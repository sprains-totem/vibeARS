import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/models/slicer_config.dart';
import '../../providers/app_state.dart';
import '../theme.dart';

class SlicerScreen extends StatelessWidget {
  const SlicerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final slicerConfig = state.slicerConfig;
    final uploadQueue = state.uploadQueue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('定时分段切片与上传管理'),
        actions: [
          if (uploadQueue.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空上传历史记录（不影响本地录音文件）',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF192230),
                    title: const Text('清空切片上传历史'),
                    content: const Text('将从列表与历史记录中移除全部切片条目，但不会删除本地录音文件。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                      TextButton(
                        onPressed: () {
                          uploadQueue.clearHistory();
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
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Slicer Configuration Card
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
                        '定时无缝分段切片',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Switch(
                        value: slicerConfig.enabled,
                        activeColor: VibeTheme.primaryNeon,
                        onChanged: (val) {
                          state.updateSlicerConfig(slicerConfig.copyWith(enabled: val));
                        },
                      ),
                    ],
                  ),
                  const Text(
                    '采集过程中按固定时长无缝滚转生成独立音频文件，零爆音、零丢帧。',
                    style: TextStyle(fontSize: 12, color: VibeTheme.textSecondary),
                  ),
                  const Divider(height: 24, color: Color(0xFF2C394B)),

                  // Interval Selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('切片间隔时长：', style: TextStyle(fontSize: 14)),
                      Text(
                        '${slicerConfig.intervalMinutes} 分钟/段',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: VibeTheme.primaryNeon,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    children: [1, 3, 5, 10, 15, 30, 60].map((mins) {
                      final isSelected = slicerConfig.intervalMinutes == mins;
                      return ChoiceChip(
                        label: Text('$mins 分钟'),
                        selected: isSelected,
                        selectedColor: VibeTheme.primaryNeon,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.black : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            state.updateSlicerConfig(slicerConfig.copyWith(intervalMinutes: mins));
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Upload Target Dropdown
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('自动上传目标：', style: TextStyle(fontSize: 14)),
                      DropdownButton<SlicerUploadTarget>(
                        value: slicerConfig.target,
                        dropdownColor: VibeTheme.cardSurface,
                        underline: const SizedBox(),
                        items: SlicerUploadTarget.values.map((target) {
                          return DropdownMenuItem(
                            value: target,
                            child: Text(target.displayName, style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (target) {
                          if (target != null) {
                            state.updateSlicerConfig(slicerConfig.copyWith(target: target));
                          }
                        },
                      ),
                    ],
                  ),

                  // Keep local copy switch
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('上传后保留本地副本', style: TextStyle(fontSize: 14)),
                      Switch(
                        value: slicerConfig.keepLocalAfterUpload,
                        activeColor: VibeTheme.primaryNeon,
                        onChanged: (val) {
                          state.updateSlicerConfig(slicerConfig.copyWith(keepLocalAfterUpload: val));
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Upload Queue Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '切片与上传任务队列 (${uploadQueue.items.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              if (uploadQueue.isProcessing)
                const Row(
                  children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 6),
                    Text('传输中...', style: TextStyle(fontSize: 12, color: VibeTheme.primaryNeon)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),

          // 3. Upload Queue Items List
          if (uploadQueue.items.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: const Column(
                children: [
                  Icon(Icons.cloud_upload_outlined, size: 48, color: VibeTheme.textSecondary),
                  SizedBox(height: 12),
                  Text('暂无切片生成，开始录音后将按周期生成切片', style: TextStyle(color: VibeTheme.textSecondary, fontSize: 13)),
                ],
              ),
            )
          else
            ...uploadQueue.items.map((item) {
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '#${item.sequence} · ${item.fileName}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            DateFormat('HH:mm:ss').format(item.createdAt),
                            style: const TextStyle(fontSize: 11, color: VibeTheme.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '时长: ${(item.durationMs / 1000).toStringAsFixed(1)}s · 大小: ${(item.fileSizeBytes / 1024).toStringAsFixed(1)} KB',
                        style: const TextStyle(fontSize: 11, color: VibeTheme.textSecondary),
                      ),
                      const SizedBox(height: 8),

                      // Status indicators
                      Row(
                        children: [
                          if (slicerConfig.target == SlicerUploadTarget.webdav || slicerConfig.target == SlicerUploadTarget.both)
                            _StatusBadge(label: 'WebDAV', status: item.webdavStatus),
                          if (slicerConfig.target == SlicerUploadTarget.both)
                            const SizedBox(width: 8),
                          if (slicerConfig.target == SlicerUploadTarget.s3 || slicerConfig.target == SlicerUploadTarget.both)
                            _StatusBadge(label: 'S3', status: item.s3Status),
                          const Spacer(),
                          if (item.webdavStatus == SliceUploadStatus.failed || item.s3Status == SliceUploadStatus.failed)
                            IconButton(
                              icon: const Icon(Icons.refresh, color: VibeTheme.errorRed, size: 20),
                              tooltip: '重试上传',
                              onPressed: () => uploadQueue.retrySlice(item.id),
                            ),
                          // Delete this slice entry (optionally removing the local file).
                          PopupMenuButton<String>(
                            color: VibeTheme.cardSurface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            icon: const Icon(Icons.more_vert, size: 18, color: VibeTheme.textSecondary),
                            onSelected: (action) {
                              if (action == 'delete_entry') {
                                uploadQueue.removeSlice(item.id, deleteLocalFile: false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('已从切片队列移除'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              } else if (action == 'delete_file') {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: const Color(0xFF192230),
                                    title: const Text('删除切片与本地文件'),
                                    content: const Text('将从队列移除该切片，并同时删除对应的本地录音文件（不可恢复）。'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('取消'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          uploadQueue.removeSlice(item.id, deleteLocalFile: true);
                                          Navigator.pop(ctx);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('切片已删除（含本地文件）'),
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        },
                                        child: const Text('确认删除', style: TextStyle(color: VibeTheme.errorRed)),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'delete_entry',
                                child: Text('从队列移除（保留文件）'),
                              ),
                              const PopupMenuItem(
                                value: 'delete_file',
                                child: Text('删除切片并删除本地文件'),
                              ),
                            ],
                          ),
                        ],
                      ),

                      if (item.uploadProgress > 0 && item.uploadProgress < 1.0) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: item.uploadProgress,
                          backgroundColor: const Color(0xFF2C394B),
                          color: VibeTheme.primaryNeon,
                        ),
                      ],

                      if (item.errorMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.errorMessage!,
                          style: const TextStyle(fontSize: 11, color: VibeTheme.errorRed),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final SliceUploadStatus status;

  const _StatusBadge({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    switch (status) {
      case SliceUploadStatus.idle:
        color = Colors.grey;
        icon = Icons.hourglass_empty;
        break;
      case SliceUploadStatus.pending:
        color = VibeTheme.accentAmber;
        icon = Icons.access_time;
        break;
      case SliceUploadStatus.uploading:
        color = VibeTheme.primaryNeon;
        icon = Icons.arrow_upward;
        break;
      case SliceUploadStatus.success:
        color = VibeTheme.successGreen;
        icon = Icons.check_circle_outline;
        break;
      case SliceUploadStatus.failed:
        color = VibeTheme.errorRed;
        icon = Icons.error_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: ${status.displayName}',
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
