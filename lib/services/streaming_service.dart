import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/models/streaming_config.dart';

class StreamingService extends ChangeNotifier {
  static final StreamingService instance = StreamingService._internal();
  StreamingService._internal();

  WebSocketChannel? _channel;
  StreamingConfig _config = const StreamingConfig();
  StreamingState _state = StreamingState.disconnected;
  StreamingStats _stats = const StreamingStats();

  Timer? _statsTimer;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _bytesInCurrentSecond = 0;
  int _totalBytesSent = 0;
  int _totalPacketsSent = 0;
  int _droppedPackets = 0;
  DateTime? _lastPingTime;
  int _lastLatencyMs = 0;
  bool _manuallyClosed = false;

  StreamingState get state => _state;
  StreamingStats get stats => _stats;
  StreamingConfig get config => _config;

  void configure(StreamingConfig config) {
    _config = config;
    notifyListeners();
  }

  Future<void> connect() async {
    if (_state == StreamingState.connected || _state == StreamingState.connecting) {
      return;
    }
    if (!_config.isValid) {
      _setState(StreamingState.error);
      return;
    }

    _manuallyClosed = false;
    _setState(StreamingState.connecting);
    _resetStats();
    _startStatsTimer();

    try {
      final uri = Uri.parse(_config.serverUrl);
      final headers = <String, dynamic>{};
      if (_config.authToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${_config.authToken}';
      }

      final channel = IOWebSocketChannel.connect(
        uri,
        headers: headers,
        pingInterval: const Duration(seconds: 10),
      );
      _channel = channel;

      // Wait for the underlying socket to actually open before reporting connected.
      await channel.ready.timeout(const Duration(seconds: 15));

      // Listen for server incoming messages (Heartbeats, ACK, control messages)
      channel.stream.listen(
        (message) {
          _handleServerMessage(message);
        },
        onDone: () {
          print('[StreamingService] WebSocket stream closed');
          if (!_manuallyClosed) {
            _onDisconnect();
          } else {
            _setState(StreamingState.disconnected);
          }
        },
        onError: (error) {
          print('[StreamingService] WebSocket error: $error');
          if (!_manuallyClosed) {
            _onDisconnect();
          }
        },
        cancelOnError: true,
      );

      _setState(StreamingState.connected);
      _sendHandshake();
      _startHeartbeat();
    } catch (e) {
      print('[StreamingService] Connection error: $e');
      _channel?.sink.close();
      _channel = null;
      if (!_manuallyClosed) {
        _onDisconnect();
      } else {
        _setState(StreamingState.disconnected);
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_state != StreamingState.connected || _channel == null) return;
      _lastPingTime = DateTime.now();
      try {
        _channel?.sink.add(
          jsonEncode({
            'event': 'ping',
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );
      } catch (_) {}
    });
  }

  void _sendHandshake() {
    try {
      final handshake = {
        'event': 'handshake',
        'streamId': _config.streamId.isNotEmpty ? _config.streamId : 'vibe_${DateTime.now().millisecondsSinceEpoch}',
        'protocol': _config.protocol.name,
        'timestamp': DateTime.now().toIso8601String(),
        'client': 'vibeARS-Mobile',
      };
      _channel?.sink.add(jsonEncode(handshake));
    } catch (e) {
      print('[StreamingService] Handshake error: $e');
    }
  }

  void sendAudioChunk(Uint8List pcmBytes) {
    if (_state != StreamingState.connected || _channel == null) {
      _droppedPackets++;
      return;
    }

    try {
      _channel?.sink.add(pcmBytes);
      _bytesInCurrentSecond += pcmBytes.length;
      _totalBytesSent += pcmBytes.length;
      _totalPacketsSent++;
    } catch (e) {
      _droppedPackets++;
      print('[StreamingService] Error sending audio chunk: $e');
    }
  }

  void _handleServerMessage(dynamic message) {
    try {
      if (message is String) {
        final decoded = jsonDecode(message);
        if (decoded is Map && decoded['event'] == 'pong') {
          if (_lastPingTime != null) {
            _lastLatencyMs = DateTime.now().difference(_lastPingTime!).inMilliseconds;
          }
        }
      }
    } catch (_) {}
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final kbps = (_bytesInCurrentSecond * 8) / 1024.0;
      _bytesInCurrentSecond = 0;

      _stats = StreamingStats(
        bytesSent: _totalBytesSent,
        packetsSent: _totalPacketsSent,
        currentBitrateKbps: kbps,
        latencyMs: _lastLatencyMs,
        droppedPackets: _droppedPackets,
      );
      notifyListeners();
    });
  }

  void _onDisconnect() {
    if (_config.autoReconnect) {
      _setState(StreamingState.reconnecting);
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        if (_state == StreamingState.reconnecting && !_manuallyClosed) {
          connect();
        }
      });
    } else {
      _setState(StreamingState.disconnected);
    }
  }

  void disconnect() {
    _manuallyClosed = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _statsTimer?.cancel();
    _setState(StreamingState.disconnected);
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _resetStats();
  }

  void _setState(StreamingState newState) {
    _state = newState;
    notifyListeners();
  }

  void _resetStats() {
    _bytesInCurrentSecond = 0;
    _totalBytesSent = 0;
    _totalPacketsSent = 0;
    _droppedPackets = 0;
    _lastLatencyMs = 0;
    _stats = const StreamingStats();
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
