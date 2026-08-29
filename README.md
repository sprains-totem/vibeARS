# vibeARS (Audio Recording, Streaming & Multi-Storage Slicing Engine)

[![vibeARS Build & Release CI/CD](https://github.com/sprains-totem/vibeARS/actions/workflows/build-and-release.yml/badge.svg)](https://github.com/sprains-totem/vibeARS/actions/workflows/build-and-release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-green.svg)]()

**vibeARS** 是一款面向移动端（Android & iOS）的企业级高质量**不间断录音、实时流式传输与远程多云分段切片存储系统**。

---

## 🌟 核心功能矩阵

### 1. 🎙️ 硬件探测与自由路由 (Upstream Microphones & Capabilities)
- **全面设备探测**：支持内置麦克风、蓝牙耳机 (Bluetooth SCO/HFP/A2DP)、USB 声卡/专业录音接口、有线耳机麦克风与线路输入。
- **能力参数透视**：实时探测各硬件麦克风所支持的采样率（16kHz, 44.1kHz, 48kHz）、声道数（单声道/双声道）、编码格式及指向性拾音模式（全向/心形/立体声）。
- **动态无缝切换**：在录音过程中或就绪时自由切换输入源，支持蓝牙 SCO 声道自动激活与管理。

### 2. ⚡ 多路分发架构 (1-In-3-Out Audio Pipelines)
- **Pipeline 1：实时流式传输 (Live Streaming)**
  - 采用低延迟高品质通话/直播级流式方案。
  - 支持 **WebSocket (AAC/ADTS 压缩帧)** 与 **WebSocket (原始 PCM 流)** 两种真实可用协议，编码在设备端完成（Android MediaCodec / iOS AVAudioConverter）。
  - 支持鉴权 Token、自定义流 ID，内置断网自动重连与端到端延迟、码率遥测监控。
- **Pipeline 2：无缝分段切片与云端归档 (Segmented Slicer)**
  - 自由设定切片周期（支持 **5 分钟**、1 分钟、10 分钟、30 分钟等）。
  - **样本精确度无缝滚转（Sample-Accurate Rollover）**：在底层 PCM 持续采集中自动分段，实现切口处**零丢帧、零爆音**。
  - **无限循环录制（Loop Recording，对标行车记录仪/监控摄像头）**：设置存储配额（256MB-5GB 或不限制），达到上限自动覆盖最旧的**未锁定**片段；关键片段可一键**锁定保护**，永不被循环覆盖删除。
  - **自动多远程存储同步**：
    - **WebDAV 网盘**：支持坚果云、Nextcloud、ownCloud、群晖 WebDAV、Alist 等。
    - **S3 / 对象存储**：完整实现 AWS SigV4 认证，兼容 Amazon S3、MinIO、Cloudflare R2、阿里云 OSS、腾讯云 COS、Backblaze B2 等。
  - 后台离线队列、指数退避失败重试、上传进度实时反馈与本地缓存自动清理。
### 3. 💾 本地存储、公共文件夹优先与自由路径选择
- **Android 公共文件夹优先**：默认优先采用系统公共音乐目录（`/storage/emulated/0/Music/vibeARS`），系统文件管理器与第三方播放器即时可见，避免 App 卸载丢失录音。
- **自由路径切换与预设**：支持一键切换至公共下载（Download）、公共录音（Recordings）、公共文档（Documents）或私有沙盒，并支持自由输入任意自定义存储绝对路径；路径不可写时会明确提示并保持原路径。
- **原生多格式录制**：支持 **WAV (PCM 无损)** 与 **AAC/M4A 有损压缩** 两种原生录制格式（Android 由 MediaCodec+MediaMuxer 编码，iOS 由 AVAudioFile 编码），选择 AAC 时码率设置（64k-320kbps）真实作用于编码器；MP3/Opus 需集成第三方编码库，当前可通过录音库的分享/ZIP/目录复制导出转换。
- **Android 11+ 全文件管理权限**：内置 `MANAGE_EXTERNAL_STORAGE` 授权检测与引导，支持向 SD 卡或任意受限目录读写。

### 4. 🎵 全功能高级播放器与批量导出系统 (Audio Player & Batch Export)
- **高级播放器功能**：
  - **多档倍速播放**：支持 0.5x、0.75x、1.0x、1.25x、1.5x、1.75x、2.0x 无级/快捷变速。
  - **快进 / 快退**：支持 +/-10 秒精准快进与快退跳转。
  - **多样播放循环模式**：支持顺序播放、单曲循环、列表循环、随机播放。
  - **高精度拖拽进度条**与动态声波频谱动画。
  - **沉浸式播放器底部弹窗**：支持查看文件格式、码率、采样率与修改时间。
- **多选与批量导出机制**：
  - **多选管理**：支持一键全选、反选、多选。
  - **系统级批量分享**：调用系统 Share Sheet 批量分享音频文件至微信、邮件、网盘、AirDrop、蓝牙等。
  - **一键打包 ZIP 归档**：批量将选中录音无损压缩为 `.zip` 文件并导出。
  - **批量复制到指定目录**：一键将多个录音文件拷贝导出至指定的目标外部文件夹。
  - **批量删除与云端同步**。

### 5. 🛡️ 后台深度保活机制 (Uninterrupted Recording)
- **Android 端**：
  - 运行前台服务 `ForegroundService` 并声明 `FOREGROUND_SERVICE_MICROPHONE` (Android 14 适配)。
  - 持有 `PARTIAL_WAKE_LOCK` 阻止 CPU 深度休眠。
  - 注册 `AudioManager.OnAudioFocusChangeListener` 处理电话呼入与系统音频抢占。
  - 电池优化忽略引导（`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`）。
- **iOS 端**：
  - 声明 `UIBackgroundModes`（`audio`, `fetch`, `processing`）。
  - 配置 `AVAudioSession` 分类 `.playAndRecord` 与 `.allowBluetooth`。
  - 监听 `AVAudioSession.interruptionNotification` 自动恢复打断音频流。

---

## 📱 界面与交互模块

| 模块 | 说明 |
| :--- | :--- |
| **工作台 (Dashboard)** | 实时音频动态波形可视化（60fps）、瞬时分贝表（dB）、累计时长计时器、主控录制/暂停/停止按钮。 |
| **麦克风 (Microphones)** | 硬件输入源扫描列表、设备类型标签、支持采样率与声道数能力徽章、一键选择生效。 |
| **实时推流 (Streaming)** | 协议选择、服务器 URL、Token 配置，实时推流码率、延迟、已发包数与丢失包数监控。 |
| **分段切片 (Slicer)** | 切片时长配置（默认 5 分钟）、上传目标选择、实时上传任务队列、进度条与重试。 |
| **存储参数 (Settings)** | WebDAV 与 S3 认证配置、连接性一键测试、本地格式/采样率/码率/降噪参数面板。 |
| **录音库 (Recordings)** | 本地录音列表展示、内置波形拖动播放器、文件管理与存储空间分析。 |

---

## 🏗️ 系统架构图

```
+-----------------------------------------------------------------------------------+
|                           Flutter UI Layer (Material 3)                           |
|  [ Dashboard ]  [ Mic Explorer ]  [ Streaming Console ]  [ Slicer & Cloud Queue ] |
+-----------------------------------------+-----------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
|                   AppState (Provider / Reactive Coordinator)                      |
+-----------------------------------------+-----------------------------------------+
                                          | MethodChannel / EventChannel
                                          v
+-----------------------------------------------------------------------------------+
|               Native Audio Engines (Android / iOS Foreground Service)             |
|                                                                                   |
|  [ AudioManager / AudioSession ] <---> [ AudioDeviceManager (Caps & Routing) ]    |
|                                                                                   |
|  [ AudioRecord / AVAudioEngine ] ----> [ Unlocked RingBuffer (PCM 48kHz/16bit) ]  |
+-----------------------------------------+-----------------------------------------+
                                          |
          +-------------------------------+-------------------------------+
          |                               |                               |
          v                               v                               v
+-------------------+           +-------------------+           +-------------------+
|   Streaming Pipe  |           |   Slicer Pipe     |           |   Local Storage   |
|   (WebSocket/Opus)|           |   (5min Rollover) |           |   (AAC/WAV/MP3)   |
+-------------------+           +---------+---------+           +-------------------+
                                          |
                        +-----------------+-----------------+
                        |                                   |
                        v                                   v
             +--------------------+               +--------------------+
             |   WebDAV Client    |               |  S3 SigV4 Client   |
             | (Nextcloud/JianGuo)|               |  (MinIO/R2/AWS/OSS)|
             +--------------------+               +--------------------+
```

---

## ⚙️ 远程存储快速配置指南

### 1. WebDAV 配置示例（如：坚果云 / Nextcloud）
- **服务器 URL**：`https://dav.jianguoyun.com/dav/`
- **用户名**：你的账号邮箱
- **应用密码**：在网盘后台生成的应用专属密码（非登录密码）
- **保存目录**：`/vibeARS/recordings`

### 2. S3 兼容对象存储配置示例（如：Cloudflare R2 / MinIO / 阿里云 OSS）
- **Endpoint**：`xxx.r2.cloudflarestorage.com` 或 `play.min.io` 或 `oss-cn-hangzhou.aliyuncs.com`
- **Region**：`auto` 或 `us-east-1`
- **Bucket**：`my-recordings-bucket`
- **Access Key ID**：你的 AccessKey
- **Secret Access Key**：你的 SecretKey
- **Path-Style**：MinIO 开启，AWS/R2/OSS 关闭

---

## 🚀 持续集成与云端自动构建 (CI/CD)

项目配置了完整的 GitHub Actions 流水线（`.github/workflows/build-and-release.yml`）：

1. **Android 构建流水线**：自动下载 Flutter 与 Android SDK，生成 `vibeARS-Android-release.apk`。
2. **iOS 构建流水线**：在 macOS 运行机上编译生成免签名/企业签名的 `vibeARS-iOS-unsigned.ipa`。
3. **GitHub Release 发布**：构建成功后自动发布 GitHub Release 并附带最新的 APK 和 IPA 产物供下载安装。

---

## 📄 详细设计文档索引

- [系统核心架构设计 (ARCHITECTURE.md)](docs/ARCHITECTURE.md)
- [硬件麦克风探测与音频路由指南 (HARDWARE_AUDIO_ROUTING.md)](docs/HARDWARE_AUDIO_ROUTING.md)
- [远程存储与流式传输协议规范 (STORAGE_AND_STREAMING.md)](docs/STORAGE_AND_STREAMING.md)
- [AI Agent 开发与维护指南 (AGENTS.md)](AGENTS.md)
