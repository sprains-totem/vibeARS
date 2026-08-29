import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/app_state.dart';
import '../../services/local_storage_service.dart';
import '../theme.dart';
import '../widgets/full_player_bottom_sheet.dart';

class LocalRecordingsScreen extends StatefulWidget {
  const LocalRecordingsScreen({super.key});

  @override
  State<LocalRecordingsScreen> createState() => _LocalRecordingsScreenState();
}

class _LocalRecordingsScreenState extends State<LocalRecordingsScreen> {
  String _selectedFormatFilter = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openFullPlayer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const FullPlayerBottomSheet(),
    );
  }

  void _showPathSelectionDialog(BuildContext context, AppState state) {
    final storage = state.storage;
    final textController = TextEditingController(text: storage.customStoragePath);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF192230),
        title: const Text('选择录音存储路径', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Android 推荐使用公共文件夹，方便在系统文件管理或第三方播放器中直接访问。',
                style: TextStyle(fontSize: 12, color: VibeTheme.textSecondary),
              ),
              const SizedBox(height: 14),

              // Presets list
              const Text('快捷预设目录：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),

              if (storage.storagePresets.containsKey('public_music'))
                _PresetPathTile(
                  title: '公共音乐目录 (推荐)',
                  subtitle: storage.storagePresets['public_music']!,
                  icon: Icons.music_note,
                  isSelected: storage.customStoragePath == storage.storagePresets['public_music'],
                  onTap: () {
                    textController.text = storage.storagePresets['public_music']!;
                  },
                ),

              if (storage.storagePresets.containsKey('public_recordings'))
                _PresetPathTile(
                  title: '公共录音目录 (Recordings)',
                  subtitle: storage.storagePresets['public_recordings']!,
                  icon: Icons.mic,
                  isSelected: storage.customStoragePath == storage.storagePresets['public_recordings'],
                  onTap: () {
                    textController.text = storage.storagePresets['public_recordings']!;
                  },
                ),

              if (storage.storagePresets.containsKey('public_download'))
                _PresetPathTile(
                  title: '公共下载目录 (Download)',
                  subtitle: storage.storagePresets['public_download']!,
                  icon: Icons.download,
                  isSelected: storage.customStoragePath == storage.storagePresets['public_download'],
                  onTap: () {
                    textController.text = storage.storagePresets['public_download']!;
                  },
                ),

              if (storage.storagePresets.containsKey('app_sandbox'))
                _PresetPathTile(
                  title: '应用专属沙盒 (私有隔离)',
                  subtitle: storage.storagePresets['app_sandbox']!,
                  icon: Icons.security,
                  isSelected: storage.customStoragePath == storage.storagePresets['app_sandbox'],
                  onTap: () {
                    textController.text = storage.storagePresets['app_sandbox']!;
                  },
                ),

              const SizedBox(height: 12),
              const Text('自定义绝对路径：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: textController,
                decoration: const InputDecoration(
                  hintText: '/storage/emulated/0/Music/vibeARS',
                  prefixIcon: Icon(Icons.folder_open),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPath = textController.text.trim();
              if (newPath.isNotEmpty) {
                final ok = await storage.setStoragePath(newPath);
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? '已更改存储路径为: $newPath' : '路径不可写，无法应用: $newPath'),
                      backgroundColor: ok ? VibeTheme.successGreen : VibeTheme.errorRed,
                    ),
                  );
                }
              }
            },
            child: const Text('确认应用'),
          ),
        ],
      ),
    ).then((_) => textController.dispose());
  }

  void _showCopyToDirectoryDialog(BuildContext context, LocalStorageService storage) {
    final textController = TextEditingController(text: '/storage/emulated/0/Download/vibeARS_Export');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF192230),
        title: Text('批量导出 (${storage.selectedCount} 项) 至目录', style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '请输入要导出的目标文件夹路径：',
              style: TextStyle(fontSize: 12, color: VibeTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                labelText: '目标导出路径',
                prefixIcon: Icon(Icons.drive_file_move_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final target = textController.text.trim();
              if (target.isNotEmpty) {
                final copied = await storage.batchCopyToDirectory(target);
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('成功导出 $copied 个文件至: $target'),
                      backgroundColor: VibeTheme.successGreen,
                    ),
                  );
                }
              }
            },
            child: const Text('开始导出'),
          ),
        ],
      ),
    ).then((_) => textController.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final storage = state.storage;

    // Filter files based on format and search query
    final filteredFiles = storage.files.where((f) {
      if (_selectedFormatFilter != 'all' && f.extension.toLowerCase() != _selectedFormatFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty && !f.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(storage.isSelectionMode ? '已选择 ${storage.selectedCount} 项' : '本地录音库与播放器'),
        actions: [
          if (storage.isSelectionMode) ...[
            TextButton(
              onPressed: () {
                if (storage.selectedCount == storage.files.length) {
                  storage.deselectAll();
                } else {
                  storage.selectAll();
                }
              },
              child: Text(
                storage.selectedCount == storage.files.length ? '取消全选' : '全选',
                style: const TextStyle(color: VibeTheme.primaryNeon, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '退出多选',
              onPressed: () => storage.setSelectionMode(false),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: '多选与批量导出',
              onPressed: () => storage.setSelectionMode(true),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新文件',
              onPressed: () => storage.refreshFiles(),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // 1. Current Storage Path Bar with Change Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xFF131A24),
            child: Row(
              children: [
                const Icon(Icons.folder_special, size: 18, color: VibeTheme.accentAmber),
                const SizedBox(width: 8),
                Expanded(
                  child: FutureBuilder<String>(
                    future: storage.getActiveStoragePath(),
                    builder: (context, snapshot) {
                      final path = snapshot.data ?? '加载中...';
                      return Text(
                        path,
                        style: const TextStyle(fontSize: 11, color: VibeTheme.textSecondary, fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.edit, size: 14, color: VibeTheme.primaryNeon),
                  label: const Text('更改路径', style: TextStyle(fontSize: 12, color: VibeTheme.primaryNeon)),
                  onPressed: () => _showPathSelectionDialog(context, state),
                ),
              ],
            ),
          ),

          // 2. Search & Format Filter Chips
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '搜索录音文件名...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                      ),
                      onChanged: (val) {
                        setState(() => _searchQuery = val.trim());
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  color: VibeTheme.cardSurface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: VibeTheme.cardSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF37474F)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.filter_list, size: 16, color: VibeTheme.primaryNeon),
                        const SizedBox(width: 4),
                        Text(
                          _selectedFormatFilter == 'all' ? '全部格式' : _selectedFormatFilter.toUpperCase(),
                          style: const TextStyle(fontSize: 12, color: VibeTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  onSelected: (fmt) => setState(() => _selectedFormatFilter = fmt),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'all', child: Text('全部格式 (All)')),
                    const PopupMenuItem(value: 'wav', child: Text('WAV (PCM)')),
                    const PopupMenuItem(value: 'm4a', child: Text('M4A (AAC)')),
                    const PopupMenuItem(value: 'mp3', child: Text('MP3')),
                    const PopupMenuItem(value: 'opus', child: Text('Opus / Ogg')),
                  ],
                ),
              ],
            ),
          ),

          // 3. Batch Action Floating Toolbar (When in Selection Mode)
          if (storage.isSelectionMode) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: VibeTheme.cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: VibeTheme.primaryNeon.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _BatchActionButton(
                    icon: Icons.share,
                    label: '批量分享',
                    color: VibeTheme.primaryNeon,
                    onTap: storage.selectedCount > 0 ? () => storage.batchShareSelected() : null,
                  ),
                  _BatchActionButton(
                    icon: Icons.folder_zip,
                    label: '打包 ZIP 导出',
                    color: VibeTheme.accentAmber,
                    onTap: storage.selectedCount > 0
                        ? () async {
                            final zipPath = await storage.batchExportZipSelected();
                            if (zipPath != null && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('ZIP 归档打包完成: ${zipPath.split('/').last}'),
                                  backgroundColor: VibeTheme.successGreen,
                                ),
                              );
                            }
                          }
                        : null,
                  ),
                  _BatchActionButton(
                    icon: Icons.drive_file_move,
                    label: '复制至目录',
                    color: Colors.blueAccent,
                    onTap: storage.selectedCount > 0 ? () => _showCopyToDirectoryDialog(context, storage) : null,
                  ),
                  _BatchActionButton(
                    icon: Icons.delete_forever,
                    label: '批量删除',
                    color: VibeTheme.errorRed,
                    onTap: storage.selectedCount > 0
                        ? () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF192230),
                                title: const Text('确认批量删除'),
                                content: Text('确定要删除选中的 ${storage.selectedCount} 个录音文件吗？'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                                  TextButton(
                                    onPressed: () {
                                      storage.batchDeleteSelected();
                                      Navigator.pop(ctx);
                                    },
                                    child: const Text('确认删除', style: TextStyle(color: VibeTheme.errorRed)),
                                  ),
                                ],
                              ),
                            );
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],

          // 4. File List
          Expanded(
            child: filteredFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.folder_open, size: 60, color: VibeTheme.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty ? '没有匹配 "$_searchQuery" 的录音' : '当前存储目录暂无录音文件',
                          style: const TextStyle(color: VibeTheme.textSecondary),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    itemCount: filteredFiles.length,
                    itemBuilder: (context, index) {
                      final file = filteredFiles[index];
                      final isCurrent = storage.currentlyPlayingPath == file.path;
                      final isSelected = storage.isSelected(file.path);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: isCurrent ? const Color(0xFF1F2B3E) : VibeTheme.cardBackground,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: isSelected
                                ? VibeTheme.primaryNeon
                                : (isCurrent ? VibeTheme.primaryNeon.withOpacity(0.5) : const Color(0xFF2C394B)),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            if (storage.isSelectionMode) {
                              storage.toggleSelect(file.path);
                            } else {
                              final ok = await storage.playFile(file.path);
                              if (!ok && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(storage.lastPlayError ?? '播放失败'),
                                    backgroundColor: VibeTheme.errorRed,
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            }
                          },
                          onLongPress: () {
                            storage.toggleSelect(file.path);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                if (storage.isSelectionMode) ...[
                                  Checkbox(
                                    value: isSelected,
                                    activeColor: VibeTheme.primaryNeon,
                                    checkColor: Colors.black,
                                    onChanged: (_) => storage.toggleSelect(file.path),
                                  ),
                                  const SizedBox(width: 4),
                                ] else ...[
                                  IconButton(
                                    icon: Icon(
                                      isCurrent && storage.playerState == PlayerState.playing
                                          ? Icons.pause_circle_filled
                                          : Icons.play_circle_fill,
                                      color: isCurrent ? VibeTheme.primaryNeon : VibeTheme.textSecondary,
                                      size: 36,
                                    ),
                                    onPressed: () async {
                                      final ok = await storage.playFile(file.path);
                                      if (!ok && mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(storage.lastPlayError ?? '播放失败'),
                                            backgroundColor: VibeTheme.errorRed,
                                            duration: const Duration(seconds: 3),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        file.name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isCurrent ? VibeTheme.primaryNeon : VibeTheme.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF37474F),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              file.extension.toUpperCase(),
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${file.formattedSize} · ${DateFormat('yyyy-MM-dd HH:mm').format(file.modifiedAt)}',
                                            style: const TextStyle(fontSize: 11, color: VibeTheme.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (!storage.isSelectionMode) ...[
                                  IconButton(
                                    icon: const Icon(Icons.share, size: 18, color: VibeTheme.textSecondary),
                                    tooltip: '分享',
                                    onPressed: () => Share.shareXFiles([XFile(file.path)], text: file.name),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: VibeTheme.textSecondary),
                                    tooltip: '删除',
                                    onPressed: () => storage.deleteFile(file.path),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // 5. Enhanced In-App Mini Player Bar (Bottom Docked)
          if (storage.currentlyPlayingPath != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF182333),
                border: Border(top: BorderSide(color: Color(0xFF2C394B), width: 1)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: VibeTheme.primaryNeon.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.audiotrack, color: VibeTheme.primaryNeon, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () => _openFullPlayer(context),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                storage.currentlyPlayingFile?.name ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              const Text('点击展开完整播放器与音质信息 >', style: TextStyle(fontSize: 10, color: VibeTheme.primaryNeon)),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.replay_10, size: 22, color: VibeTheme.textSecondary),
                        tooltip: '快退 10 秒',
                        onPressed: () => storage.skipBackward(10),
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
                          } else if (storage.playerState == PlayerState.paused ||
                              storage.playerState == PlayerState.completed) {
                            storage.resumePlayer();
                          } else {
                            storage.playFile(storage.currentlyPlayingPath!);
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.forward_10, size: 22, color: VibeTheme.textSecondary),
                        tooltip: '快进 10 秒',
                        onPressed: () => storage.skipForward(10),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: VibeTheme.textSecondary),
                        onPressed: () => storage.stopPlayer(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BatchActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _BatchActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: enabled ? color : Colors.grey),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: enabled ? VibeTheme.textPrimary : Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetPathTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetPathTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: isSelected ? const Color(0xFF1F2B3E) : VibeTheme.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? VibeTheme.primaryNeon : const Color(0xFF37474F),
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: isSelected ? VibeTheme.primaryNeon : VibeTheme.textSecondary, size: 20),
        title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 10, color: VibeTheme.textSecondary, fontFamily: 'monospace'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: VibeTheme.primaryNeon, size: 18)
            : const Icon(Icons.chevron_right, size: 16, color: VibeTheme.textSecondary),
        onTap: onTap,
      ),
    );
  }
}
