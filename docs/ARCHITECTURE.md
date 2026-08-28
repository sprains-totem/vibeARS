# vibeARS 系统核心架构与设计规范

本文档详述 **vibeARS** 客户端的音频采集子系统、多路分发调度机制、后台保活体系以及分段无缝切片原理。

---

## 1. 系统总体架构与分层

vibeARS 采用严格的**分层解耦架构**：

```
+-------------------------------------------------------------+
|                      1. UI 表示层 (Flutter)                   |
|   Dashboard | Mic Inspector | Slicer Queue | Settings Panel |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|                2. 业务调度层 (AppState & Services)            |
|   - AudioEngineService    - StreamingService                |
|   - SlicerService         - UploadQueueManager              |
|   - LocalStorageService   - StorageAdapters (WebDAV / S3)   |
+-------------------------------------------------------------+
                              | Platform Channels (Method/Event)
+-------------------------------------------------------------+
|                3. 原生音频引擎层 (Native Audio Engine)        |
|   - Android: AudioCaptureService + AudioRecord + AudioDevice|
|   - iOS: AudioEngineManager + AVAudioEngine + AudioSession  |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|                4. 底层硬件与操作系统驱动层 (Hardware & OS)     |
|   Built-in Mic | Bluetooth SCO | USB Audio Interface        |
+-------------------------------------------------------------+
```

---

## 2. 单输入与三路扇出流水线 (1-In-3-Out Fan-out Pipeline)

### 2.1 底层无锁 PCM 环形缓冲
音频采集引擎统一在底层以标准 PCM 格式（默认 48,000 Hz, 16-bit, 双声道）进行硬件采集。采集线程独立运行于系统高优先级原生线程（Android `Thread.MAX_PRIORITY`，iOS 实时音频回调）。

PCM 数据帧进入环形缓冲池后，同时扇出分发给以下三条独立的消费管道：

### 2.2 管道一：实时流式推流 (Streaming Pipeline)
- 将 PCM 原始帧或压缩后的 Opus 帧通过轻量级二进制 WebSocket 管道实时推送至远端流式处理服务。
- 管道设计具备自适应流量控制，当检测到弱网或推流堵塞时，优先保障本地录制，仅丢弃实时流并触发断网重连。

### 2.3 管道二：定时分段切片与上传 (Segment Slicer Pipeline)
- 采用**样本精确度计数器（Sample-Accurate Counter）**。
- 计算公式：
  $$\text{MaxSliceBytes} = \text{SampleRate} \times \text{Channels} \times \text{BytesPerSample} \times (\text{IntervalMinutes} \times 60)$$
- 当写入字节数达到阈值时：
  1. 瞬间锁定当前文件描述符，补齐 WAV 头信息或写出封装尾部。
  2. 立即分配新的文件写入器，后续采样点直接无缝流入新文件。
  3. 将完成的文件抛送至 `UploadQueueManager`，异步执行 WebDAV / S3 上传。

### 2.4 管道三：本地归档与质量选择 (Local Archiving Pipeline)
- 负责本地长期持久化。
- 支持用户设定的动态采样率与压缩码率（如 AAC 192kbps 或无损 WAV）。

---

## 3. 移动端后台保活体系

### 3.1 Android 保活技术矩阵
1. **前台服务（Foreground Service）**：
   - 适配 Android 10 - 14，在 `AndroidManifest.xml` 中指定 `android:foregroundServiceType="microphone"`。
   - 调用 `startForeground()` 展示不可消除的常驻系统通知。
2. **电源唤醒锁（WakeLock）**：
   - 持有 `PowerManager.PARTIAL_WAKE_LOCK`，确保屏幕熄灭锁屏后 CPU 依然满频运行音频处理循环。
3. **电池白名单请求**：
   - 触发 `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` 系统意图，规避厂商 Doze 深度休眠杀进程。
4. **音频焦点（Audio Focus）**：
   - 监听 `AudioManager.OnAudioFocusChangeListener`，在电话呼入时优雅暂停，通话结束后自动恢复。

### 3.2 iOS 后台模式与中断处理
1. **后台模式声明**：
   - `UIBackgroundModes` 包含 `audio`, `fetch`, `processing`。
2. **AudioSession 策略**：
   - 配置 `.playAndRecord`，开启 `.allowBluetooth`, `.allowBluetoothA2DP`, `.mixWithOthers` 选项。
3. **系统中断处理**：
   - 注册 `AVAudioSession.interruptionNotification`，识别 `.began` 与 `.ended`（`.shouldResume`），保障切后台及电话挂断后的不间断录音。
