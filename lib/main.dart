import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'screens/incoming_text_screen.dart';
import 'screens/transfer_screen.dart';
import 'widgets/liquid_glass.dart';
import 'widgets/send_morph_bar.dart';

const String kAppVersion = '1.2';
// Порты ниже 49152, чтобы не конфликтовать с эфемерными портами iOS.
const int kTransferPort = 14680;
const int kDiscoveryPort = 14681;
const int kChunkSize = 1024 * 1024;

/// false: выбранные файлы попадают в список «ВЫБРАНО», отправка по кнопке «Отправить (N)».
/// true: после выбора файлов отправка начинается сразу.
const bool kSendImmediately = false;

/// Собственная папка приложения для принятых файлов.
/// Android: Download/FastDrop, iPhone: «Файлы» → FastDrop → FastDrop.
Future<Directory> resolveDefaultSaveDirectory() async {
  Directory dir;
  if (Platform.isAndroid) {
    dir = Directory('/storage/emulated/0/Download/FastDrop');
  } else {
    final docs = await getApplicationDocumentsDirectory();
    dir = Directory('${docs.path}/FastDrop');
  }
  try {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  } catch (_) {
    return await getApplicationDocumentsDirectory();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FastDropApp());
}

// ───────────────────────── Модели ─────────────────────────

class TransferHistoryItem {
  final String fileName;
  final int sizeBytes;
  final String direction;
  final String savedPath;
  final DateTime timestamp;

  TransferHistoryItem({
    required this.fileName,
    required this.sizeBytes,
    required this.direction,
    required this.savedPath,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'direction': direction,
        'savedPath': savedPath,
        'timestamp': timestamp.toIso8601String(),
      };

  factory TransferHistoryItem.fromJson(Map<String, dynamic> json) {
    return TransferHistoryItem(
      fileName: json['fileName'] as String? ?? 'file',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      direction: json['direction'] as String? ?? 'Принято',
      savedPath: json['savedPath'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class DiscoveredPeer {
  final String ip;
  final String name;
  DateTime lastSeen;

  DiscoveredPeer({
    required this.ip,
    required this.name,
    required this.lastSeen,
  });
}

class OutgoingItem {
  final String relativeName;
  final String? title;
  final int sizeBytes;
  final File? file;
  final Uint8List? rawBytes;

  OutgoingItem({
    required this.relativeName,
    required this.sizeBytes,
    this.title,
    this.file,
    this.rawBytes,
  });
}

class AppSettings {
  bool isWhiteTheme;
  String? customSaveDir;
  List<TransferHistoryItem> history;

  AppSettings({
    this.isWhiteTheme = false,
    this.customSaveDir,
    List<TransferHistoryItem>? history,
  }) : history = history ?? [];
}

class SettingsStorage {
  static Future<File> _configFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/fastdrop_settings_v1_2.json');
  }

  static Future<AppSettings> load() async {
    try {
      final file = await _configFile();
      if (!await file.exists()) return AppSettings();
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final histRaw = (data['history'] as List<dynamic>? ?? [])
          .map((e) => TransferHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return AppSettings(
        isWhiteTheme: data['isWhiteTheme'] as bool? ?? false,
        customSaveDir: data['customSaveDir'] as String?,
        history: histRaw,
      );
    } catch (_) {
      return AppSettings();
    }
  }

  static Future<void> save(AppSettings settings) async {
    try {
      final file = await _configFile();
      final payload = {
        'isWhiteTheme': settings.isWhiteTheme,
        'customSaveDir': settings.customSaveDir,
        'history': settings.history.map((e) => e.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }
}

// ───────────────────────── Приложение ─────────────────────────

class FastDropApp extends StatefulWidget {
  const FastDropApp({super.key});

  @override
  State<FastDropApp> createState() => _FastDropAppState();
}

class _FastDropAppState extends State<FastDropApp> {
  final AppSettings _settings = AppSettings();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final loaded = await SettingsStorage.load();
    if (!mounted) return;
    setState(() {
      _settings.isWhiteTheme = loaded.isWhiteTheme;
      _settings.customSaveDir = loaded.customSaveDir;
      _settings.history
        ..clear()
        ..addAll(loaded.history);
      _loaded = true;
    });
  }

  Future<void> _updateTheme(bool whiteTheme) async {
    setState(() => _settings.isWhiteTheme = whiteTheme);
    await SettingsStorage.save(_settings);
  }

  Future<void> _updateSaveDir(String? path) async {
    setState(() => _settings.customSaveDir = path);
    await SettingsStorage.save(_settings);
  }

  Future<void> _addHistory(TransferHistoryItem item) async {
    setState(() {
      _settings.history.insert(0, item);
      if (_settings.history.length > 100) {
        _settings.history.removeRange(100, _settings.history.length);
      }
    });
    await SettingsStorage.save(_settings);
  }

  Future<void> _clearHistory() async {
    setState(() => _settings.history.clear());
    await SettingsStorage.save(_settings);
  }

  @override
  Widget build(BuildContext context) {
    final isWhite = _settings.isWhiteTheme;
    final p = GlassPalette(isWhite);
    final bg = isWhite ? const Color(0xFFEEF2FA) : const Color(0xFF000000);

    return MaterialApp(
      title: 'FastDrop $kAppVersion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: isWhite ? Brightness.light : Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: ColorScheme(
          brightness: isWhite ? Brightness.light : Brightness.dark,
          primary: p.accent,
          onPrimary: Colors.black,
          secondary: p.accent,
          onSecondary: Colors.black,
          error: p.danger,
          onError: Colors.white,
          surface: bg,
          onSurface: p.fg,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isWhite ? const Color(0xE6FFFFFF) : const Color(0xE61C1C24),
          contentTextStyle: TextStyle(color: p.fg, fontSize: 14),
          shape: const StadiumBorder(),
        ),
        useMaterial3: true,
      ),
      home: !_loaded
          ? LiquidBackground(
              isWhite: isWhite,
              child: const Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(child: CircularProgressIndicator()),
              ),
            )
          : TransferHomePage(
              settings: _settings,
              onThemeChanged: _updateTheme,
              onSaveDirChanged: _updateSaveDir,
              onAddHistory: _addHistory,
              onClearHistory: _clearHistory,
            ),
    );
  }
}

// ───────────────────────── Главный экран ─────────────────────────

class TransferHomePage extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<bool> onThemeChanged;
  final ValueChanged<String?> onSaveDirChanged;
  final ValueChanged<TransferHistoryItem> onAddHistory;
  final Future<void> Function() onClearHistory;

  const TransferHomePage({
    super.key,
    required this.settings,
    required this.onThemeChanged,
    required this.onSaveDirChanged,
    required this.onAddHistory,
    required this.onClearHistory,
  });

  @override
  State<TransferHomePage> createState() => _TransferHomePageState();
}

class _TransferHomePageState extends State<TransferHomePage> {
  final TextEditingController _ipController = TextEditingController(text: '172.20.10.1');
  final FocusNode _ipFocus = FocusNode();

  // Любое изменение состояния передачи увеличивает счётчик,
  // благодаря чему TransferScreen обновляется «на лету».
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  ServerSocket? _server;
  RawDatagramSocket? _udpSocket;
  Timer? _beaconTimer;
  Timer? _cleanupTimer;

  bool _isListening = false;
  bool _isTransferring = false; // идёт отправка
  bool _isReceivingNow = false; // идёт приём
  bool _transferCompleted = false;
  bool _cancelRequested = false;
  bool _receiveCancelled = false;
  bool _transferScreenOpen = false;
  bool _menuOpen = false;

  Socket? _activeSendSocket;
  Socket? _activeIncomingClient;
  String? _activeReceivedFilePath;
  String? _lastSavedPath;
  String? _lastSavedFolder;

  final List<OutgoingItem> _queuedItems = [];

  String _status = 'Готово · v$kAppVersion';
  String _currentFileName = '';
  int _currentFileIndex = 0;
  int _totalFilesCount = 0;

  double _progress = 0.0;
  double _speedMBps = 0.0;
  int _transferredBytes = 0;
  int _totalBytes = 0;
  String _etaText = '--:--';

  List<String> _myIps = [];
  final Map<String, DiscoveredPeer> _peers = {};

  bool get _busy => _isTransferring || _isReceivingNow;

  @override
  void initState() {
    super.initState();
    _initEnvironment();
  }

  /// setState + уведомление экрана передачи.
  void _ui(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _tick.value++;
  }

  void _hideKeyboard() {
    _ipFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _toast(String text, {int seconds = 1}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: Duration(seconds: seconds)),
    );
  }

  Future<void> _openReceivedFile(String path) async {
    try {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        _toast('Не удалось открыть файл: ${result.message}', seconds: 3);
      }
    } catch (e) {
      _toast('Не удалось открыть файл: $e', seconds: 3);
    }
  }

  Future<void> _openReceivedFolder() async {
    final folder = _lastSavedFolder;
    if (folder == null || folder.isEmpty) return;

    try {
      if (Platform.isIOS) {
        // Открывает приложение «Файлы» сразу в нужной папке.
        final ok = await launchUrl(Uri.parse('shareddocuments://${Uri.encodeFull(folder)}'));
        if (ok) return;
      } else if (Platform.isAndroid) {
        const root = '/storage/emulated/0/';
        if (folder.startsWith(root)) {
          final relative = folder.substring(root.length);
          final data =
              'content://com.android.externalstorage.documents/document/primary%3A${Uri.encodeComponent(relative)}';
          for (final type in const ['vnd.android.document/directory', 'resource/folder']) {
            try {
              await AndroidIntent(
                action: 'action_view',
                data: data,
                type: type,
                flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
              ).launch();
              return;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    _toast('Файлы лежат в: $folder', seconds: 4);
  }

  Future<void> _initEnvironment() async {
    await _refreshLocalIps();
    await _startUdpRadar();
    if (Platform.isAndroid) {
      try {
        await [
          Permission.storage,
          Permission.manageExternalStorage,
        ].request();
      } catch (_) {}
    }
    // Создаём папку FastDrop сразу, чтобы она была видна в файлах.
    try {
      await _resolveSaveDirectory();
    } catch (_) {}
  }

  Future<void> _refreshLocalIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final ips = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          ips.add(addr.address);
        }
      }
      if (mounted) {
        setState(() => _myIps = ips);
      }
    } catch (_) {}
  }

  // ───────────── UDP-радар ─────────────

  Future<void> _startUdpRadar() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kDiscoveryPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      _udpSocket = socket;

      socket.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data, allowMalformed: true).trim();
        if (!msg.startsWith('FASTDROP_READY|')) return;
        final senderIp = dg.address.address;
        if (_myIps.contains(senderIp)) return;
        final label = msg.substring('FASTDROP_READY|'.length);
        if (!mounted) return;
        setState(() {
          _peers[senderIp] = DiscoveredPeer(
            ip: senderIp,
            name: label.isEmpty ? 'Устройство' : label,
            lastSeen: DateTime.now(),
          );
        });
      });

      _cleanupTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        final now = DateTime.now();
        if (!mounted) return;
        final before = _peers.length;
        _peers.removeWhere((_, p) => now.difference(p.lastSeen).inSeconds > 5);
        if (_peers.length != before) setState(() {});
      });
    } catch (_) {}
  }

  void _startBroadcastingPresence() {
    _beaconTimer?.cancel();
    final osName = Platform.isIOS ? 'iPhone' : (Platform.isAndroid ? 'Android' : 'Device');
    final payload = utf8.encode('FASTDROP_READY|$osName');

    _beaconTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final sock = _udpSocket;
      if (sock == null || !_isListening) return;
      try {
        sock.send(payload, InternetAddress('255.255.255.255'), kDiscoveryPort);
      } catch (_) {}
      for (final ip in _myIps) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          final bcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          try {
            sock.send(payload, InternetAddress(bcast), kDiscoveryPort);
          } catch (_) {}
        }
      }
    });
  }

  // ───────────── Вспомогательное ─────────────

  Future<Directory> _resolveSaveDirectory() async {
    final custom = widget.settings.customSaveDir;
    if (custom != null && custom.trim().isNotEmpty) {
      try {
        final dir = Directory(custom.trim());
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir;
      } catch (_) {}
    }
    return resolveDefaultSaveDirectory();
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 Б';
    const units = ['Б', 'КБ', 'МБ', 'ГБ'];
    double v = bytes.toDouble();
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i >= 2 ? 2 : 0)} ${units[i]}';
  }

  String _formatEta(int remainingBytes, double speedMBps) {
    if (speedMBps <= 0.05 || remainingBytes <= 0) return '--:--';
    final sec = (remainingBytes / (speedMBps * 1024 * 1024)).round();
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _sanitizeRelativePath(String raw) {
    final normalized = raw.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .map((s) => s.replaceAll(RegExp(r'[:*?"<>|]'), '_'))
        .toList();
    return segments.isEmpty ? 'received_file' : segments.join('/');
  }

  Future<void> _deletePartialReceivedFile() async {
    final p = _activeReceivedFilePath;
    _activeReceivedFilePath = null;
    if (p == null || p.isEmpty) return;
    try {
      final f = File(p);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }

  IconData _iconForItem(OutgoingItem item) {
    if (item.rawBytes != null) return Icons.notes_rounded;
    if (item.relativeName.contains('/')) return Icons.folder_rounded;
    return Icons.insert_drive_file_rounded;
  }

  // ───────────── Экраны ─────────────

  void _cancelTransfer() {
    _cancelRequested = true;
    _receiveCancelled = true;
    try {
      _activeSendSocket?.destroy();
    } catch (_) {}
    try {
      _activeIncomingClient?.destroy();
    } catch (_) {}
    _ui(() {
      _isTransferring = false;
      _isReceivingNow = false;
      _speedMBps = 0.0;
      _status = 'Передача отменена';
    });
    if (mounted && _transferScreenOpen) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openTransferScreen({required bool isSender}) async {
    if (!mounted || _transferScreenOpen) return;
    _transferScreenOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ValueListenableBuilder<int>(
            valueListenable: _tick,
            builder: (_, __, ___) => TransferScreen(
              isSender: isSender,
              isTransferring: _busy,
              isCompleted: _transferCompleted,
              isCancelled: _cancelRequested,
              fileName: _currentFileName,
              currentIndex: _currentFileIndex,
              totalCount: _totalFilesCount,
              progress: _progress,
              speedMBps: _speedMBps,
              transferredBytes: _transferredBytes,
              totalBytes: _totalBytes,
              etaText: _etaText,
              statusText: _status,
              savedFilePath: _lastSavedPath,
              savedFolderPath: _lastSavedFolder,
              isWhiteTheme: widget.settings.isWhiteTheme,
              onCancel: _cancelTransfer,
              onDone: () => Navigator.of(ctx).pop(),
              onSendMore: () {
                Navigator.of(ctx).pop();
                _openSendMenu();
              },
              onOpenFile: _openReceivedFile,
              onOpenFolder: _lastSavedFolder == null ? null : _openReceivedFolder,
            ),
          ),
        ),
      );
    } finally {
      _transferScreenOpen = false;
    }
  }

  Future<void> _openIncomingText(
    String relPath,
    String fullPath,
    int sizeBytes,
    String senderIp,
  ) async {
    if (!mounted) return;
    final lower = relPath.toLowerCase();
    if (!lower.endsWith('.txt') || sizeBytes > 1024 * 1024) return;
    try {
      final content = await File(fullPath).readAsString();
      if (!mounted || content.isEmpty) return;
      if (_transferScreenOpen) {
        Navigator.of(context).pop();
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => IncomingTextScreen(
            senderName: _peers[senderIp]?.name ?? 'Устройство',
            deviceLabel: senderIp,
            messageText: content,
            isWhiteTheme: widget.settings.isWhiteTheme,
          ),
        ),
      );
    } catch (_) {}
  }

  // ───────────── Приём ─────────────

  Future<void> _toggleReceive() async {
    _hideKeyboard();
    if (_isListening) {
      _beaconTimer?.cancel();
      try {
        await _server?.close();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _server = null;
        _isListening = false;
        _status = 'Приём остановлен';
      });
      return;
    }

    await _refreshLocalIps();
    try {
      try {
        await _server?.close();
      } catch (_) {}
      final server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        kTransferPort,
        shared: true,
      );
      if (!mounted) {
        await server.close();
        return;
      }
      setState(() {
        _server = server;
        _isListening = true;
        _status = 'Ожидание подключения (порт $kTransferPort)';
        _progress = 0.0;
        _speedMBps = 0.0;
      });
      _startBroadcastingPresence();

      server.listen(
        (Socket client) {
          _handleIncomingClient(client);
        },
        onError: (Object e) {
          _ui(() => _status = 'Ошибка сервера: $e');
        },
      );
    } catch (e) {
      if (mounted) setState(() => _status = 'Ошибка приёма: $e');
    }
  }

  Future<void> _handleIncomingClient(Socket client) async {
    client.setOption(SocketOption.tcpNoDelay, true);
    final remoteIp = client.remoteAddress.address;
    _receiveCancelled = false;
    _cancelRequested = false;
    _activeIncomingClient = client;
    _activeReceivedFilePath = null;

    RandomAccessFile? raf;
    String relPath = 'received_file';
    int totalSize = 0;
    int receivedBytes = 0;
    bool headerParsed = false;
    final headerBuffer = BytesBuilder(copy: true);

    int bytesInInterval = 0;
    DateTime lastSpeedUpdate = DateTime.now();
    Directory? saveDir;

    try {
      saveDir = await _resolveSaveDirectory();

      await for (final Uint8List data in client) {
        if (_receiveCancelled) break;
        Uint8List payload = data;

        if (!headerParsed) {
          headerBuffer.add(data);
          final bytes = headerBuffer.toBytes();
          final nl = bytes.indexOf(10);
          if (nl == -1) {
            if (bytes.length > 16384) {
              throw Exception('Некорректный заголовок');
            }
            continue;
          }

          final headerLine = utf8.decode(bytes.sublist(0, nl), allowMalformed: true).trim();
          final sep = headerLine.lastIndexOf('|');
          if (sep <= 0) {
            throw Exception('Некорректный заголовок');
          }

          relPath = _sanitizeRelativePath(headerLine.substring(0, sep));
          totalSize = int.tryParse(headerLine.substring(sep + 1).trim()) ?? 0;

          final outFile = File('${saveDir.path}/$relPath');
          await outFile.parent.create(recursive: true);
          // Всегда пишем файл с нуля, чтобы повторная отправка
          // файла с тем же именем не ломалась.
          raf = await outFile.open(mode: FileMode.write);
          receivedBytes = 0;
          _activeReceivedFilePath = outFile.path;

          client.write('0\n');
          await client.flush();

          headerParsed = true;
          payload = Uint8List.sublistView(bytes, nl + 1);

          _ui(() {
            _isReceivingNow = true;
            _transferCompleted = false;
            _currentFileName = relPath;
            _currentFileIndex = 0;
            _totalFilesCount = 0;
            _totalBytes = totalSize;
            _transferredBytes = 0;
            _progress = 0.0;
            _speedMBps = 0.0;
            _etaText = '--:--';
            _status = 'Приём: $relPath';
          });
          if (!_transferScreenOpen) {
            unawaited(_openTransferScreen(isSender: false));
          }
        }

        if (payload.isNotEmpty) {
          if (_receiveCancelled) break;
          await raf!.writeFrom(payload);
          receivedBytes += payload.length;
          bytesInInterval += payload.length;

          final now = DateTime.now();
          final elapsedMs = now.difference(lastSpeedUpdate).inMilliseconds;
          if (elapsedMs >= 200 || receivedBytes >= totalSize) {
            final sec = elapsedMs > 0 ? elapsedMs / 1000.0 : 0.001;
            final speed = (bytesInInterval / (1024 * 1024)) / sec;
            bytesInInterval = 0;
            lastSpeedUpdate = now;

            _ui(() {
              _transferredBytes = receivedBytes;
              _progress = totalSize > 0 ? (receivedBytes / totalSize).clamp(0.0, 1.0).toDouble() : 0.0;
              _speedMBps = speed;
              _etaText = _formatEta(totalSize - receivedBytes, speed);
            });
          }
        }
      }

      await raf?.flush();
      await raf?.close();
      raf = null;

      if (_receiveCancelled) {
        await _deletePartialReceivedFile();
        _ui(() {
          _isReceivingNow = false;
          _status = 'Приём отменён';
          _speedMBps = 0.0;
        });
        return;
      }

      if (!headerParsed) {
        // Пустое подключение, ничего не принято.
        return;
      }

      if (totalSize > 0 && receivedBytes < totalSize) {
        throw Exception('Соединение прервано ($receivedBytes из $totalSize байт)');
      }

      final fullPath = '${saveDir.path}/$relPath';
      final finalSize = receivedBytes > 0 ? receivedBytes : totalSize;
      widget.onAddHistory(
        TransferHistoryItem(
          fileName: relPath,
          sizeBytes: finalSize,
          direction: 'Принято',
          savedPath: fullPath,
          timestamp: DateTime.now(),
        ),
      );

      _activeReceivedFilePath = null;
      _ui(() {
        _isReceivingNow = false;
        _transferCompleted = true;
        _progress = 1.0;
        _speedMBps = 0.0;
        _etaText = '00:00';
        _transferredBytes = finalSize;
        _lastSavedPath = fullPath;
        _lastSavedFolder = File(fullPath).parent.path;
        _status = 'Сохранено: $fullPath';
      });

      await _openIncomingText(relPath, fullPath, finalSize, remoteIp);
    } catch (e) {
      try {
        await raf?.close();
      } catch (_) {}
      await _deletePartialReceivedFile();
      if (_receiveCancelled) {
        _ui(() {
          _isReceivingNow = false;
          _status = 'Приём отменён';
          _speedMBps = 0.0;
        });
      } else {
        _ui(() {
          _isReceivingNow = false;
          _speedMBps = 0.0;
          _status = 'Ошибка приёма: $e';
        });
      }
    } finally {
      _activeIncomingClient = null;
      try {
        await client.close();
      } catch (_) {}
    }
  }

  // ───────────── Очередь и меню ─────────────

  void _addToQueue(List<OutgoingItem> items) {
    if (items.isEmpty) return;
    _ui(() {
      _queuedItems.addAll(items);
      _status = 'В списке: ${_queuedItems.length}';
    });
    if (kSendImmediately) {
      unawaited(_startSendingQueue());
    }
  }

  void _removeQueuedItem(int index) {
    if (_busy || index < 0 || index >= _queuedItems.length) return;
    _ui(() {
      _queuedItems.removeAt(index);
      _status = _queuedItems.isEmpty ? 'Список очищен' : 'В списке: ${_queuedItems.length}';
    });
  }

  void _clearQueuedItems() {
    if (_busy) return;
    _ui(() {
      _queuedItems.clear();
      _status = 'Готово · v$kAppVersion';
    });
  }

  Future<void> _openSendMenu() async {
    _hideKeyboard();
    if (_busy) return;
    setState(() => _menuOpen = true);
  }

  void _menuAction(VoidCallback action) {
    setState(() => _menuOpen = false);
    action();
  }

  OutgoingItem _textItem(String text, String label) {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final preview = oneLine.length > 40 ? '${oneLine.substring(0, 40)}…' : oneLine;
    return OutgoingItem(
      relativeName: '${stamp}_$label',
      title: 'Текст: $preview',
      sizeBytes: bytes.length,
      rawBytes: bytes,
    );
  }

  Future<void> _enqueueClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      _ui(() => _status = 'Буфер обмена пуст');
      return;
    }
    _addToQueue([_textItem(text, 'clipboard.txt')]);
  }

  Future<void> _enqueueTextComposer() async {
    final isWhite = widget.settings.isWhiteTheme;
    final p = GlassPalette(isWhite);
    final controller = TextEditingController();

    final text = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: GlassCard(
          isWhite: isWhite,
          radius: 32,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Отправить текст',
                style: TextStyle(color: p.fg, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              GlassTextField(
                controller: controller,
                isWhite: isWhite,
                hint: 'Введите текст или ссылку...',
                maxLines: 6,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: 'Отмена',
                      isWhite: isWhite,
                      expand: true,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassButton(
                      label: 'Добавить',
                      isWhite: isWhite,
                      active: true,
                      expand: true,
                      onPressed: () => Navigator.pop(ctx, controller.text),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (text != null && text.trim().isNotEmpty) {
      _addToQueue([_textItem(text, 'message.txt')]);
    }
  }

  Future<void> _enqueueFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return;

    final items = <OutgoingItem>[];
    for (final f in result.files) {
      if (f.path == null) continue;
      final file = File(f.path!);
      if (await file.exists()) {
        final len = await file.length();
        items.add(OutgoingItem(relativeName: f.name, sizeBytes: len, file: file));
      }
    }
    _addToQueue(items);
  }

  Future<void> _enqueueFolder() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null || dirPath.trim().isEmpty) return;

    final rootDir = Directory(dirPath);
    if (!await rootDir.exists()) return;

    final folderName = rootDir.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'folder';
    final normalizedRoot = rootDir.path.replaceAll('\\', '/');
    final prefix = normalizedRoot.endsWith('/') ? normalizedRoot : '$normalizedRoot/';

    final items = <OutgoingItem>[];
    await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final path = entity.path.replaceAll('\\', '/');
        final rel = path.startsWith(prefix) ? path.substring(prefix.length) : entity.uri.pathSegments.last;
        final len = await entity.length();
        items.add(
          OutgoingItem(
            relativeName: '$folderName/$rel',
            sizeBytes: len,
            file: entity,
          ),
        );
      }
    }

    if (items.isEmpty) {
      _ui(() => _status = 'Выбранная папка пуста');
      return;
    }
    _addToQueue(items);
  }

  // ───────────── Отправка ─────────────

  Future<void> _startSendingQueue() async {
    _hideKeyboard();
    if (_busy) return;

    if (_queuedItems.isEmpty) {
      await _openSendMenu();
      return;
    }

    final host = _ipController.text.trim();
    if (host.isEmpty) {
      _ui(() => _status = 'Укажите IP получателя — список сохранён');
      return;
    }

    await _sendItemsQueue(host, List<OutgoingItem>.from(_queuedItems));
  }

  Future<void> _sendItemsQueue(String host, List<OutgoingItem> items) async {
    if (_busy) return;

    _cancelRequested = false;
    final sent = <OutgoingItem>[];

    _ui(() {
      _menuOpen = false;
      _isTransferring = true;
      _transferCompleted = false;
      _totalFilesCount = items.length;
      _currentFileIndex = 0;
      _currentFileName = '';
      _progress = 0.0;
      _speedMBps = 0.0;
      _transferredBytes = 0;
      _totalBytes = 0;
      _etaText = '--:--';
      _status = 'Подключение...';
    });
    unawaited(_openTransferScreen(isSender: true));

    try {
      for (int i = 0; i < items.length; i++) {
        if (_cancelRequested) break;
        _ui(() => _currentFileIndex = i + 1);
        await _sendSingleItem(host, items[i]);
        sent.add(items[i]);
      }

      if (_cancelRequested) {
        _ui(() {
          _queuedItems.removeWhere((q) => sent.contains(q));
          _status = 'Передача отменена';
        });
      } else {
        _ui(() {
          _queuedItems.removeWhere((q) => sent.contains(q));
          _progress = 1.0;
          _speedMBps = 0.0;
          _etaText = '00:00';
          _transferCompleted = true;
          _status = sent.length == 1 ? 'Отправлено' : 'Отправлено элементов: ${sent.length}';
        });
      }
    } catch (e) {
      _ui(() {
        _queuedItems.removeWhere((q) => sent.contains(q));
        _speedMBps = 0.0;
        _status = _cancelRequested ? 'Передача отменена' : 'Ошибка отправки: $e';
      });
    } finally {
      _activeSendSocket = null;
      _ui(() => _isTransferring = false);
    }
  }

  Future<void> _sendSingleItem(String host, OutgoingItem item) async {
    _ui(() {
      _currentFileName = item.title ?? item.relativeName;
      _totalBytes = item.sizeBytes;
      _transferredBytes = 0;
      _progress = 0.0;
      _speedMBps = 0.0;
      _etaText = '--:--';
      _status = 'Отправка ($_currentFileIndex/$_totalFilesCount)';
    });

    Socket? socket;
    RandomAccessFile? raf;
    StreamSubscription<Uint8List>? sub;

    try {
      socket = await Socket.connect(
        host,
        kTransferPort,
        timeout: const Duration(seconds: 6),
      );
      _activeSendSocket = socket;
      socket.setOption(SocketOption.tcpNoDelay, true);

      final completer = Completer<int>();
      final respBuilder = BytesBuilder(copy: true);
      bool gotOffset = false;

      // Подписка живёт до конца передачи, ответ получателя читаем один раз.
      sub = socket.listen(
        (Uint8List chunk) {
          if (gotOffset) return;
          respBuilder.add(chunk);
          final bytes = respBuilder.toBytes();
          final nl = bytes.indexOf(10);
          if (nl != -1) {
            gotOffset = true;
            final offsetStr = utf8.decode(bytes.sublist(0, nl), allowMalformed: true).trim();
            if (!completer.isCompleted) {
              completer.complete(int.tryParse(offsetStr) ?? 0);
            }
          }
        },
        onError: (Object e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.completeError(Exception('Получатель закрыл соединение'));
          }
        },
        cancelOnError: true,
      );

      socket.write('${item.relativeName}|${item.sizeBytes}\n');
      await socket.flush();

      final startOffset = await completer.future.timeout(const Duration(seconds: 10));

      int sentBytes = startOffset.clamp(0, item.sizeBytes).toInt();
      int bytesInInterval = 0;
      DateTime lastSpeedUpdate = DateTime.now();

      if (item.rawBytes != null) {
        final raw = item.rawBytes!;
        if (sentBytes < raw.length) {
          socket.add(Uint8List.sublistView(raw, sentBytes));
          await socket.flush();
          sentBytes = raw.length;
        }
        _ui(() {
          _transferredBytes = sentBytes;
          _progress = 1.0;
          _etaText = '00:00';
        });
      } else if (item.file != null) {
        raf = await item.file!.open(mode: FileMode.read);
        await raf.setPosition(sentBytes);

        while (sentBytes < item.sizeBytes) {
          if (_cancelRequested) throw Exception('Отменено');
          final remaining = item.sizeBytes - sentBytes;
          final toRead = remaining < kChunkSize ? remaining : kChunkSize;
          final buffer = await raf.read(toRead);
          if (buffer.isEmpty) break;

          socket.add(buffer);
          await socket.flush();

          sentBytes += buffer.length;
          bytesInInterval += buffer.length;

          final now = DateTime.now();
          final elapsedMs = now.difference(lastSpeedUpdate).inMilliseconds;
          if (elapsedMs >= 200 || sentBytes >= item.sizeBytes) {
            final sec = elapsedMs > 0 ? elapsedMs / 1000.0 : 0.001;
            final speed = (bytesInInterval / (1024 * 1024)) / sec;
            bytesInInterval = 0;
            lastSpeedUpdate = now;

            _ui(() {
              _transferredBytes = sentBytes;
              _progress = item.sizeBytes > 0
                  ? (sentBytes / item.sizeBytes).clamp(0.0, 1.0).toDouble()
                  : 0.0;
              _speedMBps = speed;
              _etaText = _formatEta(item.sizeBytes - sentBytes, speed);
            });
          }
        }
        await raf.close();
        raf = null;
      }

      await socket.flush();
      await socket.close();

      widget.onAddHistory(
        TransferHistoryItem(
          fileName: item.relativeName,
          sizeBytes: item.sizeBytes,
          direction: 'Отправлено',
          savedPath: host,
          timestamp: DateTime.now(),
        ),
      );
    } catch (e) {
      try {
        await raf?.close();
      } catch (_) {}
      socket?.destroy();
      rethrow;
    } finally {
      try {
        await sub?.cancel();
      } catch (_) {}
    }
  }

  // ───────────── Настройки ─────────────

  void _openSettings() {
    _hideKeyboard();
    if (_menuOpen) setState(() => _menuOpen = false);
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => _SwipeToClose(
          child: SettingsPage(
            settings: widget.settings,
            onThemeChanged: widget.onThemeChanged,
            onSaveDirChanged: widget.onSaveDirChanged,
            onClearHistory: widget.onClearHistory,
          ),
        ),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _beaconTimer?.cancel();
    _cleanupTimer?.cancel();
    _udpSocket?.close();
    _ipController.dispose();
    _ipFocus.dispose();
    _server?.close();
    _tick.dispose();
    super.dispose();
  }

  // ───────────── UI ─────────────

  Widget _buildTopBar(bool isWhite, GlassPalette p) {
    return Row(
      children: [
        GlassIconButton(
          icon: Icons.menu_rounded,
          isWhite: isWhite,
          onTap: _openSettings,
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'FastDrop',
                style: TextStyle(
                  color: p.fg,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'v$kAppVersion',
                style: TextStyle(color: p.subtle, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        GlassIconButton(
          icon: isWhite ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          isWhite: isWhite,
          onTap: () => widget.onThemeChanged(!isWhite),
        ),
        const SizedBox(width: 10),
        GlassIconButton(
          icon: Icons.refresh_rounded,
          isWhite: isWhite,
          onTap: _refreshLocalIps,
        ),
      ],
    );
  }

  Widget _buildIpCard(bool isWhite, GlassPalette p) {
    return GlassCard(
      isWhite: isWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassLabel('МОЙ IP', isWhite: isWhite),
          const SizedBox(height: 12),
          if (_myIps.isEmpty)
            Text('Нет сети', style: TextStyle(color: p.subtle, fontSize: 14))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _myIps.map((ip) {
                return GlassChip(
                  label: ip,
                  mono: true,
                  isWhite: isWhite,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: ip));
                    _toast('Скопировано: $ip');
                  },
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildPeersCard(bool isWhite, GlassPalette p) {
    return GlassCard(
      isWhite: isWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassLabel('НАЙДЕНЫ', isWhite: isWhite),
          const SizedBox(height: 6),
          ..._peers.values.map((peer) {
            final selected = _ipController.text.trim() == peer.ip;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _ipController.text = peer.ip),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      peer.name == 'iPhone' ? Icons.phone_iphone_rounded : Icons.phone_android_rounded,
                      color: selected ? p.accent : p.fg,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            peer.name,
                            style: TextStyle(
                              color: p.fg,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            peer.ip,
                            style: TextStyle(
                              color: p.subtle,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected) Icon(Icons.check_circle_rounded, color: p.accent, size: 22),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildQueueCard(bool isWhite, GlassPalette p) {
    return GlassCard(
      isWhite: isWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GlassLabel('ВЫБРАНО (${_queuedItems.length})', isWhite: isWhite),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassChip(
                    label: 'Добавить',
                    icon: Icons.add_rounded,
                    isWhite: isWhite,
                    onTap: _busy ? null : _openSendMenu,
                  ),
                  if (!_busy) ...[
                    const SizedBox(width: 8),
                    GlassChip(
                      label: 'Очистить',
                      isWhite: isWhite,
                      onTap: _clearQueuedItems,
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...List.generate(_queuedItems.length, (index) {
            final item = _queuedItems[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(_iconForItem(item), size: 22, color: p.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title ?? item.relativeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.fg,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _formatSize(item.sizeBytes),
                          style: TextStyle(
                            color: p.subtle,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_busy)
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 20, color: p.subtle),
                      tooltip: 'Удалить из списка',
                      onPressed: () => _removeQueuedItem(index),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool isWhite, GlassPalette p) {
    final isError = _status.startsWith('Ошибка');
    return GlassCard(
      isWhite: isWhite,
      padding: const EdgeInsets.all(20),
      onTap: _busy ? () => _openTransferScreen(isSender: _isTransferring) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_speedMBps.toStringAsFixed(1)} МБ/с',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: p.accent,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                _etaText,
                style: TextStyle(fontSize: 16, fontFamily: 'monospace', color: p.subtle),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GlassProgressBar(
            value: _progress,
            isWhite: isWhite,
            color: isError ? p.danger : null,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(_progress * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: p.fg, fontSize: 12),
              ),
              Text(
                '${_formatSize(_transferredBytes)} / ${_formatSize(_totalBytes)}',
                style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: p.subtle),
              ),
            ],
          ),
          if (_currentFileName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _currentFileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: p.subtle),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _status,
            style: TextStyle(fontSize: 12, color: isError ? p.danger : p.fg),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWhite = widget.settings.isWhiteTheme;
    final p = GlassPalette(isWhite);

    return LiquidBackground(
      isWhite: isWhite,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _hideKeyboard();
          if (_menuOpen) setState(() => _menuOpen = false);
        },
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v > 350) _openSettings();
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(isWhite, p),
                  const SizedBox(height: 18),
                  _buildIpCard(isWhite, p),
                  const SizedBox(height: 18),
                  Center(
                    child: GlassButton(
                      label: _isListening ? 'Принимаю' : 'Принять',
                      icon: _isListening ? Icons.stop_rounded : Icons.download_rounded,
                      active: _isListening,
                      isWhite: isWhite,
                      onPressed: _toggleReceive,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_peers.isNotEmpty) ...[
                    _buildPeersCard(isWhite, p),
                    const SizedBox(height: 16),
                  ],
                  GlassTextField(
                    controller: _ipController,
                    focusNode: _ipFocus,
                    isWhite: isWhite,
                    label: 'IP получателя',
                    hint: '172.20.10.1',
                    mono: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onSubmitted: (_) => _hideKeyboard(),
                    suffix: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.paste_rounded, color: p.subtle),
                          tooltip: 'Вставить',
                          onPressed: () async {
                            final data = await Clipboard.getData('text/plain');
                            if (data?.text != null) {
                              setState(() => _ipController.text = data!.text!.trim());
                            }
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.keyboard_hide_rounded, color: p.subtle),
                          tooltip: 'Скрыть клавиатуру',
                          onPressed: _hideKeyboard,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      GlassChip(
                        label: '.',
                        isWhite: isWhite,
                        onTap: () {
                          _ipController.text = '${_ipController.text}.';
                          _ipController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _ipController.text.length),
                          );
                        },
                      ),
                      GlassChip(
                        label: '172.20.10.1',
                        isWhite: isWhite,
                        onTap: () => setState(() => _ipController.text = '172.20.10.1'),
                      ),
                      GlassChip(
                        label: '192.168.1.',
                        isWhite: isWhite,
                        onTap: () {
                          _ipController.text = '192.168.1.';
                          _ipController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _ipController.text.length),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_queuedItems.isNotEmpty) ...[
                    _buildQueueCard(isWhite, p),
                    const SizedBox(height: 16),
                  ],
                  SendMorphBar(
                    expanded: _menuOpen && !_busy,
                    enabled: !_busy,
                    active: _isTransferring,
                    isWhite: isWhite,
                    label: _queuedItems.isEmpty ? 'Отправить' : 'Отправить (${_queuedItems.length})',
                    icon: Icons.upload_rounded,
                    onPressed: _startSendingQueue,
                    onClose: () => setState(() => _menuOpen = false),
                    items: [
                      MorphMenuItem(
                        label: 'Вставить',
                        icon: Icons.content_paste_rounded,
                        onTap: () => _menuAction(_enqueueClipboard),
                      ),
                      MorphMenuItem(
                        label: 'Текст',
                        icon: Icons.notes_rounded,
                        onTap: () => _menuAction(_enqueueTextComposer),
                      ),
                      MorphMenuItem(
                        label: 'Файл',
                        icon: Icons.insert_drive_file_rounded,
                        onTap: () => _menuAction(_enqueueFiles),
                      ),
                      MorphMenuItem(
                        label: 'Папка',
                        icon: Icons.folder_rounded,
                        onTap: () => _menuAction(_enqueueFolder),
                      ),
                    ],
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          GlassButton(
                            label: 'Экран передачи',
                            icon: Icons.open_in_full_rounded,
                            isWhite: isWhite,
                            onPressed: () => _openTransferScreen(isSender: _isTransferring),
                          ),
                          GlassButton(
                            label: 'Отмена',
                            icon: Icons.close_rounded,
                            danger: true,
                            isWhite: isWhite,
                            onPressed: _cancelTransfer,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _buildStatusCard(isWhite, p),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Свайп влево закрывает экран настроек.
class _SwipeToClose extends StatelessWidget {
  final Widget child;
  const _SwipeToClose({required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -350) Navigator.of(context).maybePop();
      },
      child: child,
    );
  }
}

// ───────────────────────── Настройки ─────────────────────────

class SettingsPage extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<bool> onThemeChanged;
  final ValueChanged<String?> onSaveDirChanged;
  final Future<void> Function() onClearHistory;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onThemeChanged,
    required this.onSaveDirChanged,
    required this.onClearHistory,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _dirController;
  late bool _whiteTheme;

  @override
  void initState() {
    super.initState();
    _whiteTheme = widget.settings.isWhiteTheme;
    _dirController = TextEditingController(text: widget.settings.customSaveDir ?? '');
  }

  @override
  void dispose() {
    _dirController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    try {
      final selected = await FilePicker.platform.getDirectoryPath();
      if (selected != null && selected.isNotEmpty) {
        _dirController.text = selected;
        widget.onSaveDirChanged(selected);
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  String _formatBytes(int b) {
    if (b <= 0) return '0 Б';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} КБ';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(2)} МБ';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
  }

  @override
  Widget build(BuildContext context) {
    final isWhite = _whiteTheme;
    final p = GlassPalette(isWhite);
    final history = widget.settings.history;

    return LiquidBackground(
      isWhite: isWhite,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Row(
                children: [
                  GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    isWhite: isWhite,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      'Настройки · v$kAppVersion',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: p.fg,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
              const SizedBox(height: 18),
              GlassCard(
                isWhite: isWhite,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Белый фон',
                            style: TextStyle(
                              color: p.fg,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _whiteTheme ? 'Включён белый фон' : 'Включён OLED-чёрный фон',
                            style: TextStyle(color: p.subtle, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _whiteTheme,
                      activeColor: Colors.white,
                      activeTrackColor: p.accent,
                      onChanged: (val) {
                        setState(() => _whiteTheme = val);
                        widget.onThemeChanged(val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassCard(
                isWhite: isWhite,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassLabel('ПАПКА СОХРАНЕНИЯ', isWhite: isWhite),
                    const SizedBox(height: 12),
                    GlassTextField(
                      controller: _dirController,
                      isWhite: isWhite,
                      hint: Platform.isAndroid ? 'По умолчанию: Download/FastDrop' : 'По умолчанию: папка FastDrop',
                      onSubmitted: (val) =>
                          widget.onSaveDirChanged(val.trim().isEmpty ? null : val.trim()),
                      suffix: IconButton(
                        icon: Icon(Icons.folder_open_rounded, color: p.subtle),
                        onPressed: _pickFolder,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        GlassChip(
                          label: 'Выбрать папку',
                          icon: Icons.folder_rounded,
                          isWhite: isWhite,
                          onTap: _pickFolder,
                        ),
                        if (Platform.isAndroid)
                          GlassChip(
                            label: '/storage/emulated/0/Download',
                            isWhite: isWhite,
                            onTap: () {
                              const path = '/storage/emulated/0/Download';
                              _dirController.text = path;
                              widget.onSaveDirChanged(path);
                            },
                          ),
                        GlassChip(
                          label: 'По умолчанию',
                          isWhite: isWhite,
                          onTap: () {
                            _dirController.clear();
                            widget.onSaveDirChanged(null);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassCard(
                isWhite: isWhite,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GlassLabel('ИСТОРИЯ (${history.length})', isWhite: isWhite),
                        if (history.isNotEmpty)
                          GlassChip(
                            label: 'Очистить',
                            isWhite: isWhite,
                            onTap: () async {
                              await widget.onClearHistory();
                              if (mounted) setState(() {});
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (history.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'История пока пуста',
                          style: TextStyle(color: p.subtle, fontSize: 14),
                        ),
                      )
                    else
                      ...history.map((item) {
                        final dt =
                            '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}';
                        final received = item.direction == 'Принято';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            children: [
                              Icon(
                                received ? Icons.download_done_rounded : Icons.check_circle_outline_rounded,
                                size: 22,
                                color: received ? p.accent : p.success,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.fg,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${item.direction} · ${_formatBytes(item.sizeBytes)} · $dt',
                                      style: TextStyle(color: p.subtle, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}