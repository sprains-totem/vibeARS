enum StreamingProtocol {
  webSocketOpus,
  webSocketPcm,
  webrtcAudio;

  String get displayName {
    switch (this) {
      case StreamingProtocol.webSocketOpus:
        return 'WebSocket (Opus 低延迟高压缩编码)';
      case StreamingProtocol.webSocketPcm:
        return 'WebSocket (PCM 原始高保真流)';
      case StreamingProtocol.webrtcAudio:
        return 'WebRTC (超低延迟双向通话/直播)';
    }
  }
}

enum StreamingState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error;

  String get displayName {
    switch (this) {
      case StreamingState.disconnected:
        return '未连接';
      case StreamingState.connecting:
        return '正在连接...';
      case StreamingState.connected:
        return '实时推流中';
      case StreamingState.reconnecting:
        return '断线重连中...';
      case StreamingState.error:
        return '连接异常';
    }
  }
}

class StreamingConfig {
  final bool enabled;
  final String serverUrl; // wss://your-server.com/audio/stream or webrtc://...
  final StreamingProtocol protocol;
  final String authToken;
  final String streamId;
  final int bufferDurationMs; // e.g. 20ms or 40ms per packet
  final bool autoReconnect;

  const StreamingConfig({
    this.enabled = false,
    this.serverUrl = '',
    this.protocol = StreamingProtocol.webSocketOpus,
    this.authToken = '',
    this.streamId = '',
    this.bufferDurationMs = 20,
    this.autoReconnect = true,
  });

  factory StreamingConfig.fromJson(Map<String, dynamic> json) {
    return StreamingConfig(
      enabled: json['enabled'] as bool? ?? false,
      serverUrl: json['serverUrl'] as String? ?? '',
      protocol: StreamingProtocol.values.firstWhere(
        (e) => e.name == json['protocol'],
        orElse: () => StreamingProtocol.webSocketOpus,
      ),
      authToken: json['authToken'] as String? ?? '',
      streamId: json['streamId'] as String? ?? '',
      bufferDurationMs: json['bufferDurationMs'] as int? ?? 20,
      autoReconnect: json['autoReconnect'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'serverUrl': serverUrl,
      'protocol': protocol.name,
      'authToken': authToken,
      'streamId': streamId,
      'bufferDurationMs': bufferDurationMs,
      'autoReconnect': autoReconnect,
    };
  }

  StreamingConfig copyWith({
    bool? enabled,
    String? serverUrl,
    StreamingProtocol? protocol,
    String? authToken,
    String? streamId,
    int? bufferDurationMs,
    bool? autoReconnect,
  }) {
    return StreamingConfig(
      enabled: enabled ?? this.enabled,
      serverUrl: serverUrl ?? this.serverUrl,
      protocol: protocol ?? this.protocol,
      authToken: authToken ?? this.authToken,
      streamId: streamId ?? this.streamId,
      bufferDurationMs: bufferDurationMs ?? this.bufferDurationMs,
      autoReconnect: autoReconnect ?? this.autoReconnect,
    );
  }

  bool get isValid => serverUrl.trim().isNotEmpty;
}

class StreamingStats {
  final int bytesSent;
  final int packetsSent;
  final double currentBitrateKbps;
  final int latencyMs;
  final int droppedPackets;

  const StreamingStats({
    this.bytesSent = 0,
    this.packetsSent = 0,
    this.currentBitrateKbps = 0.0,
    this.latencyMs = 0,
    this.droppedPackets = 0,
  });
}
