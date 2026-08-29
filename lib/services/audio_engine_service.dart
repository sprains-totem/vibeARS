import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../core/models/audio_config.dart';
import '../core/models/audio_device.dart';
import '../core/models/slicer_config.dart';

class AudioEngineService {
  static final AudioEngineService instance = AudioEngineService._internal();
  AudioEngineService._internal();

  static const MethodChannel _methodChannel = MethodChannel('com.vibears.app/audio_engine');
  static const EventChannel _audioStreamChannel = EventChannel('com.vibears.app/audio_stream');
  static const EventChannel _sliceStreamChannel = EventChannel('com.vibears.app/slice_stream');

  StreamSubscription? _audioSubscription;
  StreamSubscription? _sliceSubscription;

  final _waveformController = StreamController<Map<String, dynamic>>.broadcast();
  final _sliceController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get audioFrameStream => _waveformController.stream;
  Stream<Map<String, dynamic>> get sliceCompletedStream => _sliceController.stream;

  bool _isRecording = false;
  bool _isPaused = false;

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;

  Future<void> initialize() async {
    _audioSubscription = _audioStreamChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is Map) {
          _waveformController.add(Map<String, dynamic>.from(data));
        }
      },
      onError: (err) {
        print('[AudioEngineService] AudioStream error: $err');
      },
    );

    _sliceSubscription = _sliceStreamChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is Map) {
          _sliceController.add(Map<String, dynamic>.from(data));
        }
      },
      onError: (err) {
        print('[AudioEngineService] SliceStream error: $err');
      },
    );
  }

  Future<List<AudioInputDevice>> getAudioDevices() async {
    try {
      final List<dynamic>? rawList = await _methodChannel.invokeListMethod('getAudioDevices');
      if (rawList == null) return [];

      return rawList.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return AudioInputDevice.fromJson(map);
      }).toList();
    } catch (e) {
      print('[AudioEngineService] Error getting devices: $e');
      return [
        const AudioInputDevice(
          id: 'default',
          name: '默认麦克风 (Default Mic)',
          type: AudioDeviceType.builtInMic,
          isDefault: true,
          isSelected: true,
        )
      ];
    }
  }

  Future<String> getDefaultStorageDirectory() async {
    try {
      final String? path = await _methodChannel.invokeMethod<String>('getDefaultStorageDirectory');
      if (path != null && path.isNotEmpty) {
        final dir = Directory(path);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir.path;
      }
    } catch (e) {
      print('[AudioEngineService] getDefaultStorageDirectory error: $e');
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final recDir = Directory('${docsDir.path}/vibe_recordings');
    if (!await recDir.exists()) {
      await recDir.create(recursive: true);
    }
    return recDir.path;
  }

  Future<Map<String, String>> getStoragePresets() async {
    try {
      final Map<dynamic, dynamic>? raw = await _methodChannel.invokeMethod('getStoragePresets');
      if (raw != null) {
        return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (e) {
      print('[AudioEngineService] getStoragePresets error: $e');
    }
    final fallback = await getDefaultStorageDirectory();
    return {'default': fallback};
  }

  Future<bool> isManageStorageGranted() async {
    try {
      final bool? granted = await _methodChannel.invokeMethod<bool>('isManageStorageGranted');
      return granted == true;
    } catch (_) {
      return true;
    }
  }

  Future<void> requestManageStoragePermission() async {
    try {
      await _methodChannel.invokeMethod('requestManageStoragePermission');
    } catch (e) {
      print('[AudioEngineService] requestManageStoragePermission error: $e');
    }
  }

  Future<String> getRecordingsDirectory({String? customPath}) async {
    if (customPath != null && customPath.trim().isNotEmpty) {
      final customDir = Directory(customPath.trim());
      try {
        if (!await customDir.exists()) {
          await customDir.create(recursive: true);
        }
        return customDir.path;
      } catch (e) {
        print('[AudioEngineService] Custom directory creation failed: $e, falling back to default');
      }
    }
    return await getDefaultStorageDirectory();
  }

  Future<bool> startRecording({
    required AudioRecordingConfig audioConfig,
    required SlicerConfig slicerConfig,
    String? storagePath,
  }) async {
    try {
      final outputDir = await getRecordingsDirectory(customPath: storagePath);

      final result = await _methodChannel.invokeMethod<bool>('startRecording', {
        'sampleRate': audioConfig.sampleRate,
        'channelCount': audioConfig.channelCount,
        'format': audioConfig.format.fileExtension,
        'preferredDeviceId': int.tryParse(audioConfig.preferredDeviceId ?? '') ?? (Platform.isIOS ? audioConfig.preferredDeviceId : null),
        'slicerEnabled': slicerConfig.enabled,
        'sliceDurationMinutes': slicerConfig.intervalMinutes,
        'outputDir': outputDir,
      });

      _isRecording = result == true;
      _isPaused = false;
      return _isRecording;
    } catch (e) {
      print('[AudioEngineService] Error starting recording: $e');
      return false;
    }
  }
        'sliceDurationMinutes': slicerConfig.intervalMinutes,
        'outputDir': outputDir,
      });

      _isRecording = result == true;
      _isPaused = false;
      return _isRecording;
    } catch (e) {
      print('[AudioEngineService] Error starting recording: $e');
      return false;
    }
  }

  Future<bool> pauseRecording() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('pauseRecording');
      if (result == true) {
        _isPaused = true;
        return true;
      }
      return false;
    } catch (e) {
      print('[AudioEngineService] Error pausing recording: $e');
      return false;
    }
  }

  Future<bool> resumeRecording() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('resumeRecording');
      if (result == true) {
        _isPaused = false;
        return true;
      }
      return false;
    } catch (e) {
      print('[AudioEngineService] Error resuming recording: $e');
      return false;
    }
  }

  Future<bool> stopRecording() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopRecording');
      _isRecording = false;
      _isPaused = false;
      return result == true;
    } catch (e) {
      print('[AudioEngineService] Error stopping recording: $e');
      _isRecording = false;
      _isPaused = false;
      return false;
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    if (Platform.isAndroid) {
      try {
        await _methodChannel.invokeMethod('requestIgnoreBatteryOptimizations');
      } catch (e) {
        print('[AudioEngineService] Battery optimization request error: $e');
      }
    }
  }

  void dispose() {
    _audioSubscription?.cancel();
    _sliceSubscription?.cancel();
    _waveformController.close();
    _sliceController.close();
  }
}
