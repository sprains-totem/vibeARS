import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/audio_config.dart';
import '../../core/models/storage_config.dart';
import '../../providers/app_state.dart';
import '../../services/audio_engine_service.dart';
import '../../services/storage/s3_storage_adapter.dart';
import '../../services/storage/webdav_storage_adapter.dart';
import '../theme.dart';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  // WebDAV Controllers
  late TextEditingController _webdavUrlController;
  late TextEditingController _webdavUsernameController;
  late TextEditingController _webdavPasswordController;
  late TextEditingController _webdavDirController;

  // S3 Controllers
  late TextEditingController _s3EndpointController;
  late TextEditingController _s3RegionController;
  late TextEditingController _s3BucketController;
  late TextEditingController _s3AccessKeyController;
  late TextEditingController _s3SecretKeyController;
  late TextEditingController _s3PrefixController;

  // Local Path Controller
  late TextEditingController _localPathController;

  bool _isTestingWebDav = false;
  bool _isTestingS3 = false;
  bool _isManageStorageGranted = true;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    final wd = state.webdavConfig;
    final s3 = state.s3Config;
    final storage = state.storage;

    _webdavUrlController = TextEditingController(text: wd.serverUrl);
    _webdavUsernameController = TextEditingController(text: wd.username);
    _webdavPasswordController = TextEditingController(text: wd.password);
    _webdavDirController = TextEditingController(text: wd.remoteDir);

    _s3EndpointController = TextEditingController(text: s3.endpoint);
    _s3RegionController = TextEditingController(text: s3.region);
    _s3BucketController = TextEditingController(text: s3.bucketName);
    _s3AccessKeyController = TextEditingController(text: s3.accessKey);
    _s3SecretKeyController = TextEditingController(text: s3.secretKey);
    _s3PrefixController = TextEditingController(text: s3.remotePrefix);

    _localPathController = TextEditingController(text: storage.customStoragePath);

    _checkStoragePermission();
  }

  Future<void> _checkStoragePermission() async {
    final granted = await AudioEngineService.instance.isManageStorageGranted();
    if (mounted) {
      setState(() => _isManageStorageGranted = granted);
    }
  }

  @override
  void dispose() {
    _webdavUrlController.dispose();
    _webdavUsernameController.dispose();
    _webdavPasswordController.dispose();
    _webdavDirController.dispose();
    _s3EndpointController.dispose();
    _s3RegionController.dispose();
    _s3BucketController.dispose();
    _s3AccessKeyController.dispose();
    _s3SecretKeyController.dispose();
    _s3PrefixController.dispose();
    _localPathController.dispose();
    super.dispose();
  }

  Future<void> _saveWebDav(AppState state) async {
    final updated = state.webdavConfig.copyWith(
      serverUrl: _webdavUrlController.text.trim(),
      username: _webdavUsernameController.text.trim(),
      password: _webdavPasswordController.text.trim(),
      remoteDir: _webdavDirController.text.trim(),
    );
    await state.updateWebDavConfig(updated);
  }

  Future<void> _saveS3(AppState state) async {
    final updated = state.s3Config.copyWith(
      endpoint: _s3EndpointController.text.trim(),
      region: _s3RegionController.text.trim(),
      bucketName: _s3BucketController.text.trim(),
      accessKey: _s3AccessKeyController.text.trim(),
      secretKey: _s3SecretKeyController.text.trim(),
      remotePrefix: _s3PrefixController.text.trim(),
    );
    await state.updateS3Config(updated);
  }

  Future<void> _testWebDav(AppState state) async {
    setState(() => _isTestingWebDav = true);
    await _saveWebDav(state);
    final adapter = WebDavStorageAdapter(state.webdavConfig);
    final ok = await adapter.testConnection();
    setState(() => _isTestingWebDav = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'WebDAV 连接测试成功！' : 'WebDAV 连接失败，请检查服务器地址与账号密码'),
          backgroundColor: ok ? VibeTheme.successGreen : VibeTheme.errorRed,
        ),
      );
    }
  }

  Future<void> _testS3(AppState state) async {
    setState(() => _isTestingS3 = true);
    await _saveS3(state);
    final adapter = S3StorageAdapter(state.s3Config);
    final ok = await adapter.testConnection();
    setState(() => _isTestingS3 = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'S3 对象存储连接测试成功！' : 'S3 连接失败，请检查 Endpoint、Key 及 Bucket'),
          backgroundColor: ok ? VibeTheme.successGreen : VibeTheme.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final audioConfig = state.audioConfig;
    final storage = state.storage;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('存储路径与参数配置'),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: VibeTheme.primaryNeon,
            labelColor: VibeTheme.primaryNeon,
            unselectedLabelColor: VibeTheme.textSecondary,
            tabs: [
              Tab(text: '本地路径与权限'),
              Tab(text: '录音参数'),
              Tab(text: 'WebDAV 网盘'),
              Tab(text: 'S3 对象存储'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // 1. Local Storage Path & Permissions Tab
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '本地录音存储路径 (Storage Path)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Android 优先默认存储在公共音乐目录（Music），录音完成后系统音乐 App 和文件管理器均可即时读取。',
                          style: TextStyle(fontSize: 12, color: VibeTheme.textSecondary),
                        ),
                        const Divider(height: 24, color: Color(0xFF2C394B)),

                        // Active Path Info
                        const Text('当前活跃存储路径：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        FutureBuilder<String>(
                          future: storage.getActiveStoragePath(),
                          builder: (context, snapshot) {
                            final path = snapshot.data ?? '读取中...';
                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: VibeTheme.cardSurface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: VibeTheme.primaryNeon.withOpacity(0.4)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.folder, size: 20, color: VibeTheme.primaryNeon),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      path,
                                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: VibeTheme.textPrimary),
                                      maxLines: 2,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // Storage Presets
                        const Text('快捷预设路径切换：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),

                        if (storage.storagePresets.containsKey('public_music'))
                          _PresetOptionButton(
                            title: '公共音乐目录 (Music/vibeARS - 推荐)',
                            subtitle: storage.storagePresets['public_music']!,
                            icon: Icons.music_note,
                            isSelected: storage.customStoragePath == storage.storagePresets['public_music'] ||
                                (storage.customStoragePath.isEmpty && Platform.isAndroid),
                            onTap: () {
                              _localPathController.text = storage.storagePresets['public_music']!;
                              storage.setStoragePath(storage.storagePresets['public_music']!);
                            },
                          ),

                        if (storage.storagePresets.containsKey('public_recordings'))
                          _PresetOptionButton(
                            title: '公共录音目录 (Recordings/vibeARS)',
                            subtitle: storage.storagePresets['public_recordings']!,
                            icon: Icons.mic,
                            isSelected: storage.customStoragePath == storage.storagePresets['public_recordings'],
                            onTap: () {
                              _localPathController.text = storage.storagePresets['public_recordings']!;
                              storage.setStoragePath(storage.storagePresets['public_recordings']!);
                            },
                          ),

                        if (storage.storagePresets.containsKey('public_download'))
                          _PresetOptionButton(
                            title: '公共下载目录 (Download/vibeARS)',
                            subtitle: storage.storagePresets['public_download']!,
                            icon: Icons.download,
                            isSelected: storage.customStoragePath == storage.storagePresets['public_download'],
                            onTap: () {
                              _localPathController.text = storage.storagePresets['public_download']!;
                              storage.setStoragePath(storage.storagePresets['public_download']!);
                            },
                          ),

                        if (storage.storagePresets.containsKey('app_sandbox'))
                          _PresetOptionButton(
                            title: '应用沙盒目录 (App Sandbox - 私有保护)',
                            subtitle: storage.storagePresets['app_sandbox']!,
                            icon: Icons.security,
                            isSelected: storage.customStoragePath == storage.storagePresets['app_sandbox'],
                            onTap: () {
                              _localPathController.text = storage.storagePresets['app_sandbox']!;
                              storage.setStoragePath(storage.storagePresets['app_sandbox']!);
                            },
                          ),

                        const SizedBox(height: 16),

                        // Custom Path Input
                        const Text('自由指定自定义路径：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _localPathController,
                          decoration: const InputDecoration(
                            labelText: '自定义绝对路径',
                            hintText: '/storage/emulated/0/Music/MyRecordings',
                            prefixIcon: Icon(Icons.edit_location_alt),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final custom = _localPathController.text.trim();
                            if (custom.isNotEmpty) {
                              final ok = await storage.setStoragePath(custom);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok ? '已保存并切换至: $custom' : '路径不可写，未能应用: $custom',
                                    ),
                                    backgroundColor: ok ? VibeTheme.successGreen : VibeTheme.errorRed,
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('应用自定义路径'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Android Permissions Card
                if (Platform.isAndroid) ...[
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
                                '所有文件读写管理权限',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _isManageStorageGranted
                                      ? VibeTheme.successGreen.withOpacity(0.2)
                                      : VibeTheme.errorRed.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _isManageStorageGranted ? '已授权' : '未完全授权',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _isManageStorageGranted ? VibeTheme.successGreen : VibeTheme.errorRed,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Android 11+ 系统若需要将录音存放到非默认公共目录或读取 SD 卡，需授予“所有文件访问权限”。',
                            style: TextStyle(fontSize: 12, color: VibeTheme.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await AudioEngineService.instance.requestManageStoragePermission();
                              await _checkStoragePermission();
                            },
                            icon: const Icon(Icons.admin_panel_settings),
                            label: const Text('打开系统设置授权'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // 2. Audio Quality & Parameters Tab
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '常用录音格式与编码选择',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: VibeTheme.accentAmber.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: VibeTheme.accentAmber.withOpacity(0.4)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, size: 16, color: VibeTheme.accentAmber),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '当前原生采集引擎输出标准 WAV (PCM 无损)，录音后可通过“录音库”内的一键分享 / ZIP 打包随时转换导出为其他格式。',
                                  style: TextStyle(fontSize: 11, color: VibeTheme.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: AudioFormatType.values.map((fmt) {
                            final isSelected = audioConfig.format == fmt;
                            return ChoiceChip(
                              label: Text(fmt.displayName),
                              selected: isSelected,
                              selectedColor: VibeTheme.primaryNeon,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.black : Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  state.updateAudioConfig(audioConfig.copyWith(format: fmt));
                                }
                              },
                            );
                          }).toList(),
                        ),
                        const Divider(height: 24, color: Color(0xFF2C394B)),

                        // Sample Rate
                        const Text('采样率 (Sample Rate)：', style: TextStyle(fontSize: 14)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [16000, 44100, 48000].map((sr) {
                            final isSelected = audioConfig.sampleRate == sr;
                            return ChoiceChip(
                              label: Text('${sr / 1000} kHz'),
                              selected: isSelected,
                              selectedColor: VibeTheme.primaryNeon,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.black : Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  state.updateAudioConfig(audioConfig.copyWith(sampleRate: sr));
                                }
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        // Channel Mode
                        const Text('声道模式 (Channel Mode)：', style: TextStyle(fontSize: 14)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ChoiceChip(
                              label: const Text('单声道 (Mono - 1ch)'),
                              selected: audioConfig.channelCount == 1,
                              selectedColor: VibeTheme.primaryNeon,
                              labelStyle: TextStyle(
                                color: audioConfig.channelCount == 1 ? Colors.black : Colors.white,
                                fontWeight: audioConfig.channelCount == 1 ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (s) => state.updateAudioConfig(audioConfig.copyWith(channelCount: 1)),
                            ),
                            const SizedBox(width: 10),
                            ChoiceChip(
                              label: const Text('立体声 (Stereo - 2ch)'),
                              selected: audioConfig.channelCount == 2,
                              selectedColor: VibeTheme.primaryNeon,
                              labelStyle: TextStyle(
                                color: audioConfig.channelCount == 2 ? Colors.black : Colors.white,
                                fontWeight: audioConfig.channelCount == 2 ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (s) => state.updateAudioConfig(audioConfig.copyWith(channelCount: 2)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Bitrate Selector
                        const Text('采样位深与码率 (Bitrate)：', style: TextStyle(fontSize: 14)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [64000, 128000, 192000, 256000, 320000].map((br) {
                            final isSelected = audioConfig.bitRate == br;
                            return ChoiceChip(
                              label: Text('${br ~/ 1000} kbps'),
                              selected: isSelected,
                              selectedColor: VibeTheme.primaryNeon,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.black : Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  state.updateAudioConfig(audioConfig.copyWith(bitRate: br));
                                }
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'WAV 为无损 PCM 编码，实际码率 = 采样率 × 声道数 × 16bit（如 48kHz 双声道约 1536 kbps）；码率选项预留给后续有损编码（AAC/MP3）使用。',
                          style: TextStyle(fontSize: 11, color: VibeTheme.textSecondary),
                        ),
                        const Divider(height: 24, color: Color(0xFF2C394B)),

                        // Audio Enhancement Switches
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('智能降噪 (Noise Suppression)'),
                            Switch(
                              value: audioConfig.enableNs,
                              activeColor: VibeTheme.primaryNeon,
                              onChanged: (val) => state.updateAudioConfig(audioConfig.copyWith(enableNs: val)),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('自动增益控制 (AGC)'),
                            Switch(
                              value: audioConfig.enableAgc,
                              activeColor: VibeTheme.primaryNeon,
                              onChanged: (val) => state.updateAudioConfig(audioConfig.copyWith(enableAgc: val)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '降噪 (NS) 与自动增益 (AGC) 开关为系统级音频前处理预留接口，将在后续原生音频引擎版本中生效。',
                          style: TextStyle(fontSize: 11, color: VibeTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // 3. WebDAV Config Tab
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'WebDAV 远程同步配置',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '支持 坚果云、Nextcloud、ownCloud、群晖 WebDAV、Alist 等私有云存储。',
                          style: TextStyle(fontSize: 12, color: VibeTheme.textSecondary),
                        ),
                        const Divider(height: 24, color: Color(0xFF2C394B)),

                        TextField(
                          controller: _webdavUrlController,
                          decoration: const InputDecoration(
                            labelText: '服务器 URL',
                            hintText: 'https://dav.jianguoyun.com/dav/',
                            prefixIcon: Icon(Icons.link),
                          ),
                          onChanged: (_) => _saveWebDav(state),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: _webdavUsernameController,
                          decoration: const InputDecoration(
                            labelText: '用户名 / 邮箱',
                            prefixIcon: Icon(Icons.person),
                          ),
                          onChanged: (_) => _saveWebDav(state),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: _webdavPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: '应用密码 / Token',
                            prefixIcon: Icon(Icons.lock),
                          ),
                          onChanged: (_) => _saveWebDav(state),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: _webdavDirController,
                          decoration: const InputDecoration(
                            labelText: '远程保存目录',
                            hintText: '/vibeARS/recordings',
                            prefixIcon: Icon(Icons.folder),
                          ),
                          onChanged: (_) => _saveWebDav(state),
                        ),
                        const SizedBox(height: 16),

                        ElevatedButton.icon(
                          onPressed: _isTestingWebDav ? null : () => _testWebDav(state),
                          icon: _isTestingWebDav
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.network_check),
                          label: const Text('测试连接并保存'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // 4. S3 Config Tab
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'S3 / S3 兼容对象存储配置',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '支持 Amazon S3、MinIO、Cloudflare R2、阿里云 OSS、腾讯云 COS、Backblaze B2 等。',
                          style: TextStyle(fontSize: 12, color: VibeTheme.textSecondary),
                        ),
                        const Divider(height: 24, color: Color(0xFF2C394B)),

                        TextField(
                          controller: _s3EndpointController,
                          decoration: const InputDecoration(
                            labelText: 'Endpoint (域名)',
                            hintText: 's3.amazonaws.com 或 play.min.io',
                            prefixIcon: Icon(Icons.cloud),
                          ),
                          onChanged: (_) => _saveS3(state),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _s3RegionController,
                                decoration: const InputDecoration(
                                  labelText: 'Region (区域)',
                                  hintText: 'us-east-1 / auto',
                                ),
                                onChanged: (_) => _saveS3(state),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _s3BucketController,
                                decoration: const InputDecoration(
                                  labelText: 'Bucket (存储桶)',
                                  hintText: 'my-audio-bucket',
                                ),
                                onChanged: (_) => _saveS3(state),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: _s3AccessKeyController,
                          decoration: const InputDecoration(
                            labelText: 'Access Key ID',
                            prefixIcon: Icon(Icons.key),
                          ),
                          onChanged: (_) => _saveS3(state),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: _s3SecretKeyController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Secret Access Key',
                            prefixIcon: Icon(Icons.vpn_key),
                          ),
                          onChanged: (_) => _saveS3(state),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: _s3PrefixController,
                          decoration: const InputDecoration(
                            labelText: '对象 Key 前缀',
                            hintText: 'recordings/',
                            prefixIcon: Icon(Icons.folder_open),
                          ),
                          onChanged: (_) => _saveS3(state),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('使用 Path-Style 寻址 (MinIO必选)'),
                            Switch(
                              value: state.s3Config.usePathStyle,
                              activeColor: VibeTheme.primaryNeon,
                              onChanged: (val) {
                                state.updateS3Config(state.s3Config.copyWith(usePathStyle: val));
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        ElevatedButton.icon(
                          onPressed: _isTestingS3 ? null : () => _testS3(state),
                          icon: _isTestingS3
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.network_check),
                          label: const Text('测试 S3 连通性并保存'),
                        ),
                      ],
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

class _PresetOptionButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetOptionButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected ? const Color(0xFF1E2D42) : VibeTheme.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? VibeTheme.primaryNeon : const Color(0xFF37474F),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: isSelected ? VibeTheme.primaryNeon : VibeTheme.textSecondary),
        title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: VibeTheme.textSecondary, fontFamily: 'monospace'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: VibeTheme.primaryNeon, size: 20)
            : const Icon(Icons.circle_outlined, size: 20, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
