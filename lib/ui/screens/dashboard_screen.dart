import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/streaming_config.dart';
import '../../providers/app_state.dart';
import '../theme.dart';
import '../widgets/waveform_visualizer.dart';
import 'diagnostics_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('vibeARS 录音工作台'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: '诊断日志 (一键导出)',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新硬件与状态',
            onPressed: () => state.refreshDevices(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Current Active Microphone Header Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: VibeTheme.primaryNeon.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.mic, color: VibeTheme.primaryNeon, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '当前输入源 (Input Device)',
                            style: TextStyle(color: VibeTheme.textSecondary, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            state.selectedDevice?.name ?? '内置麦克风 (Default Mic)',
                            style: const TextStyle(
                              color: VibeTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${state.audioConfig.sampleRate} Hz · ${state.audioConfig.channelCount == 1 ? "单声道" : "双声道"} · ${state.audioConfig.format.fileExtension.toUpperCase()}',
                            style: const TextStyle(color: VibeTheme.primaryNeon, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Audio Waveform Visualizer
            WaveformVisualizer(
              waveform: state.waveformHistory,
              db: state.currentDb,
              isRecording: state.isRecording,
              isPaused: state.isPaused,
            ),
            const SizedBox(height: 20),

            // 3. Recording Duration Timer
            Center(
              child: Column(
                children: [
                  const Text(
                    '录音累计时长',
                    style: TextStyle(color: VibeTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatDuration(state.recordingDurationSeconds),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: VibeTheme.textPrimary,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 4. Main Control Buttons (Record / Pause / Resume / Stop)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!state.isRecording) ...[
                  ElevatedButton.icon(
                    onPressed: () async {
                      final ok = await state.startRecording();
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('录音启动失败：请检查麦克风权限与存储路径可写性'),
                            backgroundColor: VibeTheme.errorRed,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VibeTheme.errorRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    icon: const Icon(Icons.fiber_manual_record, size: 24),
                    label: const Text('开始不间断录音', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ] else ...[
                  // Pause / Resume
                  IconButton.filledTonal(
                    onPressed: () {
                      if (state.isPaused) {
                        state.resumeRecording();
                      } else {
                        state.pauseRecording();
                      }
                    },
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: VibeTheme.cardSurface,
                    ),
                    icon: Icon(
                      state.isPaused ? Icons.play_arrow : Icons.pause,
                      color: VibeTheme.accentAmber,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Stop
                  ElevatedButton.icon(
                    onPressed: () => state.stopRecording(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    icon: const Icon(Icons.stop, size: 24),
                    label: const Text('结束并归档', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 28),

            // 5. Active Feature Status Summary Cards
            const Text(
              '数据流转管道状态',
              style: TextStyle(color: VibeTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                // Streaming Pipeline Card
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.stream,
                                size: 18,
                                color: state.streamingConfig.enabled ? VibeTheme.primaryNeon : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              const Text('实时流式推流', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.streamingConfig.enabled
                                ? state.streaming.state.displayName
                                : '已关闭',
                            style: TextStyle(
                              fontSize: 12,
                              color: state.streaming.state == StreamingState.connected
                                  ? VibeTheme.successGreen
                                  : VibeTheme.textSecondary,
                            ),
                          ),
                          if (state.streaming.state == StreamingState.connected) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${state.streaming.stats.currentBitrateKbps.toStringAsFixed(1)} kbps',
                              style: const TextStyle(fontSize: 11, color: VibeTheme.primaryNeon),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Slicing Pipeline Card
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.pie_chart,
                                size: 18,
                                color: state.slicerConfig.enabled ? VibeTheme.accentAmber : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              const Text('定时分段切片', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.slicerConfig.enabled
                                ? '每 ${state.slicerConfig.intervalMinutes} 分钟无缝切片'
                                : '已关闭',
                            style: const TextStyle(fontSize: 12, color: VibeTheme.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '目标: ${state.slicerConfig.target.displayName}',
                            style: const TextStyle(fontSize: 11, color: VibeTheme.accentAmber),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
