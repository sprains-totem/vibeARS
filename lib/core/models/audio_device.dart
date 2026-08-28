enum AudioDeviceType {
  builtInMic,
  builtInSpeaker,
  wiredHeadset,
  wiredHeadphones,
  bluetoothSco,
  bluetoothA2dp,
  bluetoothLe,
  usbAudio,
  auxLine,
  telephony,
  unknown;

  static AudioDeviceType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'builtinmic':
      case 'built_in_mic':
      case 'builtin_mic':
      case 'microphone':
        return AudioDeviceType.builtInMic;
      case 'wiredheadset':
      case 'wired_headset':
      case 'headset':
        return AudioDeviceType.wiredHeadset;
      case 'wiredheadphones':
      case 'wired_headphones':
        return AudioDeviceType.wiredHeadphones;
      case 'bluetoothsco':
      case 'bluetooth_sco':
      case 'bluetoothhfp':
        return AudioDeviceType.bluetoothSco;
      case 'bluetootha2dp':
      case 'bluetooth_a2dp':
        return AudioDeviceType.bluetoothA2dp;
      case 'bluetoothle':
      case 'bluetooth_le':
        return AudioDeviceType.bluetoothLe;
      case 'usbaudio':
      case 'usb_audio':
      case 'usb_device':
      case 'usb_headset':
        return AudioDeviceType.usbAudio;
      default:
        return AudioDeviceType.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case AudioDeviceType.builtInMic:
        return '内置麦克风 (Built-in Mic)';
      case AudioDeviceType.wiredHeadset:
        return '有线耳机麦克风 (Wired Headset)';
      case AudioDeviceType.bluetoothSco:
        return '蓝牙耳机 (Bluetooth HFP/SCO)';
      case AudioDeviceType.bluetoothA2dp:
        return '蓝牙高质量音频 (Bluetooth A2DP)';
      case AudioDeviceType.bluetoothLe:
        return '低功耗蓝牙 (Bluetooth LE)';
      case AudioDeviceType.usbAudio:
        return 'USB声卡/麦克风 (USB Audio Interface)';
      case AudioDeviceType.auxLine:
        return '线路输入 (Line-in)';
      default:
        return '未知设备 (External Audio Device)';
    }
  }
}

class AudioInputDevice {
  final String id;
  final String name;
  final AudioDeviceType type;
  final List<int> sampleRates;
  final List<int> channelCounts;
  final List<String> encodings;
  final List<String> polarPatterns;
  final bool isSelected;
  final bool isDefault;

  const AudioInputDevice({
    required this.id,
    required this.name,
    required this.type,
    this.sampleRates = const [16000, 44100, 48000],
    this.channelCounts = const [1, 2],
    this.encodings = const ['PCM_16BIT'],
    this.polarPatterns = const [],
    this.isSelected = false,
    this.isDefault = false,
  });

  factory AudioInputDevice.fromJson(Map<String, dynamic> json) {
    return AudioInputDevice(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Device',
      type: AudioDeviceType.fromString(json['type']?.toString() ?? ''),
      sampleRates: (json['sampleRates'] as List<dynamic>?)
              ?.map((e) => int.tryParse(e.toString()) ?? 0)
              .where((e) => e > 0)
              .toList() ??
          [16000, 44100, 48000],
      channelCounts: (json['channelCounts'] as List<dynamic>?)
              ?.map((e) => int.tryParse(e.toString()) ?? 0)
              .where((e) => e > 0)
              .toList() ??
          [1, 2],
      encodings: (json['encodings'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['PCM_16BIT'],
      polarPatterns: (json['polarPatterns'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      isSelected: json['isSelected'] == true,
      isDefault: json['isDefault'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'sampleRates': sampleRates,
      'channelCounts': channelCounts,
      'encodings': encodings,
      'polarPatterns': polarPatterns,
      'isSelected': isSelected,
      'isDefault': isDefault,
    };
  }

  AudioInputDevice copyWith({
    String? id,
    String? name,
    AudioDeviceType? type,
    List<int>? sampleRates,
    List<int>? channelCounts,
    List<String>? encodings,
    List<String>? polarPatterns,
    bool? isSelected,
    bool? isDefault,
  }) {
    return AudioInputDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      sampleRates: sampleRates ?? this.sampleRates,
      channelCounts: channelCounts ?? this.channelCounts,
      encodings: encodings ?? this.encodings,
      polarPatterns: polarPatterns ?? this.polarPatterns,
      isSelected: isSelected ?? this.isSelected,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
