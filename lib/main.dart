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
const int kTransferPort = 49152;
const int kDiscoveryPort = 49153;
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
    return '${v.toStringAsFixed(i >= 2 ? 2 : 0)}${units[i]}';
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
          final elapsed
