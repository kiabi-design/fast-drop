import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const String kAppVersion = '1.2';
const int kTransferPort = 14680;
const int kDiscoveryPort = 14681;
const int kChunkSize = 1024 * 1024;
const BorderRadius kPillRadius = BorderRadius.all(Radius.circular(24));

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FastDropApp());
}

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
  final int sizeBytes;
  final File? file;
  final Uint8List? rawBytes;

  OutgoingItem({
    required this.relativeName,
    required this.sizeBytes,
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
    final bg = isWhite ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    final surface = isWhite ? const Color(0xFFF4F5F7) : const Color(0xFF0A0A0C);
    final fg = isWhite ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);

    return MaterialApp(
      title: 'FastDrop $kAppVersion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: isWhite ? Brightness.light : Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme(
          brightness: isWhite ? Brightness.light : Brightness.dark,
          primary: fg,
          onPrimary: bg,
          secondary: isWhite ? const Color(0xFF007AFF) : const Color(0xFF64D2FF),
          onSecondary: Colors.black,
          error: Colors.redAccent,
          onError: Colors.white,
          surface: surface,
          onSurface: fg,
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: kPillRadius),
        ),
        useMaterial3: true,
      ),
      home: !_loaded
          ? Scaffold(backgroundColor: bg, body: const Center(child: CircularProgressIndicator()))
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

class LiquidGlassButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final bool isWhiteTheme;
  final VoidCallback? onPressed;

  const LiquidGlassButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isWhiteTheme,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = Platform.isIOS;
    final accent = isWhiteTheme ? const Color(0xFF007AFF) : const Color(0xFF64D2FF);
    final textColor = active
        ? accent
        : (isWhiteTheme ? const Color(0xFF0A0A0A) : Colors.white);

    final glassFill = isWhiteTheme
        ? Colors.white.withOpacity(active ? 0.85 : 0.65)
        : Colors.white.withOpacity(active ? 0.18 : 0.09);

    final borderColor = active
        ? accent.withOpacity(0.75)
        : (isWhiteTheme
            ? Colors.black.withOpacity(0.14)
            : Colors.white.withOpacity(0.24));

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: glassFill,
        borderRadius: kPillRadius,
        border: Border.all(color: borderColor, width: 1.1),
        boxShadow: isIos
            ? [
                BoxShadow(
                  color: active
                      ? accent.withOpacity(0.22)
                      : (isWhiteTheme
                          ? Colors.black.withOpacity(0.08)
                          : Colors.black.withOpacity(0.55)),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );

    final wrapped = isIos
        ? ClipRRect(
            borderRadius: kPillRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: content,
            ),
          )
        : content;

    return Opacity(
      opacity: onPressed == null ? 0.45 : 1.0,
      child: InkWell(
        borderRadius: kPillRadius,
        onTap: onPressed,
        child: wrapped,
      ),
    );
  }
}

class SendChoiceCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isWhiteTheme;
  final VoidCallback onTap;

  const SendChoiceCard({
    super.key,
    required this.label,
    required this.icon,
    required this.isWhiteTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = Platform.isIOS;

    if (isIos) {
      final glassBg = isWhiteTheme
          ? Colors.white.withOpacity(0.62)
          : Colors.white.withOpacity(0.10);
      final borderCol = isWhiteTheme
          ? Colors.black.withOpacity(0.14)
          : Colors.white.withOpacity(0.24);
      final fgCol = isWhiteTheme ? const Color(0xFF0A0A0A) : Colors.white;

      return ClipRRect(
        borderRadius: kPillRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: InkWell(
            borderRadius: kPillRadius,
            onTap: onTap,
            child: Container(
              height: 92,
              decoration: BoxDecoration(
                color: glassBg,
                borderRadius: kPillRadius,
                border: Border.all(color: borderCol, width: 1.1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isWhiteTheme ? 0.06 : 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 26, color: fgCol),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: fgCol,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final tileBg = isWhiteTheme ? const Color(0xFF9CE3DE) : const Color(0xFF8BE0D8);
    const tileFg = Color(0xFF071312);

    return InkWell(
      borderRadius: kPillRadius,
      onTap: onTap,
      child: Container(
        height: 92,
        decoration: BoxDecoration(
          color: tileBg,
          borderRadius: kPillRadius,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: tileFg),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: tileFg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

  ServerSocket? _server;
  RawDatagramSocket? _udpSocket;
  Timer? _beaconTimer;
  Timer? _cleanupTimer;

  bool _isListening = false;
  bool _isTransferring = false;
  bool _cancelRequested = false;
  Socket? _activeSendSocket;
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

  @override
  void initState() {
    super.initState();
    _initEnvironment();
  }
  void _resetTransferCard({String? nextStatus}) {
    setState(() {
      _currentFileName = '';
      _currentFileIndex = 0;
      _totalFilesCount = 0;
      _progress = 0.0;
      _speedMBps = 0.0;
      _transferredBytes = 0;
      _totalBytes = 0;
      _etaText = '--:--';
      if (nextStatus != null) {
        _status = nextStatus;
      }
    });
  }

  void _cancelTransfer() {
    _cancelRequested = true;
    try {
      _activeSendSocket?.destroy();
    } catch (_) {}
    setState(() {
      _status = 'Отмена передачи...';
    });
  }

  void _removeQueuedItem(int index) {
    if (_isTransferring || index < 0 || index >= _queuedItems.length) return;
    setState(() {
      _queuedItems.removeAt(index);
      if (_queuedItems.isEmpty) {
        _status = 'Очередь очищена';
      }
    });
  }

  void _clearQueuedItems() {
    if (_isTransferring) return;
    setState(() {
      _queuedItems.clear();
      _status = 'Готово · v$kAppVersion';
    });
  }

  Future<void> _addFilesToQueue() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return;

    final added = <OutgoingItem>[];
    for (final f in result.files) {
      if (f.path == null) continue;
      final file = File(f.path!);
      if (await file.exists()) {
        final len = await file.length();
        added.add(OutgoingItem(relativeName: f.name, sizeBytes: len, file: file));
      }
    }
    if (added.isEmpty) return;

    setState(() {
      _queuedItems.addAll(added);
      _status = 'Выбрано элементов: ${_queuedItems.length}';
    });
  }

  Future<void> _addFolderToQueue() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null || dirPath.trim().isEmpty) return;

    final rootDir = Directory(dirPath);
    if (!await rootDir.exists()) return;

    final folderName = rootDir.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'folder';
    final normalizedRoot = rootDir.path.replaceAll('\\', '/');
    final prefix = normalizedRoot.endsWith('/') ? normalizedRoot : '$normalizedRoot/';

    final added = <OutgoingItem>[];
    await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final p = entity.path.replaceAll('\\', '/');
        final rel = p.startsWith(prefix) ? p.substring(prefix.length) : entity.uri.pathSegments.last;
        final len = await entity.length();
        added.add(
          OutgoingItem(
            relativeName: '$folderName/$rel',
            sizeBytes: len,
            file: entity,
          ),
        );
      }
    }

    if (added.isEmpty) {
      setState(() => _status = 'Выбранная папка пуста');
      return;
    }

    setState(() {
      _queuedItems.addAll(added);
      _status = 'Добавлено из папки: ${added.length}';
    });
  }

  Future<void> _startSendingQueue() async {
    _hideKeyboard();
    if (_isTransferring) return;

    final host = _ipController.text.trim();
    if (host.isEmpty) {
      setState(() => _status = 'Укажите IP получателя — очередь сохранена');
      return;
    }

    if (_queuedItems.isEmpty) {
      await _openSendMenu();
      return;
    }

    final snapshot = List<OutgoingItem>.from(_queuedItems);
    _cancelRequested = false;

    setState(() {
      _isTransferring = true;
      _totalFilesCount = snapshot.length;
    });

    final sentItems = <OutgoingItem>[];

    try {
      for (int i = 0; i < snapshot.length; i++) {
        if (_cancelRequested) {
          throw Exception('Передача отменена');
        }
        setState(() => _currentFileIndex = i + 1);
        await _sendSingleItem(host, snapshot[i]);
        sentItems.add(snapshot[i]);
      }

      setState(() {
        _queuedItems.removeWhere((item) => sentItems.contains(item));
        _progress = 1.0;
        _speedMBps = 0.0;
        _etaText = '00:00';
        _status = sentItems.length == 1 ? 'Файл отправлен' : 'Отправлено элементов: ${sentItems.length}';
      });
    } catch (e) {
      setState(() {
        _queuedItems.removeWhere((item) => sentItems.contains(item));
        _speedMBps = 0.0;
        _status = _cancelRequested ? 'Передача отменена' : 'Ошибка отправки: $e';
      });
    } finally {
      _activeSendSocket = null;
      _cancelRequested = false;
      setState(() {
        _isTransferring = false;
        _totalFilesCount = 0;
      });
    }
  }

  void _hideKeyboard() {
    _ipFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _initEnvironment() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
      ].request();
    }
    await _refreshLocalIps();
    await _startUdpRadar();
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

  Future<void> _startUdpRadar() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kDiscoveryPort,
        reuseAddress: true,
      );
      _udpSocket!.broadcastEnabled = true;

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final dg = _udpSocket!.receive();
          if (dg == null) return;
          final msg = utf8.decode(dg.data, allowMalformed: true).trim();
          if (msg.startsWith('FASTDROP_READY|')) {
            final senderIp = dg.address.address;
            if (_myIps.contains(senderIp)) return;
            final label = msg.substring('FASTDROP_READY|'.length);
            if (mounted) {
              setState(() {
                _peers[senderIp] = DiscoveredPeer(
                  ip: senderIp,
                  name: label.isEmpty ? 'Устройство' : label,
                  lastSeen: DateTime.now(),
                );
              });
            }
          }
        }
      });

      _cleanupTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        final now = DateTime.now();
        if (mounted) {
          setState(() {
            _peers.removeWhere((_, p) => now.difference(p.lastSeen).inSeconds > 5);
          });
        }
      });
    } catch (_) {}
  }

  void _startBroadcastingPresence() {
    _beaconTimer?.cancel();
    final osName = Platform.isIOS ? 'iPhone' : (Platform.isAndroid ? 'Android' : 'Device');
    final payload = utf8.encode('FASTDROP_READY|$osName');

    _beaconTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_udpSocket == null || !_isListening) return;
      try {
        _udpSocket!.send(payload, InternetAddress('255.255.255.255'), kDiscoveryPort);
      } catch (_) {}
      for (final ip in _myIps) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          final bcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          try {
            _udpSocket!.send(payload, InternetAddress(bcast), kDiscoveryPort);
          } catch (_) {}
        }
      }
    });
  }

  Future<Directory> _resolveSaveDirectory() async {
    final custom = widget.settings.customSaveDir;
    if (custom != null && custom.trim().isNotEmpty) {
      final dir = Directory(custom.trim());
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    if (Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) return downloads;
    }
    return await getApplicationDocumentsDirectory();
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

  Future<void> _toggleReceive() async {
    _hideKeyboard();
    if (_isListening) {
      _beaconTimer?.cancel();
      await _server?.close();
      setState(() {
        _server = null;
        _isListening = false;
        _status = 'Приём остановлен';
      });
      return;
    }

    await _refreshLocalIps();
    try {
      final server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        kTransferPort,
        shared: true,
      );
      setState(() {
        _server = server;
        _isListening = true;
        _status = 'Ожидание подключения (порт $kTransferPort)';
        _progress = 0.0;
        _speedMBps = 0.0;
      });
      _startBroadcastingPresence();

      server.listen((Socket client) async {
        await _handleIncomingClient(client);
      });
    } catch (e) {
      setState(() => _status = 'Ошибка приёма: $e');
    }
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

  Future<void> _handleIncomingClient(Socket client) async {
    client.setOption(SocketOption.tcpNoDelay, true);
    final saveDir = await _resolveSaveDirectory();

    RandomAccessFile? raf;
    String relPath = 'received_file';
    int totalSize = 0;
    int receivedBytes = 0;
    bool headerParsed = false;
    final headerBuffer = BytesBuilder(copy: false);

    int bytesInInterval = 0;
    DateTime lastSpeedUpdate = DateTime.now();

    try {
      await for (final Uint8List data in client) {
        int offset = 0;

        if (!headerParsed) {
          headerBuffer.add(data);
          final bytes = headerBuffer.toBytes();
          final nl = bytes.indexOf(10);
          if (nl == -1) continue;

          final headerLine = utf8.decode(bytes.sublist(0, nl)).trim();
          final parts = headerLine.split('|');
          if (parts.length < 2) {
            throw Exception('Некорректный заголовок');
          }

          relPath = _sanitizeRelativePath(parts[0]);
          totalSize = int.tryParse(parts[1]) ?? 0;

          final outFile = File('${saveDir.path}/$relPath');
          await outFile.parent.create(recursive: true);
          raf = await outFile.open(mode: FileMode.writeOnlyAppend);
          receivedBytes = await raf.length();

          client.write('$receivedBytes\n');
          await client.flush();

          headerParsed = true;
          offset = nl + 1;

          setState(() {
            _currentFileName = relPath;
            _totalBytes = totalSize;
            _transferredBytes = receivedBytes;
            _status = 'Приём: $relPath';
          });
        }

        if (offset < data.length) {
          final chunk = Uint8List.sublistView(data, offset);
          await raf!.writeFrom(chunk);
          receivedBytes += chunk.length;
          bytesInInterval += chunk.length;

          final now = DateTime.now();
          final elapsedMs = now.difference(lastSpeedUpdate).inMilliseconds;
          if (elapsedMs >= 200 || receivedBytes >= totalSize) {
            final sec = elapsedMs > 0 ? elapsedMs / 1000.0 : 0.001;
            final speed = (bytesInInterval / (1024 * 1024)) / sec;
            bytesInInterval = 0;
            lastSpeedUpdate = now;

            setState(() {
              _transferredBytes = receivedBytes;
              _progress = totalSize > 0 ? (receivedBytes / totalSize).clamp(0.0, 1.0) : 0.0;
              _speedMBps = speed;
              _etaText = _formatEta(totalSize - receivedBytes, speed);
            });
          }
        }
      }

      await raf?.flush();
      await raf?.close();

      final fullPath = '${saveDir.path}/$relPath';
      widget.onAddHistory(
        TransferHistoryItem(
          fileName: relPath,
          sizeBytes: receivedBytes > 0 ? receivedBytes : totalSize,
          direction: 'Принято',
          savedPath: fullPath,
          timestamp: DateTime.now(),
        ),
      );

      setState(() {
        _progress = 1.0;
        _speedMBps = 0.0;
        _etaText = '00:00';
        _status = 'Сохранено: $fullPath';
      });
    } catch (e) {
      await raf?.close();
      setState(() => _status = 'Ошибка приёма: $e');
    } finally {
      await client.close();
    }
  }

  Future<void> _openSendMenu() async {
    _hideKeyboard();
    if (_isTransferring) return;

    final host = _ipController.text.trim();
    if (host.isEmpty) {
      setState(() => _status = 'Укажите IP получателя');
      return;
    }

    final isWhite = widget.settings.isWhiteTheme;
    final isIos = Platform.isIOS;
    final sheetBg = isIos
        ? (isWhite ? Colors.white.withOpacity(0.78) : const Color(0xFF0E1116).withOpacity(0.82))
        : (isWhite ? const Color(0xFFF6F7F9) : const Color(0xFF0B1110));
    final fg = isWhite ? const Color(0xFF0A0A0A) : Colors.white;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        Widget panel = Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: isWhite ? Colors.black12 : Colors.white12,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: fg.withOpacity(0.25),
                  borderRadius: kPillRadius,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Что хотите отправить',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SendChoiceCard(
                      label: 'Вставить',
                      icon: Icons.content_paste_rounded,
                      isWhiteTheme: isWhite,
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendFromClipboard(host);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SendChoiceCard(
                      label: 'Текст',
                      icon: Icons.notes_rounded,
                      isWhiteTheme: isWhite,
                      onTap: () {
                        Navigator.pop(ctx);
                        _openTextComposer(host);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SendChoiceCard(
                      label: 'Файл',
                      icon: Icons.insert_drive_file_rounded,
                      isWhiteTheme: isWhite,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendFiles(host);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SendChoiceCard(
                      label: 'Папка',
                      icon: Icons.folder_rounded,
                      isWhiteTheme: isWhite,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendFolder(host);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        if (isIos) {
          panel = ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: panel,
            ),
          );
        }

        return panel;
      },
    );
  }

  Future<void> _sendFromClipboard(String host) async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      setState(() => _status = 'Буфер обмена пуст');
      return;
    }
    await _sendTextPayload(host, text, label: 'clipboard.txt');
  }

  Future<void> _openTextComposer(String host) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: kPillRadius),
        title: const Text('Отправить текст'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Введите текст или ссылку...',
            border: OutlineInputBorder(borderRadius: kPillRadius),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: kPillRadius)),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text != null && text.isNotEmpty) {
      await _sendTextPayload(host, text, label: 'message.txt');
    }
  }

  Future<void> _sendTextPayload(String host, String text, {required String label}) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final item = OutgoingItem(
      relativeName: '${stamp}_$label',
      sizeBytes: bytes.length,
      rawBytes: bytes,
    );
    await _sendItemsQueue(host, [item], summaryDone: 'Текст отправлен');
  }

  Future<void> _pickAndSendFiles(String host) async {
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
    if (items.isEmpty) return;
    await _sendItemsQueue(
      host,
      items,
      summaryDone: items.length == 1 ? 'Файл отправлен' : 'Файлы (${items.length}) отправлены',
    );
  }

  Future<void> _pickAndSendFolder(String host) async {
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
        final p = entity.path.replaceAll('\\', '/');
        final rel = p.startsWith(prefix) ? p.substring(prefix.length) : entity.uri.pathSegments.last;
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
      setState(() => _status = 'Выбранная папка пуста');
      return;
    }

    await _sendItemsQueue(
      host,
      items,
      summaryDone: 'Папка «$folderName» (${items.length} файлов) отправлена',
    );
  }

  Future<void> _sendItemsQueue(
    String host,
    List<OutgoingItem> items, {
    required String summaryDone,
  }) async {
    if (_isTransferring) return;

    setState(() {
      _isTransferring = true;
      _totalFilesCount = items.length;
    });

    try {
      for (int i = 0; i < items.length; i++) {
        setState(() => _currentFileIndex = i + 1);
        await _sendSingleItem(host, items[i]);
      }

      setState(() {
        _progress = 1.0;
        _speedMBps = 0.0;
        _etaText = '00:00';
        _status = summaryDone;
      });
    } catch (e) {
      setState(() => _status = 'Ошибка отправки: $e');
    } finally {
      setState(() {
        _isTransferring = false;
        _totalFilesCount = 0;
      });
    }
  }

  Future<void> _sendSingleItem(String host, OutgoingItem item) async {
    setState(() {
      _currentFileName = item.relativeName;
      _totalBytes = item.sizeBytes;
      _transferredBytes = 0;
      _progress = 0.0;
      _speedMBps = 0.0;
      _status = 'Отправка ($_currentFileIndex/$_totalFilesCount)';
    });

    Socket? socket;
    RandomAccessFile? raf;

    try {
      socket = await Socket.connect(
        host,
        kTransferPort,
        timeout: const Duration(seconds: 6),
      );
      socket.setOption(SocketOption.tcpNoDelay, true);

      socket.write('${item.relativeName}|${item.sizeBytes}\n');
      await socket.flush();

      final completer = Completer<int>();
      final respBuilder = BytesBuilder(copy: false);

      late StreamSubscription sub;
      sub = socket.listen(
        (Uint8List chunk) {
          respBuilder.add(chunk);
          final bytes = respBuilder.toBytes();
          final nl = bytes.indexOf(10);
          if (nl != -1 && !completer.isCompleted) {
            final offsetStr = utf8.decode(bytes.sublist(0, nl)).trim();
            completer.complete(int.tryParse(offsetStr) ?? 0);
            sub.pause();
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(0);
        },
      );

      final startOffset = await completer.future.timeout(const Duration(seconds: 5));
      await sub.cancel();

      int sentBytes = startOffset.clamp(0, item.sizeBytes);
      int bytesInInterval = 0;
      DateTime lastSpeedUpdate = DateTime.now();

      if (item.rawBytes != null) {
        final raw = item.rawBytes!;
        if (sentBytes < raw.length) {
          final slice = Uint8List.sublistView(raw, sentBytes);
          socket.add(slice);
          await socket.flush();
          sentBytes = raw.length;
          setState(() {
            _transferredBytes = sentBytes;
            _progress = 1.0;
            _etaText = '00:00';
          });
        }
      } else if (item.file != null) {
        raf = await item.file!.open(mode: FileMode.read);
        await raf.setPosition(sentBytes);

        while (sentBytes < item.sizeBytes) {
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

            setState(() {
              _transferredBytes = sentBytes;
              _progress = item.sizeBytes > 0 ? (sentBytes / item.sizeBytes).clamp(0.0, 1.0) : 0.0;
              _speedMBps = speed;
              _etaText = _formatEta(item.sizeBytes - sentBytes, speed);
            });
          }
        }
        await raf.close();
      }

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
      await raf?.close();
      socket?.destroy();
      rethrow;
    }
  }

  void _openSettings() {
    _hideKeyboard();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          settings: widget.settings,
          onThemeChanged: widget.onThemeChanged,
          onSaveDirChanged: widget.onSaveDirChanged,
          onClearHistory: widget.onClearHistory,
        ),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWhite = widget.settings.isWhiteTheme;
    final fg = isWhite ? const Color(0xFF0A0A0A) : Colors.white;
    final subtle = isWhite ? Colors.black54 : Colors.white60;
    final cardBorder = isWhite ? Colors.black12 : Colors.white12;
    final cardBg = isWhite ? const Color(0xFFF6F7F9) : const Color(0xFF0A0A0C);
    final accent = isWhite ? const Color(0xFF007AFF) : const Color(0xFF64D2FF);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _hideKeyboard,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.settings_rounded, color: fg),
            tooltip: 'Настройки',
            onPressed: _openSettings,
          ),
          title: Text(
            'v$kAppVersion',
            style: TextStyle(fontSize: 13, color: subtle, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              icon: Icon(isWhite ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: fg),
              tooltip: isWhite ? 'OLED-чёрный фон' : 'Белый фон',
              onPressed: () => widget.onThemeChanged(!isWhite),
            ),
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: fg),
              tooltip: 'Обновить IP',
              onPressed: _refreshLocalIps,
            ),
          ],
        ),
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: kPillRadius,
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('МОЙ IP', style: TextStyle(fontSize: 11, color: subtle, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    if (_myIps.isEmpty)
                      Text('Нет сети', style: TextStyle(color: subtle, fontSize: 13))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _myIps.map((ip) {
                          return ActionChip(
                            label: Text(ip, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: ip));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Скопировано: $ip'), duration: const Duration(seconds: 1)),
                              );
                            },
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Center(
                child: LiquidGlassButton(
                  label: _isListening ? 'Принимаю' : 'Принять',
                  icon: _isListening ? Icons.stop_rounded : Icons.download_rounded,
                  active: _isListening,
                  isWhiteTheme: isWhite,
                  onPressed: _toggleReceive,
                ),
              ),

              const SizedBox(height: 16),

              if (_peers.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: kPillRadius,
                    border: Border.all(color: cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('НАЙДЕНЫ', style: TextStyle(fontSize: 11, color: subtle, fontWeight: FontWeight.w600)),
                      ..._peers.values.map((peer) {
                        final selected = _ipController.text.trim() == peer.ip;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            peer.name == 'iPhone' ? Icons.phone_iphone : Icons.phone_android,
                            color: selected ? accent : fg,
                            size: 20,
                          ),
                          title: Text(peer.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Text(peer.ip, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                          trailing: selected ? Icon(Icons.check_circle, color: accent, size: 18) : null,
                          onTap: () => setState(() => _ipController.text = peer.ip),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              TextField(
                controller: _ipController,
                focusNode: _ipFocus,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _hideKeyboard(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'IP получателя',
                  hintText: '172.20.10.1',
                  border: OutlineInputBorder(borderRadius: kPillRadius),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: kPillRadius,
                    borderSide: BorderSide(color: cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: kPillRadius,
                    borderSide: BorderSide(color: accent, width: 1.5),
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.paste_rounded),
                        tooltip: 'Вставить',
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _ipController.text = data!.text!.trim();
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_hide_rounded),
                        tooltip: 'Скрыть клавиатуру',
                        onPressed: _hideKeyboard,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    label: const Text('.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    onPressed: () {
                      _ipController.text = '${_ipController.text}.';
                      _ipController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _ipController.text.length),
                      );
                    },
                  ),
                  ActionChip(
                    label: const Text('172.20.10.1'),
                    onPressed: () => _ipController.text = '172.20.10.1',
                  ),
                  ActionChip(
                    label: const Text('192.168.1.'),
                    onPressed: () {
                      _ipController.text = '192.168.1.';
                      _ipController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _ipController.text.length),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 16),
              if (_queuedItems.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: kPillRadius,
                    border: Border.all(color: cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ВЫБРАНО (${_queuedItems.length})',
                            style: TextStyle(fontSize: 11, color: subtle, fontWeight: FontWeight.w600),
                          ),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: _isTransferring ? null : _openSendMenu,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Добавить'),
                              ),
                              if (!_isTransferring)
                                TextButton(
                                  onPressed: _clearQueuedItems,
                                  child: const Text('Очистить'),
                                ),
                            ],
                          ),
                        ],
                      ),
                      ...List.generate(_queuedItems.length, (index) {
                        final item = _queuedItems[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.insert_drive_file_rounded, size: 18, color: fg),
                          title: Text(
                            item.relativeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            _formatSize(item.sizeBytes),
                            style: TextStyle(fontSize: 11, color: subtle, fontFamily: 'monospace'),
                          ),
                          trailing: _isTransferring
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  tooltip: 'Удалить из списка',
                                  onPressed: () => _removeQueuedItem(index),
                                ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

                            Center(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    LiquidGlassButton(
                      label: _queuedItems.isEmpty ? 'Отправить' : 'Отправить (${_queuedItems.length})',
                      icon: Icons.upload_rounded,
                      active: _isTransferring,
                      isWhiteTheme: isWhite,
                      onPressed: _isTransferring ? null : _startSendingQueue,
                    ),
                    if (_isTransferring)
                      LiquidGlassButton(
                        label: 'Отмена',
                        icon: Icons.close_rounded,
                        active: true,
                        isWhiteTheme: isWhite,
                        onPressed: _cancelTransfer,
                      ),
                  ],
                ),
              ),


              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: kPillRadius,
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_speedMBps.toStringAsFixed(1)} МБ/с',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: accent),
                        ),
                        Text(
                          _etaText,
                          style: TextStyle(fontSize: 16, fontFamily: 'monospace', color: subtle),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: kPillRadius,
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${(_progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12)),
                        Text(
                          '${_formatSize(_transferredBytes)} / ${_formatSize(_totalBytes)}',
                          style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: subtle),
                        ),
                      ],
                    ),
                    if (_currentFileName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _currentFileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: subtle),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(_status, style: const TextStyle(fontSize: 12)),
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
        setState(() {});
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
    final history = widget.settings.history;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки · v$kAppVersion')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Белый фон'),
            subtitle: Text(_whiteTheme ? 'Включён белый фон' : 'Включён OLED-чёрный фон'),
            value: _whiteTheme,
            onChanged: (val) {
              setState(() => _whiteTheme = val);
              widget.onThemeChanged(val);
            },
          ),

          const Divider(height: 28),

          const Text('Папка сохранения', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _dirController,
            decoration: InputDecoration(
              hintText: 'По умолчанию (Download / Documents)',
              border: OutlineInputBorder(borderRadius: kPillRadius),
              suffixIcon: IconButton(
                icon: const Icon(Icons.folder_open_rounded),
                onPressed: _pickFolder,
              ),
            ),
            onSubmitted: (val) => widget.onSaveDirChanged(val.trim().isEmpty ? null : val.trim()),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                label: const Text('Выбрать папку'),
                onPressed: _pickFolder,
              ),
              if (Platform.isAndroid)
                ActionChip(
                  label: const Text('/storage/emulated/0/Download'),
                  onPressed: () {
                    const p = '/storage/emulated/0/Download';
                    _dirController.text = p;
                    widget.onSaveDirChanged(p);
                  },
                ),
              ActionChip(
                label: const Text('По умолчанию'),
                onPressed: () {
                  _dirController.clear();
                  widget.onSaveDirChanged(null);
                },
              ),
            ],
          ),

          const Divider(height: 28),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('История (${history.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              if (history.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await widget.onClearHistory();
                    setState(() {});
                  },
                  child: const Text('Очистить'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('История пока пуста', style: TextStyle(color: Colors.grey)),
            )
          else
            ...history.map((item) {
              final dt = '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  item.direction == 'Принято' ? Icons.download_done_rounded : Icons.check_circle_outline_rounded,
                ),
                title: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${item.direction} · ${_formatBytes(item.sizeBytes)} · $dt',
                  style: const TextStyle(fontSize: 12),
                ),
              );
            }),
        ],
      ),
    );
  }
}
