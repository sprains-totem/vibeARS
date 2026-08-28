import 'package:flutter/material.dart';
import '../theme.dart';

class WaveformVisualizer extends StatelessWidget {
  final List<double> waveform;
  final double db;
  final bool isRecording;
  final bool isPaused;

  const WaveformVisualizer({
    super.key,
    required this.waveform,
    required this.db,
    required this.isRecording,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VibeTheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRecording
              ? (isPaused ? VibeTheme.accentAmber.withOpacity(0.5) : VibeTheme.primaryNeon.withOpacity(0.5))
              : const Color(0xFF2C394B),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !isRecording
                          ? Colors.grey
                          : (isPaused ? VibeTheme.accentAmber : VibeTheme.errorRed),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    !isRecording
                        ? '就绪 (IDLE)'
                        : (isPaused ? '录音暂停 (PAUSED)' : '实时采集中 (LIVE)'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: !isRecording
                          ? Colors.grey
                          : (isPaused ? VibeTheme.accentAmber : VibeTheme.textPrimary),
                    ),
                  ),
                ],
              ),
              Text(
                '${db.toStringAsFixed(1)} dB',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: VibeTheme.primaryNeon,
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 70,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: waveform.map((amp) {
                final barHeight = isRecording && !isPaused ? (amp * 65.0).clamp(4.0, 65.0) : 4.0;
                return Container(
                  width: 3.5,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: isRecording
                        ? (isPaused
                            ? VibeTheme.accentAmber.withOpacity(0.6)
                            : (amp > 0.7 ? VibeTheme.errorRed : VibeTheme.primaryNeon))
                        : const Color(0xFF455A64),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
