enum AudioFormatType {
  aacM4a,
  wav,
  mp3,
  opus;

  String get displayName {
    switch (this) {
      case AudioFormatType.aacM4a:
        return 'AAC / M4A (高兼容/推荐)';
      case AudioFormatType.wav:
        return 'WAV (无损 PCM)';
      case AudioFormatType.mp3:
        return 'MP3 (标准音频)';
      case AudioFormatType.opus:
        return 'Opus / OGG (超高压缩/人声优化)';
    }
  }

  String get fileExtension {
    switch (this) {
      case AudioFormatType.aacM4a:
        return 'm4a';
      case AudioFormatType.wav:
        return 'wav';
      case AudioFormatType.mp3:
        return 'mp3';
      case AudioFormatType.opus:
        return 'opus';
    }
  }

  String get mimeType {
    switch (this) {
      case AudioFormatType.aacM4a:
        return 'audio/mp4';
      case AudioFormatType.wav:
        return 'audio/wav';
      case AudioFormatType.mp3:
        return 'audio/mpeg';
      case AudioFormatType.opus:
        return 'audio/opus';
    }
  }
}

class AudioRecordingConfig {
  final AudioFormatType format;
  final int sampleRate; // 16000, 44100, 48000
  final int channelCount; // 1 = Mono, 2 = Stereo
  final int bitRate; // e.g. 64000, 128000, 192000, 256000, 320000
  final String? preferredDeviceId;
  final bool enableAec; // Acoustic Echo Cancellation
  final bool enableNs; // Noise Suppression
  final bool enableAgc; // Automatic Gain Control

  const AudioRecordingConfig({
    this.format = AudioFormatType.aacM4a,
    this.sampleRate = 48000,
    this.channelCount = 2,
    this.bitRate = 192000,
    this.preferredDeviceId,
    this.enableAec = false,
    this.enableNs = true,
    this.enableAgc = true,
  });

  factory AudioRecordingConfig.fromJson(Map<String, dynamic> json) {
    return AudioRecordingConfig(
      format: AudioFormatType.values.firstWhere(
        (e) => e.name == json['format'],
        orElse: () => AudioFormatType.aacM4a,
      ),
      sampleRate: json['sampleRate'] as int? ?? 48000,
      channelCount: json['channelCount'] as int? ?? 2,
      bitRate: json['bitRate'] as int? ?? 192000,
      preferredDeviceId: json['preferredDeviceId'] as String?,
      enableAec: json['enableAec'] as bool? ?? false,
      enableNs: json['enableNs'] as bool? ?? true,
      enableAgc: json['enableAgc'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'format': format.name,
      'sampleRate': sampleRate,
      'channelCount': channelCount,
      'bitRate': bitRate,
      'preferredDeviceId': preferredDeviceId,
      'enableAec': enableAec,
      'enableNs': enableNs,
      'enableAgc': enableAgc,
    };
  }

  AudioRecordingConfig copyWith({
    AudioFormatType? format,
    int? sampleRate,
    int? channelCount,
    int? bitRate,
    String? preferredDeviceId,
    bool? enableAec,
    bool? enableNs,
    bool? enableAgc,
  }) {
    return AudioRecordingConfig(
      format: format ?? this.format,
      sampleRate: sampleRate ?? this.sampleRate,
      channelCount: channelCount ?? this.channelCount,
      bitRate: bitRate ?? this.bitRate,
      preferredDeviceId: preferredDeviceId ?? this.preferredDeviceId,
      enableAec: enableAec ?? this.enableAec,
      enableNs: enableNs ?? this.enableNs,
      enableAgc: enableAgc ?? this.enableAgc,
    );
  }
}
