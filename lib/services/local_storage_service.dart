import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'audio_engine_service.dart';

class LocalRecordingFile {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modifiedAt;
  final String extension;

  LocalRecordingFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.extension,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class LocalStorageService extends ChangeNotifier {
  static final LocalStorageService instance = LocalStorageService._internal();
  LocalStorageService._internal();

  final AudioPlayer _player = AudioPlayer();
  List<LocalRecordingFile> _files = [];
  String? _currentlyPlayingPath;
  PlayerState _playerState = PlayerState.stopped;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  List<LocalRecordingFile> get files => List.unmodifiable(_files);
  String? get currentlyPlayingPath => _currentlyPlayingPath;
  PlayerState get playerState => _playerState;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;

  int get totalDiskUsageBytes => _files.fold(0, (sum, f) => sum + f.sizeBytes);

  void initialize() {
    _player.onPlayerStateChanged.listen((state) {
      _playerState = state;
      notifyListeners();
    });

    _player.onPositionChanged.listen((pos) {
      _currentPosition = pos;
      notifyListeners();
    });

    _player.onDurationChanged.listen((dur) {
      _totalDuration = dur;
      notifyListeners();
    });

    _player.onPlayerComplete.listen((_) {
      _currentlyPlayingPath = null;
      _currentPosition = Duration.zero;
      _playerState = PlayerState.completed;
      notifyListeners();
    });

    refreshFiles();
  }

  Future<void> refreshFiles() async {
    try {
      final dirPath = await AudioEngineService.instance.getRecordingsDirectory();
      final dir = Directory(dirPath);

      if (!await dir.exists()) {
        _files = [];
        notifyListeners();
        return;
      }

      final entities = dir.listSync();
      final list = <LocalRecordingFile>[];

      for (final entity in entities) {
        if (entity is File) {
          final stat = entity.statSync();
          list.add(
            LocalRecordingFile(
              path: entity.path,
              name: p.basename(entity.path),
              sizeBytes: stat.size,
              modifiedAt: stat.modified,
              extension: p.extension(entity.path).replaceAll('.', ''),
            ),
          );
        }
      }

      // Sort newest first
      list.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      _files = list;
      notifyListeners();
    } catch (e) {
      print('[LocalStorageService] Error refreshing files: $e');
    }
  }

  Future<void> playFile(String path) async {
    try {
      if (_currentlyPlayingPath == path && _playerState == PlayerState.playing) {
        await _player.pause();
        return;
      }

      _currentlyPlayingPath = path;
      await _player.stop();
      await _player.play(DeviceFileSource(path));
    } catch (e) {
      print('[LocalStorageService] Error playing file: $e');
    }
  }

  Future<void> pausePlayer() async {
    await _player.pause();
  }

  Future<void> stopPlayer() async {
    await _player.stop();
    _currentlyPlayingPath = null;
    _currentPosition = Duration.zero;
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<bool> deleteFile(String path) async {
    try {
      if (_currentlyPlayingPath == path) {
        await stopPlayer();
      }
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      await refreshFiles();
      return true;
    } catch (e) {
      print('[LocalStorageService] Error deleting file: $e');
      return false;
    }
  }

  Future<void> deleteAllFiles() async {
    try {
      await stopPlayer();
      for (final f in _files) {
        final file = File(f.path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      await refreshFiles();
    } catch (e) {
      print('[LocalStorageService] Error deleting all: $e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
