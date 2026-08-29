import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../services/log_collector.dart';
import '../theme.dart';

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  String _fmt(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final logs = LogCollector.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断日志 (一键导出)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空日志',
            onPressed: () => logs.clear(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Export banner
          Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: VibeTheme.cardSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: VibeTheme.primaryNeon.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bug_report, color: VibeTheme.primaryNeon, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '遇到蓝牙/录音异常时，先操作复现（连接耳机→开始录音），然后一键导出日志发送给开发者即可，无需连接电脑。',
                        style: TextStyle(fontSize: 12, color: VibeTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: VibeTheme.primaryNeon,
                          side: const BorderSide(color: VibeTheme.primaryNeon),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          final path = await logs.shareLogs();
                          if (path == null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('日志导出失败，请重试'),
                                backgroundColor: VibeTheme.errorRed,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.share),
                        label: const Text('一键导出并分享日志'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: '复制到剪贴板',
                      style: IconButton.styleFrom(
                        backgroundColor: VibeTheme.cardSurface,
                        side: const BorderSide(color: Color(0xFF37474F)),
                      ),
                      icon: const Icon(Icons.copy, color: VibeTheme.textSecondary, size: 20),
                      onPressed: () async {
                        final buf = StringBuffer();
                        for (final e in logs.entries) {
                          buf.writeln(e.line);
                        }
                        await Clipboard.setData(ClipboardData(text: buf.toString()));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('日志已复制到剪贴板'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '共 ${logs.entries.length} 条记录${logs.droppedInMemory > 0 ? '（已丢弃 ${logs.droppedInMemory} 条最早的）' : ''} · 文件: ${logs.logFilePath ?? "初始化中..."}',
                  style: const TextStyle(fontSize: 10, color: VibeTheme.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2C394B)),

          // Log list
          Expanded(
            child: logs.entries.isEmpty
                ? const Center(
                    child: Text('暂无日志', style: TextStyle(color: VibeTheme.textSecondary)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: logs.entries.length,
                    itemBuilder: (context, index) {
                      final e = logs.entries[index];
                      final isError = e.tag.contains('Error') ||
                          e.tag == 'AudioPipeline' ||
                          e.message.contains('failed') ||
                          e.message.contains('失败') ||
                          e.message.contains('error');
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 74,
                              child: Text(
                                _fmt(e.time),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: VibeTheme.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isError
                                    ? VibeTheme.errorRed.withOpacity(0.15)
                                    : VibeTheme.primaryNeon.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                e.tag,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isError ? VibeTheme.errorRed : VibeTheme.primaryNeon,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                e.message,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: isError ? VibeTheme.errorRed : VibeTheme.textPrimary,
                                ),
                              ),
                            ),
                          ],
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
