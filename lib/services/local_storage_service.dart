import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive_io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_engine_service.dart';

enum PlayMode {
  sequential, // 顺序播放
  loopSingle, // 单曲循环
  loopAll, // 列表循环
  shuffle; // 随机播放

  String get displayName {
    switch (this) {
      case PlayMode.sequential:
        return '顺序播放';
      case PlayMode.loopSingle:
        return '单曲循环';
      case PlayMode.loopAll:
        return '列表循环';
      case PlayMode.shuffle:
        return '随机播放';
    }
  }
}

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
  double _playbackSpeed = 1.0;
  double _volume = 1.0;
  PlayMode _playMode = PlayMode.sequential;

  // Custom storage directory path
  String _customStoragePath = '';
  Map<String, String> _storagePresets = {};
  Map<String, bool> _presetAvailability = {};
  String? _lastStoragePathError;
  String? _lastPlayError;

  // Batch selection
  bool _isSelectionMode = false;
  final Set<String> _selectedPaths = <String>{};

  List<LocalRecordingFile> get files => List.unmodifiable(_files);
  String? get currentlyPlayingPath => _currentlyPlayingPath;
  PlayerState get playerState => _playerState;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  double get playbackSpeed => _playbackSpeed;
  double get volume => _volume;
  PlayMode get playMode => _playMode;
  String get customStoragePath => _customStoragePath;
  Map<String, String> get storagePresets => Map.unmodifiable(_storagePresets);
  Map<String, bool> get presetAvailability => Map.unmodifiable(_presetAvailability);
  String? get lastStoragePathError => _lastStoragePathError;
  String? get lastPlayError => _lastPlayError;

  bool get isSelectionMode => _isSelectionMode;
  Set<String> get selectedPaths => Set.unmodifiable(_selectedPaths);
  int get selectedCount => _selectedPaths.length;
  bool isSelected(String path) => _selectedPaths.contains(path);

  int get totalDiskUsageBytes => _files.fold(0, (sum, f) => sum + f.sizeBytes);

  LocalRecordingFile? get currentlyPlayingFile {
    if (_currentlyPlayingPath == null) return null;
    return _files.firstWhere(
      (f) => f.path == _currentlyPlayingPath,
      orElse: () => LocalRecordingFile(
        path: _currentlyPlayingPath!,
        name: p.basename(_currentlyPlayingPath!),
        sizeBytes: 0,
        modifiedAt: DateTime.now(),
        extension: p.extension(_currentlyPlayingPath!).replaceAll('.', ''),
      ),
    );
  }

  Future<void> initialize() async {
    final sp = await SharedPreferences.getInstance();
    _customStoragePath = sp.getString('vibears_custom_storage_path') ?? '';
    _playMode = PlayMode.values.firstWhere(
      (e) => e.name == sp.getString('vibears_play_mode'),
      orElse: () => PlayMode.sequential,
    );
    _playbackSpeed = sp.getDouble('vibears_playback_speed') ?? 1.0;

    _storagePresets = await AudioEngineService.instance.getStoragePresets();
    // Probe writability of each preset once at startup.
    await checkStoragePresetAvailability();

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
      _onTrackComplete();
    });

    await refreshFiles();
  }

  /// Returns true if the path was accepted (directory exists or was created).
  /// Returns false if the directory could not be created (e.g. no permission),
  /// in which case the previous storage path stays active.
  Future<bool> setStoragePath(String newPath) async {
    final clean = newPath.trim();
    if (clean.isEmpty) return false;

    try {
      final dir = Directory(clean);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      if (!await _isDirectoryWritable(dir)) {
        _lastStoragePathError = '目录不可写（可能缺少“所有文件访问权限”）: $clean';
        print('[LocalStorageService] ${_lastStoragePathError}');
        return false;
      }
    } catch (e) {
      _lastStoragePathError = '无法创建目录: $clean (${e.toString()})';
      print('[LocalStorageService] ${_lastStoragePathError}');
      return false;
    }

    _lastStoragePathError = null;
    _customStoragePath = clean;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('vibears_custom_storage_path', clean);
    notifyListeners();
    await refreshFiles();
    return true;
  }

  Future<bool> _isDirectoryWritable(Directory dir) async {
    try {
      final probe = File('${dir.path}/.vibears_probe');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Probes every storage preset directory for writability. The result map
  /// uses the same keys as [storagePresets].
  Future<Map<String, bool>> checkStoragePresetAvailability() async {
    if (_storagePresets.isEmpty) {
      _storagePresets = await AudioEngineService.instance.getStoragePresets();
    }
    final result = <String, bool>{};
    for (final entry in _storagePresets.entries) {
      var writable = false;
      try {
        final dir = Directory(entry.value);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        writable = await _isDirectoryWritable(dir);
      } catch (e) {
        print('[LocalStorageService] Preset ${entry.key} unavailable: $e');
        writable = false;
      }
      result[entry.key] = writable;
    }
    _presetAvailability = result;
    notifyListeners();
    return Map.unmodifiable(result);
  }

  Future<String> getActiveStoragePath() async {
    if (_customStoragePath.isNotEmpty) {
      final dir = Directory(_customStoragePath);
      if (await dir.exists()) {
        return _customStoragePath;
      }
    }
    return await AudioEngineService.instance.getDefaultStorageDirectory();
  }

  Future<void> refreshFiles() async {
    try {
      final dirPath = await getActiveStoragePath();
      final dir = Directory(dirPath);

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final entities = dir.listSync();
      final list = <LocalRecordingFile>[];

      for (final entity in entities) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          // Only list playable audio files; raw .pcm slices from older
          // versions are skipped because they cannot be decoded by the player.
          if (['.wav', '.m4a', '.aac', '.mp3', '.opus', '.ogg'].contains(ext)) {
            final stat = entity.statSync();
            list.add(
              LocalRecordingFile(
                path: entity.path,
                name: p.basename(entity.path),
                sizeBytes: stat.size,
                modifiedAt: stat.modified,
                extension: ext.replaceAll('.', ''),
              ),
            );
          }
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

  // --- Advanced Player Methods ---

  /// Plays (or toggles) the given audio file. Returns false and records
  /// [lastPlayError] when the file is missing or the player fails, so the UI
  /// can surface real feedback instead of silently doing nothing.
  Future<bool> playFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        _lastPlayError = '文件不存在: $path';
        print('[LocalStorageService] ${_lastPlayError}');
        if (_currentlyPlayingPath == path) {
          _currentlyPlayingPath = null;
        }
        notifyListeners();
        return false;
      }

      if (_currentlyPlayingPath == path && _playerState == PlayerState.playing) {
        await _player.pause();
        return true;
      }

      if (_currentlyPlayingPath == path && _playerState == PlayerState.paused) {
        await _player.resume();
        return true;
      }

      _currentlyPlayingPath = path;
      _lastPlayError = null;
      await _player.stop();
      await _player.setPlaybackRate(_playbackSpeed);
      await _player.setVolume(_volume);
      await _player.play(DeviceFileSource(path));
      return true;
    } catch (e) {
      _lastPlayError = '播放失败: $path (${e.toString()})';
      print('[LocalStorageService] ${_lastPlayError}');
      // Roll back the current-track marker so the mini player does not stay
      // stuck on a track that could not be started.
      if (_currentlyPlayingPath == path) {
        _currentlyPlayingPath = null;
      }
      notifyListeners();
      return false;
    }
  }

  Future<void> pausePlayer() async {
    await _player.pause();
  }

  Future<void> resumePlayer() async {
    await _player.resume();
  }

  Future<void> stopPlayer() async {
    await _player.stop();
    _currentlyPlayingPath = null;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> skipForward(int seconds) async {
    final target = _currentPosition + Duration(seconds: seconds);
    final clamped = target > _totalDuration ? _totalDuration : target;
    await seek(clamped);
  }

  Future<void> skipBackward(int seconds) async {
    final target = _currentPosition - Duration(seconds: seconds);
    final clamped = target < Duration.zero ? Duration.zero : target;
    await seek(clamped);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    await _player.setPlaybackRate(speed);
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('vibears_playback_speed', speed);
    notifyListeners();
  }

  Future<void> setVolume(double vol) async {
    _volume = vol.clamp(0.0, 1.0).toDouble();
    await _player.setVolume(_volume);
    notifyListeners();
  }

  Future<void> setPlayMode(PlayMode mode) async {
    _playMode = mode;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('vibears_play_mode', mode.name);
    notifyListeners();
  }

  Future<void> playNext() async {
    if (_files.isEmpty) return;
    if (_currentlyPlayingPath == null) {
      await playFile(_files.first.path);
      return;
    }

    final currentIndex = _files.indexWhere((f) => f.path == _currentlyPlayingPath);
    if (currentIndex == -1) {
      await playFile(_files.first.path);
      return;
    }

    if (_playMode == PlayMode.shuffle) {
      final rand = Random();
      var nextIdx = rand.nextInt(_files.length);
      if (_files.length > 1 && nextIdx == currentIndex) {
        nextIdx = (nextIdx + 1) % _files.length;
      }
      await playFile(_files[nextIdx].path);
      return;
    }

    final nextIndex = currentIndex + 1;
    if (nextIndex < _files.length) {
      await playFile(_files[nextIndex].path);
    } else if (_playMode == PlayMode.loopAll) {
      await playFile(_files.first.path);
    } else {
      await stopPlayer();
    }
  }

  Future<void> playPrevious() async {
    if (_files.isEmpty) return;
    if (_currentlyPlayingPath == null) {
      await playFile(_files.first.path);
      return;
    }

    final currentIndex = _files.indexWhere((f) => f.path == _currentlyPlayingPath);
    if (currentIndex == -1) {
      await playFile(_files.first.path);
      return;
    }

    final prevIndex = currentIndex - 1;
    if (prevIndex >= 0) {
      await playFile(_files[prevIndex].path);
    } else if (_playMode == PlayMode.loopAll) {
      await playFile(_files.last.path);
    } else {
      await seek(Duration.zero);
    }
  }

  void _onTrackComplete() {
    if (_playMode == PlayMode.loopSingle && _currentlyPlayingPath != null) {
      // Restart the same track from the beginning.
      _player.seek(Duration.zero).then((_) => _player.resume()).catchError((_) {
        playFile(_currentlyPlayingPath!);
      });
    } else {
      playNext();
    }
  }

  // --- Batch Selection & Export Operations ---

  void setSelectionMode(bool enabled) {
    _isSelectionMode = enabled;
    if (!enabled) {
      _selectedPaths.clear();
    }
    notifyListeners();
  }

  void toggleSelect(String path) {
    if (_selectedPaths.contains(path)) {
      _selectedPaths.remove(path);
    } else {
      _selectedPaths.add(path);
    }
    if (_selectedPaths.isEmpty) {
      _isSelectionMode = false;
    } else {
      _isSelectionMode = true;
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedPaths.clear();
    _selectedPaths.addAll(_files.map((f) => f.path));
    _isSelectionMode = true;
    notifyListeners();
  }

  void deselectAll() {
    _selectedPaths.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  Future<void> batchShareSelected() async {
    if (_selectedPaths.isEmpty) return;
    try {
      final xfiles = _selectedPaths.map((p) => XFile(p)).toList();
      await Share.shareXFiles(xfiles, text: 'vibeARS 录音文件导出 (${xfiles.length} 项)');
    } catch (e) {
      print('[LocalStorageService] Share error: $e');
    }
  }

  Future<String?> batchExportZipSelected() async {
    if (_selectedPaths.isEmpty) return null;
    try {
      final archive = Archive();
      for (final filePath in _selectedPaths) {
        final file = File(filePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final fileName = p.basename(filePath);
          // The 3-argument ArchiveFile constructor is deprecated in newer
          // archive versions but is the only one available across the
          // resolved version; bytes are in-memory so size is exact.
          // ignore: deprecated_member_use
          archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
        }
      }

      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);
      if (zipData == null) return null;

      final dirPath = await getActiveStoragePath();
      final timeStamp = DateTime.now().millisecondsSinceEpoch;
      final zipFile = File('$dirPath/vibeARS_batch_export_$timeStamp.zip');
      await zipFile.writeAsBytes(zipData);

      // Trigger share of the zip file
      await Share.shareXFiles([XFile(zipFile.path)], text: 'vibeARS 打包归档文件');
      await refreshFiles();
      return zipFile.path;
    } catch (e) {
      print('[LocalStorageService] Zip export error: $e');
      return null;
    }
  }

  Future<int> batchCopyToDirectory(String destinationDirPath) async {
    var count = 0;
    final destDir = Directory(destinationDirPath);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    for (final filePath in _selectedPaths) {
      final file = File(filePath);
      if (await file.exists()) {
        final targetPath = p.join(destDir.path, p.basename(filePath));
        await file.copy(targetPath);
        count++;
      }
    }
    return count;
  }

  Future<bool> deleteFile(String path) async {
    try {
      if (_currentlyPlayingPath == path) {
        await stopPlayer();
      }
      _selectedPaths.remove(path);
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

  Future<int> batchDeleteSelected() async {
    var deleted = 0;
    for (final path in _selectedPaths.toList()) {
      if (await deleteFile(path)) {
        deleted++;
      }
    }
    _selectedPaths.clear();
    _isSelectionMode = false;
    notifyListeners();
    return deleted;
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
      _selectedPaths.clear();
      _isSelectionMode = false;
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
