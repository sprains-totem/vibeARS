import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/app_state.dart';
import '../../services/local_storage_service.dart';
import '../theme.dart';

class FullPlayerBottomSheet extends StatelessWidget {
  const FullPlayerBottomSheet({super.key});

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final storage = state.storage;
    final file = storage.currentlyPlayingFile;

    if (file == null) {
      return const SizedBox.shrink();
    }

    final posMs = storage.currentPosition.inMilliseconds.toDouble();
    final durMs = storage.totalDuration.inMilliseconds.toDouble();
    final maxSlider = durMs > 0 ? durMs : 1.0;
    final currentSlider = posMs.clamp(0.0, maxSlider);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF161E2B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header with format badge & share button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: VibeTheme.primaryNeon.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: VibeTheme.primaryNeon.withOpacity(0.3)),
                ),
                child: Text(
                  file.extension.toUpperCase(),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: VibeTheme.primaryNeon),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  file.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: VibeTheme.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.share, size: 20, color: VibeTheme.textSecondary),
                tooltip: '分享此录音',
                onPressed: () {
                  Share.shareXFiles([XFile(file.path)], text: file.name);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),

          // File metadata info
          Row(
            children: [
              Text(
                '${file.formattedSize} · ${DateFormat('yyyy-MM-dd HH:mm').format(file.modifiedAt)}',
                style: const TextStyle(fontSize: 12, color: VibeTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Waveform Animation Box
          Container(
            height: 80,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: VibeTheme.cardSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(35, (index) {
                final isPlaying = storage.playerState == PlayerState.playing;
                final factor = isPlaying
                    ? ((index % 5 + 1) * 12.0 + (index % 3) * 8.0).clamp(6.0, 60.0)
                    : 6.0;
                return AnimatedContainer(
                  duration: Duration(milliseconds: 200 + (index % 5) * 50),
                  width: 3.5,
                  height: factor,
                  decoration: BoxDecoration(
                    color: isPlaying ? VibeTheme.primaryNeon : const Color(0xFF455A64),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),

          // Scrubbing Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: VibeTheme.primaryNeon,
              inactiveTrackColor: const Color(0xFF37474F),
              thumbColor: VibeTheme.primaryNeon,
            ),
            child: Slider(
              value: currentSlider,
              max: maxSlider,
              onChanged: (val) {
                storage.seek(Duration(milliseconds: val.toInt()));
              },
            ),
          ),

          // Time Labels (Elapsed / Total)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(storage.currentPosition),
                  style: const TextStyle(fontSize: 12, color: VibeTheme.textSecondary, fontFamily: 'monospace'),
                ),
                Text(
                  _formatDuration(storage.totalDuration),
                  style: const TextStyle(fontSize: 12, color: VibeTheme.textSecondary, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Playback Mode & Speed Buttons Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Play Mode Toggle
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: VibeTheme.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                icon: Icon(
                  _getPlayModeIcon(storage.playMode),
                  size: 18,
                  color: VibeTheme.primaryNeon,
                ),
                label: Text(
                  storage.playMode.displayName,
                  style: const TextStyle(fontSize: 12, color: VibeTheme.textPrimary),
                ),
                onPressed: () {
                  final nextMode = _getNextPlayMode(storage.playMode);
                  storage.setPlayMode(nextMode);
                },
              ),

              // Playback Speed Selector
              PopupMenuButton<double>(
                initialValue: storage.playbackSpeed,
                color: VibeTheme.cardSurface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: VibeTheme.cardSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF37474F)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.speed, size: 14, color: VibeTheme.accentAmber),
                      const SizedBox(width: 4),
                      Text(
                        '${storage.playbackSpeed}x',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: VibeTheme.accentAmber),
                      ),
                    ],
                  ),
                ),
                onSelected: (speed) {
                  storage.setPlaybackSpeed(speed);
                },
                itemBuilder: (ctx) => [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map((s) {
                  return PopupMenuItem(
                    value: s,
                    child: Text('${s}x', style: TextStyle(fontWeight: s == storage.playbackSpeed ? FontWeight.bold : FontWeight.normal)),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Main Controls: Previous, Rewind -10s, Play/Pause, Forward +10s, Next
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 28),
                color: VibeTheme.textPrimary,
                tooltip: '上一首',
                onPressed: () => storage.playPrevious(),
              ),
              IconButton(
                icon: const Icon(Icons.replay_10, size: 28),
                color: VibeTheme.textSecondary,
                tooltip: '快退 10 秒',
                onPressed: () => storage.skipBackward(10),
              ),
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: VibeTheme.primaryNeon,
                ),
                child: IconButton(
                  icon: Icon(
                    storage.playerState == PlayerState.playing ? Icons.pause : Icons.play_arrow,
                    size: 36,
                    color: Colors.black,
                  ),
                  onPressed: () {
                    if (storage.playerState == PlayerState.playing) {
                      storage.pausePlayer();
                    } else {
                      storage.resumePlayer();
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.forward_10, size: 28),
                color: VibeTheme.textSecondary,
                tooltip: '快进 10 秒',
                onPressed: () => storage.skipForward(10),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, size: 28),
                color: VibeTheme.textPrimary,
                tooltip: '下一首',
                onPressed: () => storage.playNext(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getPlayModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.sequential:
        return Icons.repeat;
      case PlayMode.loopSingle:
        return Icons.repeat_one;
      case PlayMode.loopAll:
        return Icons.loop;
      case PlayMode.shuffle:
        return Icons.shuffle;
    }
  }

  PlayMode _getNextPlayMode(PlayMode current) {
    final values = PlayMode.values;
    final nextIndex = (values.indexOf(current) + 1) % values.length;
    return values[nextIndex];
  }
}
