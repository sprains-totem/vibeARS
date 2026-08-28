import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../services/local_storage_service.dart';
import '../theme.dart';

class LocalRecordingsScreen extends StatelessWidget {
  const LocalRecordingsScreen({super.key});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final storage = state.storage;

    return Scaffold(
      appBar: AppBar(
        title: const Text('本地录音库与播放器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新列表',
            onPressed: () => storage.refreshFiles(),
          ),
          if (storage.files.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空所有本地录音',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清空本地录音'),
                    content: const Text('确定要删除全部本地录音文件吗？此操作无法撤销。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                      TextButton(
                        onPressed: () {
                          storage.deleteAllFiles();
                          Navigator.pop(ctx);
                        },
                        child: const Text('确认清空', style: TextStyle(color: VibeTheme.errorRed)),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // 1. In-App Audio Mini Player Card
          if (storage.currentlyPlayingPath != null) ...[
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: VibeTheme.cardSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: VibeTheme.primaryNeon, width: 1.5),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.audiotrack, color: VibeTheme.primaryNeon, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          storage.currentlyPlayingPath!.split('/').last,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          storage.playerState == PlayerState.playing ? Icons.pause_circle : Icons.play_circle,
                          color: VibeTheme.primaryNeon,
                          size: 32,
                        ),
                        onPressed: () {
                          if (storage.playerState == PlayerState.playing) {
                            storage.pausePlayer();
                          } else {
                            storage.playFile(storage.currentlyPlayingPath!);
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: VibeTheme.textSecondary, size: 20),
                        onPressed: () => storage.stopPlayer(),
                      ),
                    ],
                  ),
                  Slider(
                    value: storage.currentPosition.inMilliseconds.toDouble().clamp(
                          0.0,
                          storage.totalDuration.inMilliseconds.toDouble() > 0
                              ? storage.totalDuration.inMilliseconds.toDouble()
                              : 1.0,
                        ),
                    max: storage.totalDuration.inMilliseconds.toDouble() > 0
                        ? storage.totalDuration.inMilliseconds.toDouble()
                        : 1.0,
                    activeColor: VibeTheme.primaryNeon,
                    inactiveColor: const Color(0xFF37474F),
                    onChanged: (val) {
                      storage.seek(Duration(milliseconds: val.toInt()));
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(storage.currentPosition),
                        style: const TextStyle(fontSize: 11, color: VibeTheme.textSecondary, fontFamily: 'monospace'),
                      ),
                      Text(
                        _formatDuration(storage.totalDuration),
                        style: const TextStyle(fontSize: 11, color: VibeTheme.textSecondary, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // 2. Storage Overview Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '文件总数: ${storage.files.length} 个',
                  style: const TextStyle(fontSize: 13, color: VibeTheme.textSecondary),
                ),
                Text(
                  '已用空间: ${(storage.totalDiskUsageBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                  style: const TextStyle(fontSize: 13, color: VibeTheme.primaryNeon, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2C394B)),

          // 3. File List
          Expanded(
            child: storage.files.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open, size: 64, color: VibeTheme.textSecondary),
                        SizedBox(height: 12),
                        Text('暂无本地录音文件', style: TextStyle(color: VibeTheme.textSecondary)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: storage.files.length,
                    itemBuilder: (context, index) {
                      final file = storage.files[index];
                      final isCurrent = storage.currentlyPlayingPath == file.path;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: isCurrent ? VibeTheme.cardSurface : VibeTheme.cardBackground,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isCurrent ? VibeTheme.primaryNeon : const Color(0xFF2C394B),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          leading: IconButton(
                            icon: Icon(
                              isCurrent && storage.playerState == PlayerState.playing
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_fill,
                              color: isCurrent ? VibeTheme.primaryNeon : VibeTheme.textSecondary,
                              size: 34,
                            ),
                            onPressed: () => storage.playFile(file.path),
                          ),
                          title: Text(
                            file.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isCurrent ? VibeTheme.primaryNeon : VibeTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${file.formattedSize} · ${DateFormat('yyyy-MM-dd HH:mm').format(file.modifiedAt)}',
                            style: const TextStyle(fontSize: 11, color: VibeTheme.textSecondary),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: VibeTheme.textSecondary),
                            onPressed: () => storage.deleteFile(file.path),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
