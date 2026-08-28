# 上游麦克风硬件探测与音频路由规范

本文档介绍 vibeARS 在 Android 和 iOS 端对音频输入设备的发现、能力探测与实时路由切换机制。

---

## 1. 支持的硬件麦克风类型

| 平台端口类型 | Android 常量 | iOS AVAudioSession.Port | 物理设备说明 |
| :--- | :--- | :--- | :--- |
| **内置麦克风** | `TYPE_BUILTIN_MIC` | `.builtInMic` | 手机机身内置全向麦克风阵列 |
| **有线耳机麦克风** | `TYPE_WIRED_HEADSET` | `.headsetMic` | 3.5mm 或 Lightning/Type-C 转接线耳麦 |
| **蓝牙通话麦克风** | `TYPE_BLUETOOTH_SCO` | `.bluetoothHFP` | 蓝牙耳机 Hands-Free Profile (8k/16k 通话频宽) |
| **蓝牙高清音频** | `TYPE_BLUETOOTH_A2DP` | `.bluetoothA2DP` | 蓝牙高质量双向音频设备 |
| **USB 音频设备** | `TYPE_USB_DEVICE` | `.usbAudio` | 专业 USB 电容麦、声卡、音频接口 |
| **线路输入** | `TYPE_LINE_ANALOG` | `.lineIn` | 模拟/数字线路输入 (Line-in) |

---

## 2. 硬件输出能力探测指标

每台设备探测后均提取以下属性：

1. **设备标识（ID & Name）**：硬件唯一 UID 及展示名称。
2. **支持的采样率（Sample Rates）**：
   - 16,000 Hz（语音 ASR 标准采样率）
   - 44,100 Hz（CD 音质）
   - 48,000 Hz（专业广播/通话音质）
3. **支持的声道数（Channel Counts）**：
   - 1（单声道 Mono）
   - 2（立体声 Stereo）
4. **支持的编码格式（Encodings）**：
   - `PCM_16BIT`（标准 16位无损整型）
   - `PCM_FLOAT`（32位浮点采样）
5. **拾音指向性（Polar Patterns - 仅 iOS）**：
   - 全向（Omnidirectional）
   - 心形指向（Cardioid）
   - 超心形（Subcardioid）
   - 立体声对（Stereo）

---

## 3. 动态切换与热插拔逻辑

### 3.1 Android 切换机制
```kotlin
val audioRecord = ... // 当前活跃的 AudioRecord
val targetDevice = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS).find { it.id == deviceId }
if (targetDevice != null) {
    audioRecord.setPreferredDevice(targetDevice)
    if (targetDevice.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) {
        audioManager.startBluetoothSco()
        audioManager.isBluetoothScoOn = true
    }
}
```

### 3.2 iOS 切换机制
```swift
let session = AVAudioSession.sharedInstance()
if let targetPort = session.availableInputs?.first(where: { $0.uid == deviceUID }) {
    try session.setPreferredInput(targetPort)
}
```
无需销毁并重启整个录音会话即可平滑切换输入路由。
