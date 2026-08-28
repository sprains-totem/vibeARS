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
import '../services/audio_engine_service.dart';
import '../services/local_storage_service.dart';
import '../services/storage/upload_queue_manager.dart';
import '../services/streaming_service.dart';

class AppState extends ChangeNotifier {
  final AudioEngineService _audioEngine = AudioEngineService.instance;
  final StreamingService _streaming = StreamingService.instance;
  final UploadQueueManager _uploadQueue = UploadQueueManager.instance;
  final LocalStorageService _storage = LocalStorageService.instance;

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
  final List<double> _waveformHistory = List.filled(50, 0.0);

  // Subscriptions
  StreamSubscription? _audioFrameSub;
  StreamSubscription? _sliceCompletedSub;

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
    await _loadPreferences();
    await _audioEngine.initialize();
    _storage.initialize();
    await _uploadQueue.loadHistory();

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

      // Dispatch to real-time streaming pipeline if active
      if (_streamingConfig.enabled && _streaming.state == StreamingState.connected) {
        final pcm = data['pcm'];
        if (pcm is Uint8List) {
          _streaming.sendAudioChunk(pcm);
        } else if (pcm is List<int>) {
          _streaming.sendAudioChunk(Uint8List.fromList(pcm));
        }
      }

      notifyListeners();
    });

    // Listen to 5-min slice completed events
    _sliceCompletedSub = _audioEngine.sliceCompletedStream.listen((data) {
      final sliceItem = AudioSliceItem.fromJson(data);
      _uploadQueue.enqueueSlice(sliceItem);
      _storage.refreshFiles();
      notifyListeners();
    });

    await refreshDevices();
  }

  Future<void> refreshDevices() async {
    _isLoadingDevices = true;
    notifyListeners();

    try {
      _devices = await _audioEngine.getAudioDevices();
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
    _audioConfig = _audioConfig.copyWith(preferredDeviceId: device.id);
    notifyListeners();
    await _savePreferences();
  }

  Future<bool> startRecording() async {
    // Request microphone permission
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      print('[AppState] Microphone permission denied');
      return false;
    }

    if (Platform.isAndroid) {
      await Permission.notification.request();
      await Permission.bluetoothConnect.request();
      await _audioEngine.requestIgnoreBatteryOptimizations();
    }

    // Connect real-time streaming if enabled
    if (_streamingConfig.enabled && _streamingConfig.isValid) {
      _streaming.connect();
    }

    final success = await _audioEngine.startRecording(
      audioConfig: _audioConfig,
      slicerConfig: _slicerConfig,
    );

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
    _audioFrameSub?.cancel();
    _sliceCompletedSub?.cancel();
    _durationTimer?.cancel();
    _audioEngine.dispose();
    _streaming.dispose();
    _storage.dispose();
    super.dispose();
  }
}
