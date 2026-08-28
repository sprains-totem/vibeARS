import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/streaming_config.dart';
import '../../providers/app_state.dart';
import '../theme.dart';

class StreamingScreen extends StatefulWidget {
  const StreamingScreen({super.key});

  @override
  State<StreamingScreen> createState() => _StreamingScreenState();
}

class _StreamingScreenState extends State<StreamingScreen> {
  late TextEditingController _urlController;
  late TextEditingController _tokenController;
  late TextEditingController _streamIdController;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppState>().streamingConfig;
    _urlController = TextEditingController(text: config.serverUrl);
    _tokenController = TextEditingController(text: config.authToken);
    _streamIdController = TextEditingController(text: config.streamId);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _streamIdController.dispose();
    super.dispose();
  }

  void _saveConfig(AppState state) {
    final updated = state.streamingConfig.copyWith(
      serverUrl: _urlController.text.trim(),
      authToken: _tokenController.text.trim(),
      streamId: _streamIdController.text.trim(),
    );
    state.updateStreamingConfig(updated);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final streaming = state.streaming;
    final config = state.streamingConfig;
    final stats = streaming.stats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('实时流式传输 (Live Streaming)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Streaming Master Switch Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '实时流式音频推流',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Switch(
                        value: config.enabled,
                        activeColor: VibeTheme.primaryNeon,
                        onChanged: (val) {
                          final updated = config.copyWith(enabled: val);
                          state.updateStreamingConfig(updated);
                        },
                      ),
                    ],
                  ),
                  const Text(
                    '支持低延迟通话/直播级音频实时上行推流，支持云端即时 ASR、语音对话与 AI 实时处理。',
                    style: TextStyle(fontSize: 12, color: VibeTheme.textSecondary),
                  ),
                  const Divider(height: 24, color: Color(0xFF2C394B)),

                  // Protocol selection
                  const Text('推流协议 (Streaming Protocol)：', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: StreamingProtocol.values.map((proto) {
                      final isSelected = config.protocol == proto;
                      return ChoiceChip(
                        label: Text(proto.displayName),
                        selected: isSelected,
                        selectedColor: VibeTheme.primaryNeon,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.black : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            state.updateStreamingConfig(config.copyWith(protocol: proto));
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: '推流服务器 WebSocket / WebRTC URL',
                      hintText: 'wss://your-asr-server.com/audio/live',
                      prefixIcon: Icon(Icons.link),
                    ),
                    onChanged: (_) => _saveConfig(state),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _tokenController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '鉴权 Token / Bearer Key (可选)',
                      prefixIcon: Icon(Icons.security),
                    ),
                    onChanged: (_) => _saveConfig(state),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _streamIdController,
                    decoration: const InputDecoration(
                      labelText: '自定义流 ID / 房间号 (可选)',
                      hintText: 'room_1001_mic_master',
                      prefixIcon: Icon(Icons.tag),
                    ),
                    onChanged: (_) => _saveConfig(state),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Realtime Telemetry & Diagnostics Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '推流实时遥测数据 (Telemetry)',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: streaming.state == StreamingState.connected
                              ? VibeTheme.successGreen.withOpacity(0.2)
                              : VibeTheme.cardSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: streaming.state == StreamingState.connected
                                ? VibeTheme.successGreen
                                : Colors.grey,
                          ),
                        ),
                        child: Text(
                          streaming.state.displayName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: streaming.state == StreamingState.connected
                                ? VibeTheme.successGreen
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24, color: Color(0xFF2C394B)),

                  Row(
                    children: [
                      _TelemetryItem(
                        label: '实时码率',
                        value: '${stats.currentBitrateKbps.toStringAsFixed(1)} kbps',
                        icon: Icons.speed,
                        color: VibeTheme.primaryNeon,
                      ),
                      _TelemetryItem(
                        label: '往返延迟',
                        value: '${stats.latencyMs} ms',
                        icon: Icons.timer,
                        color: VibeTheme.accentAmber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      _TelemetryItem(
                        label: '已发数据量',
                        value: '${(stats.bytesSent / (1024 * 1024)).toStringAsFixed(2)} MB',
                        icon: Icons.data_usage,
                        color: Colors.blueAccent,
                      ),
                      _TelemetryItem(
                        label: '已发数据包',
                        value: '${stats.packetsSent} pkts',
                        icon: Icons.unarchive,
                        color: Colors.purpleAccent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TelemetryItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _TelemetryItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: VibeTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 12, color: VibeTheme.textSecondary)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
