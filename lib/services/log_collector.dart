import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'audio_engine_service.dart';

/// In-app diagnostic log collector.
///
/// Keeps a bounded in-memory ring buffer (for the on-screen log viewer) and
/// appends every entry to a rolling log file under the app documents
/// directory, so a one-tap export can be shared without a computer.
class LogCollector extends ChangeNotifier {
  static final LogCollector instance = LogCollector._internal();
  LogCollector._internal();

  static const int _maxInMemory = 600;
  static const int _maxFileBytes = 2 * 1024 * 1024; // 2 MB rolling

  final Queue<LogEntry> _entries = Queue<LogEntry>();
  File? _logFile;
  int _droppedInMemory = 0;

  List<LogEntry> get entries => List.unmodifiable(_entries);
  int get droppedInMemory => _droppedInMemory;
  String? get logFilePath => _logFile?.path;

  Future<void> initialize() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/logs');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _logFile = File('${dir.path}/vibears_diag.log');
      if (await _logFile!.exists()) {
        final len = await _logFile!.length();
        if (len > _maxFileBytes) {
          // Roll: keep only the tail.
          final raf = await _logFile!.open();
          await raf.setPosition(len - _maxFileBytes);
          final tail = await raf.read(_maxFileBytes);
          await raf.close();
          await _logFile!.writeAsBytes(tail, flush: true);
        }
      } else {
        await _logFile!.create(recursive: true);
      }
    } catch (e) {
      debugPrint('[LogCollector] init error: $e');
    }
  }

  void log(String tag, String message) {
    final entry = LogEntry(tag: tag, message: message, time: DateTime.now());
    _entries.add(entry);
    if (_entries.length > _maxInMemory) {
      _entries.removeFirst();
      _droppedInMemory++;
    }
    _appendToFile(entry);
    notifyListeners();
  }

  void _appendToFile(LogEntry entry) {
    final line = '[${entry.time.toIso8601String()}] [${entry.tag}] ${entry.message}\n';
    try {
      _logFile?.writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('[LogCollector] write error: $e');
    }
  }

  Future<String?> ensureLogFileReady() async {
    if (_logFile != null) return _logFile!.path;
    await initialize();
    return _logFile?.path;
  }

  /// Exports the collected logs as a single text file and opens the system
  /// share sheet (WeChat/email/AirDrop/etc.) — no computer required.
  Future<String?> shareLogs() async {
    final path = await ensureLogFileReady();
    if (path == null) return null;
    try {
      await Share.shareXFiles(
        [XFile(path, mimeType: 'text/plain')],
        text: 'vibeARS 诊断日志 (蓝牙/录音排查)',
      );
      return path;
    } catch (e) {
      debugPrint('[LogCollector] share error: $e');
      return null;
    }
  }

  Future<void> clear() async {
    _entries.clear();
    _droppedInMemory = 0;
    final path = await ensureLogFileReady();
    if (path != null) {
      try {
        await File(path).writeAsString('', flush: true);
      } catch (_) {}
    }
    log('LogCollector', '日志已清空');
  }
}

class LogEntry {
  final String tag;
  final String message;
  final DateTime time;

  const LogEntry({required this.tag, required this.message, required this.time});

  String get line => '[$time] [$tag] $message';
}
