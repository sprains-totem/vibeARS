import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models/audio_config.dart';
import '../core/models/audio_device.dart';
import '../core/models/slicer_config.dart';
import '../core/models/storage_config.dart';
import '../core/models/streaming_config.dart';
import '../services/audio_converter.dart';
import '../services/audio_engine_service.dart';
import '../services/local_storage_service.dart';
import '../services/log_collector.dart';
import '../services/storage/upload_queue_manager.dart';
import '../services/streaming_service.dart';

class AppState extends ChangeNotifier {
  final AudioEngineService _audioEngine = AudioEngineService.instance;
  final StreamingService _streaming = StreamingService.instance;
  final UploadQueueManager _uploadQueue = UploadQueueManager.instance;
  final LocalStorageService _storage = LocalStorageService.instance;

  LogCollector get logCollector => LogCollector.instance;

  // Configurations
  AudioRecordingConfig _audioConfig = const AudioRecordingConfig();
  SlicerConfig _slicerConfig = const SlicerConfig();
  WebDavConfig _webdavConfig = const WebDavConfig();
  S3Config _s3Config = const S3Config();
  StreamingConfig _streamingConfig = const StreamingConfig();

  // Hardware Devices
  List<AudioInputDevice> _devices = [];
  AudioInputDevice? _selectedDevice;
  bool _isLoadingDevices = false;

  // Live Recording Status
  bool _isRecording = false;
  bool _isPaused = false;
  int _recordingDurationSeconds = 0;
  Timer? _durationTimer;
  double _currentAmplitude = 0.0;
  double _currentDb = 0.0;
  final List<double> _waveformHistory = List<double>.filled(50, 0.0, growable: true);

  // Subscriptions
  StreamSubscription? _audioFrameSub;
  StreamSubscription? _sliceCompletedSub;

  // WAV slices produced during the current session (transcoded to MP3 on stop
  // when the user selected MP3; Opus is already native on Android).
  final List<String> _sessionWavPaths = [];

  // Getters
  AudioRecordingConfig get audioConfig => _audioConfig;
  SlicerConfig get slicerConfig => _slicerConfig;
  WebDavConfig get webdavConfig => _webdavConfig;
  S3Config get s3Config => _s3Config;
  StreamingConfig get streamingConfig => _streamingConfig;

  List<AudioInputDevice> get devices => _devices;
  AudioInputDevice? get selectedDevice => _selectedDevice;
  bool get isLoadingDevices => _isLoadingDevices;

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  int get recordingDurationSeconds => _recordingDurationSeconds;
  double get currentAmplitude => _currentAmplitude;
  double get currentDb => _currentDb;
  List<double> get waveformHistory => List.unmodifiable(_waveformHistory);

  StreamingService get streaming => _streaming;
  UploadQueueManager get uploadQueue => _uploadQueue;
  LocalStorageService get storage => _storage;

  Future<void> initialize() async {
    await LogCollector.instance.initialize();
    LogCollector.instance.log('AppState', 'vibeARS 启动');
    await _loadPreferences();
    await _audioEngine.initialize();
    await _storage.initialize();
    await _uploadQueue.loadHistory();

    // Bridge notifications from child services so that any UI that watches
    // AppState also rebuilds when playback/upload/streaming state changes.
    // Without this, tapping play (or an upload progress tick) would never
    // refresh the screens.
    _storage.addListener(_forwardNotification);
    _uploadQueue.addListener(_forwardNotification);
    _streaming.addListener(_forwardNotification);

    _uploadQueue.configure(
      webdavConfig: _webdavConfig,
      s3Config: _s3Config,
      slicerConfig: _slicerConfig,
    );

    _streaming.configure(_streamingConfig);

    // Listen to real-time audio frame stream
    _audioFrameSub = _audioEngine.audioFrameStream.listen((data) {
      _currentAmplitude = (data['amplitude'] as num?)?.toDouble() ?? 0.0;
      _currentDb = (data['db'] as num?)?.toDouble() ?? 0.0;

      // Update rolling waveform visualizer buffer
      _waveformHistory.removeAt(0);
      _waveformHistory.add(_currentAmplitude);

      // Dispatch to real-time streaming pipeline if active. The uplink
      // carries AAC/ADTS frames when the webSocketAac protocol is selected
      // (encoding happens natively), otherwise raw PCM bytes.
      if (_streamingConfig.enabled && _streaming.state == StreamingState.connected) {
        if (_streamingConfig.protocol == StreamingProtocol.webSocketAac) {
          final aac = data['aac'];
          if (aac is Uint8List) {
            _streaming.sendAudioChunk(aac);
          } else if (aac is List<int>) {
            _streaming.sendAudioChunk(Uint8List.fromList(aac));
          }
        } else {
          final pcm = data['pcm'];
          if (pcm is Uint8List) {
            _streaming.sendAudioChunk(pcm);
          } else if (pcm is List<int>) {
            _streaming.sendAudioChunk(Uint8List.fromList(pcm));
          }
        }
      }

      notifyListeners();
    });

    // Listen to 5-min slice completed events
    _sliceCompletedSub = _audioEngine.sliceCompletedStream.listen((data) {
      final sliceItem = AudioSliceItem.fromJson(data);
      // Track WAV slices of the current session for MP3 post-transcoding.
      if (sliceItem.fileName.toLowerCase().endsWith('.wav')) {
        _sessionWavPaths.add(sliceItem.localPath);
      }
      _uploadQueue.enqueueSlice(sliceItem);
      _storage.refreshFiles();
      // Dashcam-style loop recording: prune oldest unlocked slices if the
      // storage quota is exceeded.
      _storage.pruneForLoopRecording();
      notifyListeners();
    });

    await refreshDevices();
  }

  Future<void> refreshDevices() async {
    _isLoadingDevices = true;
    notifyListeners();

    try {
      _devices = await _audioEngine.getAudioDevices();
      LogCollector.instance.log('AppState', '设备枚举完成: ${_devices.length} 个输入设备');
      if (_devices.isNotEmpty) {
        if (_audioConfig.preferredDeviceId != null) {
          _selectedDevice = _devices.firstWhere(
            (d) => d.id == _audioConfig.preferredDeviceId,
            orElse: () => _devices.first,
          );
        } else {
          _selectedDevice = _devices.firstWhere((d) => d.isSelected || d.isDefault, orElse: () => _devices.first);
        }
      }
    } catch (e) {
      print('[AppState] Error loading devices: $e');
    } finally {
      _isLoadingDevices = false;
      notifyListeners();
    }
  }

  Future<void> selectDevice(AudioInputDevice device) async {
    _selectedDevice = device;
    // Bluetooth SCO capture only supports 8/16 kHz mono; force compatible
    // settings so the recording session can actually start.
    if (device.type == AudioDeviceType.bluetoothSco) {
      _audioConfig = _audioConfig.copyWith(
        preferredDeviceId: device.id,
        sampleRate: 16000,
        channelCount: 1,
      );
    } else {
      _audioConfig = _audioConfig.copyWith(preferredDeviceId: device.id);
    }
    LogCollector.instance.log(
      'AppState',
      '选择设备: ${device.name} (${device.type.name}, id=${device.id}) 格式=${_audioConfig.sampleRate}Hz/${_audioConfig.channelCount}ch',
    );
    notifyListeners();
    await _savePreferences();
  }

  /// Selects a device AND the output format (sample rate / channel count)
  /// it should capture in. Takes effect on the next recording session.
  Future<void> selectDeviceFormat(
    AudioInputDevice device, {
    int? sampleRate,
    int? channelCount,
  }) async {
    _selectedDevice = device;
    final isSco = device.type == AudioDeviceType.bluetoothSco;
    _audioConfig = _audioConfig.copyWith(
      preferredDeviceId: device.id,
      // SCO devices are limited to 8/16 kHz mono by the HFP profile.
      sampleRate: isSco
          ? 16000
          : (sampleRate ?? _audioConfig.sampleRate),
      channelCount: isSco ? 1 : (channelCount ?? _audioConfig.channelCount),
    );
    LogCollector.instance.log(
      'AppState',
      '设备 ${device.name} 输出格式: ${_audioConfig.sampleRate}Hz / ${_audioConfig.channelCount}ch (SCO 自动 16kHz 单声道=$isSco)',
    );
    notifyListeners();
    await _savePreferences();
  }

  Future<bool> startRecording() async {
    // Request microphone permission
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      LogCollector.instance.log('AppState', '麦克风权限被拒绝，录音无法启动');
      print('[AppState] Microphone permission denied');
      return false;
    }

    if (Platform.isAndroid) {
      await Permission.notification.request();
      await Permission.bluetoothConnect.request();
      await _audioEngine.requestIgnoreBatteryOptimizations();
    }

    LogCollector.instance.log(
      'AppState',
      '启动录音: 设备=${_selectedDevice?.name ?? "默认"} 采样率=${_audioConfig.sampleRate} 声道=${_audioConfig.channelCount} 格式=${_audioConfig.format.name} 码率=${_audioConfig.bitRate}',
    );

    // Connect real-time streaming if enabled
    if (_streamingConfig.enabled && _streamingConfig.isValid) {
      _streaming.connect();
    }

    final storagePath = await _storage.getActiveStoragePath();
    final success = await _audioEngine.startRecording(
      audioConfig: _audioConfig,
      slicerConfig: _slicerConfig,
      storagePath: storagePath,
      uplinkAac: _streamingConfig.enabled &&
          _streamingConfig.protocol == StreamingProtocol.webSocketAac,
    );

    LogCollector.instance.log('AppState', '录音启动结果: ${success ? "成功" : "失败"}');

    if (success) {
      _isRecording = true;
      _isPaused = false;
      _recordingDurationSeconds = 0;
      _startDurationTimer();
      notifyListeners();
    }

    return success;
  }

  Future<void> pauseRecording() async {
    final success = await _audioEngine.pauseRecording();
    if (success) {
      _isPaused = true;
      _durationTimer?.cancel();
      notifyListeners();
    }
  }

  Future<void> resumeRecording() async {
    final success = await _audioEngine.resumeRecording();
    if (success) {
      _isPaused = false;
      _startDurationTimer();
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    LogCollector.instance.log('AppState', '停止录音，本次时长 ${_recordingDurationSeconds}s');
    await _audioEngine.stopRecording();
    _isRecording = false;
    _isPaused = false;
    _durationTimer?.cancel();
    _durationTimer = null;
    _currentAmplitude = 0.0;
    _currentDb = 0.0;

    if (_streaming.state != StreamingState.disconnected) {
      _streaming.disconnect();
    }

    await _storage.refreshFiles();

    // MP3 sessions: transcode the session's WAV slices with the bundled LAME
    // encoder and remove the intermediates.
    final wavs = List<String>.from(_sessionWavPaths);
    _sessionWavPaths.clear();
    if (wavs.isNotEmpty && _audioConfig.format == AudioFormatType.mp3) {
      LogCollector.instance.log('AppState', 'MP3 模式：转码 ${wavs.length} 个切片');
      for (final wav in wavs) {
        final outDir = _storage.customStoragePath.isNotEmpty
            ? _storage.customStoragePath
            : await _storage.getActiveStoragePath();
        final mp3 = await AudioConverter.wavToMp3(
          inputPath: wav,
          bitRate: _audioConfig.bitRate,
          outputDir: outDir,
        );
        if (mp3 != null) {
          try {
            final f = File(wav);
            if (await f.exists()) await f.delete();
          } catch (_) {}
          await _storage.refreshFiles();
        }
      }
    }

    LogCollector.instance.log('AppState', '录音已停止并归档，录音库共 ${_storage.files.length} 个文件');
    notifyListeners();
  }

  void _forwardNotification() {
    notifyListeners();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isRecording && !_isPaused) {
        _recordingDurationSeconds++;
        notifyListeners();
      }
    });
  }

  // Update Configs
  Future<void> updateAudioConfig(AudioRecordingConfig config) async {
    _audioConfig = config;
    notifyListeners();
    await _savePreferences();
  }

  Future<void> updateSlicerConfig(SlicerConfig config) async {
    _slicerConfig = config;
    _uploadQueue.configure(
      webdavConfig: _webdavConfig,
      s3Config: _s3Config,
      slicerConfig: _slicerConfig,
    );
    notifyListeners();
    await _savePreferences();
  }

  Future<void> updateWebDavConfig(WebDavConfig config) async {
    _webdavConfig = config;
    _uploadQueue.configure(
      webdavConfig: _webdavConfig,
      s3Config: _s3Config,
      slicerConfig: _slicerConfig,
    );
    notifyListeners();
    await _savePreferences();
  }

  Future<void> updateS3Config(S3Config config) async {
    _s3Config = config;
    _uploadQueue.configure(
      webdavConfig: _webdavConfig,
      s3Config: _s3Config,
      slicerConfig: _slicerConfig,
    );
    notifyListeners();
    await _savePreferences();
  }

  Future<void> updateStreamingConfig(StreamingConfig config) async {
    _streamingConfig = config;
    _streaming.configure(config);
    notifyListeners();
    await _savePreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final sp = await SharedPreferences.getInstance();

      final audioJson = sp.getString('vibears_audio_config');
      if (audioJson != null) {
        _audioConfig = AudioRecordingConfig.fromJson(jsonDecode(audioJson));
      }

      final slicerJson = sp.getString('vibears_slicer_config');
      if (slicerJson != null) {
        _slicerConfig = SlicerConfig.fromJson(jsonDecode(slicerJson));
      }

      final webdavJson = sp.getString('vibears_webdav_config');
      if (webdavJson != null) {
        _webdavConfig = WebDavConfig.fromJson(jsonDecode(webdavJson));
      }

      final s3Json = sp.getString('vibears_s3_config');
      if (s3Json != null) {
        _s3Config = S3Config.fromJson(jsonDecode(s3Json));
      }

      final streamJson = sp.getString('vibears_stream_config');
      if (streamJson != null) {
        _streamingConfig = StreamingConfig.fromJson(jsonDecode(streamJson));
      }
    } catch (e) {
      print('[AppState] Error loading preferences: $e');
    }
  }

  Future<void> _savePreferences() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('vibears_audio_config', jsonEncode(_audioConfig.toJson()));
      await sp.setString('vibears_slicer_config', jsonEncode(_slicerConfig.toJson()));
      await sp.setString('vibears_webdav_config', jsonEncode(_webdavConfig.toJson()));
      await sp.setString('vibears_s3_config', jsonEncode(_s3Config.toJson()));
      await sp.setString('vibears_stream_config', jsonEncode(_streamingConfig.toJson()));
    } catch (e) {
      print('[AppState] Error saving preferences: $e');
    }
  }

  @override
  void dispose() {
    _storage.removeListener(_forwardNotification);
    _uploadQueue.removeListener(_forwardNotification);
    _streaming.removeListener(_forwardNotification);
    _audioFrameSub?.cancel();
    _sliceCompletedSub?.cancel();
    _durationTimer?.cancel();
    _audioEngine.dispose();
    _streaming.dispose();
    _storage.dispose();
    super.dispose();
  }
}
