import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const int kTransferPort = 49152;
const int kChunkSize = 1024 * 1024;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FastDropApp());
}

class FastDropApp extends StatelessWidget {
  const FastDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FastDrop Wi-Fi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const TransferHomePage(),
    );
  }
}

class TransferHomePage extends StatefulWidget {
  const TransferHomePage({super.key});

  @override
  State<TransferHomePage> createState() => _TransferHomePageState();
}

class _TransferHomePageState extends State<TransferHomePage> {
  final TextEditingController _ipController = TextEditingController(text: '172.20.10.1');

  ServerSocket? _server;
  bool _isListening = false;
  bool _isTransferring = false;

  String _status = 'Готов к работе';
  double _progress = 0.0;
  double _speedMBps = 0.0;
  String _localIps = 'Определяется...';

  @override
  void initState() {
    super.initState();
    _initEnvironment();
  }

  Future<void> _initEnvironment() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
      ].request();
    }
    await _refreshLocalIps();
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
          ips.add('${iface.name}: ${addr.address}');
        }
      }
      setState(() {
        _localIps = ips.isEmpty ? 'Нет активного IPv4' : ips.join(' | ');
      });
    } catch (e) {
      setState(() => _localIps = 'Ошибка IP: $e');
    }
  }

  Future<Directory> _getSaveDirectory() async {
    if (Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) return downloads;
    }
    return await getApplicationDocumentsDirectory();
  }

  Future<void> _toggleServer() async {
    if (_isListening) {
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
        reuseAddress: true

      );
      setState(() {
        _server = server;
        _isListening = true;
        _status = 'Жду подключение на порту $kTransferPort...';
        _progress = 0.0;
        _speedMBps = 0.0;
      });

      server.listen((Socket client) async {
        await _handleIncomingClient(client);
      });
    } catch (e) {
      setState(() => _status = 'Ошибка запуска приёмника: $e');
    }
  }

  Future<void> _handleIncomingClient(Socket client) async {
    client.setOption(SocketOption.tcpNoDelay, true);

    final saveDir = await _getSaveDirectory();
    RandomAccessFile? raf;
    String fileName = 'received_file';
    int totalSize = 0;
    int receivedBytes = 0;
    bool headerParsed = false;
    BytesBuilder headerBuffer = BytesBuilder(copy: false);

    final stopwatch = Stopwatch()..start();
    int bytesInInterval = 0;
    DateTime lastSpeedUpdate = DateTime.now();

    try {
      await for (final Uint8List data in client) {
        int offset = 0;

        if (!headerParsed) {
          headerBuffer.add(data);
          final bytes = headerBuffer.toBytes();
          final newlineIndex = bytes.indexOf(10);
          if (newlineIndex == -1) {
            continue;
          }

          final headerLine = utf8.decode(bytes.sublist(0, newlineIndex)).trim();
          final parts = headerLine.split('|');
          if (parts.length < 2) {
            throw Exception('Некорректный заголовок: $headerLine');
          }

          fileName = parts[0].replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          totalSize = int.tryParse(parts[1]) ?? 0;

          final outFile = File('${saveDir.path}/$fileName');
          raf = await outFile.open(mode: FileMode.writeOnlyAppend);
          receivedBytes = await raf.length();

          client.write('$receivedBytes\n');
          await client.flush();

          headerParsed = true;
          offset = newlineIndex + 1;

          setState(() {
            _status = 'Приём: $fileName (с ${(receivedBytes / (1024 * 1024)).toStringAsFixed(1)} МБ)';
          });
        }

        if (offset < data.length) {
          final chunk = Uint8List.sublistView(data, offset);
          await raf!.writeFrom(chunk);
          receivedBytes += chunk.length;
          bytesInInterval += chunk.length;

          final now = DateTime.now();
          final elapsedMs = now.difference(lastSpeedUpdate).inMilliseconds;
          if (elapsedMs >= 250 || receivedBytes >= totalSize) {
            final sec = elapsedMs > 0 ? elapsedMs / 1000.0 : 0.001;
            final speed = (bytesInInterval / (1024 * 1024)) / sec;
            bytesInInterval = 0;
            lastSpeedUpdate = now;

            setState(() {
              _progress = totalSize > 0 ? (receivedBytes / totalSize).clamp(0.0, 1.0) : 0.0;
              _speedMBps = speed;
            });
          }
        }
      }

      await raf?.flush();
      await raf?.close();
      stopwatch.stop();

      setState(() {
        _progress = 1.0;
        _speedMBps = 0.0;
        _status = 'Готово! Сохранено: ${saveDir.path}/$fileName';
      });
    } catch (e) {
      await raf?.close();
      setState(() => _status = 'Ошибка приёма: $e');
    } finally {
      await client.close();
    }
  }

  Future<void> _pickAndSendFile() async {
    if (_isTransferring) return;

    final host = _ipController.text.trim();
    if (host.isEmpty) {
      setState(() => _status = 'Укажи IP-адрес приёмника');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withReadStream: false,
    );

    if (result == null || result.files.single.path == null) {
      return;
    }

    final file = File(result.files.single.path!);
    if (!await file.exists()) {
      setState(() => _status = 'Файл недоступен');
      return;
    }

    final fileName = file.uri.pathSegments.last;
    final totalSize = await file.length();

    setState(() {
      _isTransferring = true;
      _status = 'Подключение к $host:$kTransferPort...';
      _progress = 0.0;
      _speedMBps = 0.0;
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

      socket.write('$fileName|$totalSize\n');
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

      raf = await file.open(mode: FileMode.read);
      int sentBytes = startOffset.clamp(0, totalSize);
      await raf.setPosition(sentBytes);

      int bytesInInterval = 0;
      DateTime lastSpeedUpdate = DateTime.now();

      setState(() {
        _status = 'Отправка: $fileName';
      });

      while (sentBytes < totalSize) {
        final remaining = totalSize - sentBytes;
        final toRead = remaining < kChunkSize ? remaining : kChunkSize;
        final buffer = await raf.read(toRead);
        if (buffer.isEmpty) break;

        socket.add(buffer);
        await socket.flush();

        sentBytes += buffer.length;
        bytesInInterval += buffer.length;

        final now = DateTime.now();
        final elapsedMs = now.difference(lastSpeedUpdate).inMilliseconds;
        if (elapsedMs >= 250 || sentBytes >= totalSize) {
          final sec = elapsedMs > 0 ? elapsedMs / 1000.0 : 0.001;
          final speed = (bytesInInterval / (1024 * 1024)) / sec;
          bytesInInterval = 0;
          lastSpeedUpdate = now;

          setState(() {
            _progress = totalSize > 0 ? (sentBytes / totalSize).clamp(0.0, 1.0) : 0.0;
            _speedMBps = speed;
          });
        }
      }

      await raf.close();
      await socket.close();

      setState(() {
        _progress = 1.0;
        _speedMBps = 0.0;
        _status = 'Отправка завершена: $fileName';
      });
    } catch (e) {
      await raf?.close();
      socket?.destroy();
      setState(() => _status = 'Ошибка отправки: $e');
    } finally {
      setState(() => _isTransferring = false);
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FastDrop TCP (Wi-Fi 5GHz)'),
        actions: [
          IconButton(
            onPressed: _refreshLocalIps,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить IP',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Локальные IPv4 этого устройства:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_localIps, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _toggleServer,
              icon: Icon(_isListening ? Icons.stop : Icons.download),
              label: Text(_isListening ? 'Остановить приём (Порт $kTransferPort)' : 'Режим приёма (Слушать порт)'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _ipController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'IP-адрес приёмника',
                hintText: 'Например, 172.20.10.1 или 192.168.1.50',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isTransferring ? null : _pickAndSendFile,
              icon: const Icon(Icons.upload),
              label: Text(_isTransferring ? 'Передача...' : 'Выбрать файл и отправить'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 28),
            LinearProgressIndicator(value: _progress, minHeight: 10),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(_progress * 100).toStringAsFixed(1)}%'),
                Text('${_speedMBps.toStringAsFixed(1)} МБ/с', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 16),
            Text(_status, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
