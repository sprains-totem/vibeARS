# 远程存储与实时流式传输协议规范

本文档详述 vibeARS 支持的 **WebDAV 网盘同步**、**S3 兼容对象存储上传** 以及 **低延迟实时音频推流** 协议实现。

---

## 1. WebDAV 远程存储适配规范 (RFC 4918)

vibeARS 内置了轻量级原生 WebDAV 客户端，遵循 RFC 4918 规范：

### 1.1 认证与连通性验证
- 支持 `HTTP Basic Auth`：`Authorization: Basic base64(username:password)`。
- 发送 `PROPFIND`（Header: `Depth: 0`）探测服务端可用性。

### 1.2 自动递归目录创建
在上传切片文件前，自动解析目标远程路径（例如 `/vibeARS/recordings/`），逐级发送 `MKCOL` 请求确保目录存在。

### 1.3 流式分块上传
使用 `PUT` 请求配合 `http.StreamedRequest`，边读取本地文件分块边计算传输百分比，并在 UI 上实时呈现进度条。

---

## 2. S3 兼容对象存储规范 (AWS Signature Version 4)

vibeARS 实现了纯 Dart 版的 **AWS SigV4** 签名算法，无需依赖重量级的庞大 SDK，即可直连所有主流对象存储服务：

### 2.1 兼容存储服务列表
- Amazon S3
- Cloudflare R2
- MinIO (私有化部署)
- 阿里云 OSS
- 腾讯云 COS
- 华为云 OBS
- Backblaze B2

### 2.2 签名与寻址模式
1. **Canonical Request 构建**：规范化 HTTP 方法、URI、查询参数、`host`, `x-amz-date`, `x-amz-content-sha256` 头部。
2. **String to Sign 派生**：通过 HMAC-SHA256 逐步计算 `DateKey -> RegionKey -> ServiceKey -> SigningKey`。
3. **寻址模式支持**：
   - **Path-Style（路径式）**：`https://<endpoint>/<bucket>/<key>`（MinIO 常用）。
   - **Virtual-Hosted-Style（虚拟主机式）**：`https://<bucket>.<endpoint>/<key>`（AWS S3 / R2 常用）。

---

## 3. 实时流式传输协议 (Streaming Protocols)

### 3.1 WebSocket 二进制推流（上行音频处理链路）

上行链路对标监控摄像头/对讲设备的音频上行：**采集 → 编码 → 分帧 → 推送**。

- **协议握手（JSON Handshake）**：
  ```json
  {
    "event": "handshake",
    "streamId": "room_1001_mic_master",
    "protocol": "webSocketAac",
    "sampleRate": 48000,
    "channels": 2,
    "timestamp": "2024-01-01T12:00:00.000Z",
    "client": "vibeARS-Mobile"
  }
  ```
- **上行编码（设备端完成）**：
  - `webSocketPcm`：直接发送 **16-bit 小端 PCM 原始帧**（零编码开销，服务器可直接解码，最通用）。
  - `webSocketAac`：设备端（Android MediaCodec / iOS AVAudioConverter）将 PCM 实时编码为 **AAC-LC + ADTS 帧**（每帧 1024 采样，带 ADTS 头，服务器可连续流式解码），带宽约为 PCM 的 1/8-1/15。
  - 注：平台不提供 Opus 编码器，故不提供 Opus 上行；如需 Opus 需集成 libopus。
- **音频数据分包（Binary Payload）**：
  - 握手完成后，后续直接通过 WebSocket 发送二进制帧（PCM 字节或 AAC/ADTS 帧，每包约 20ms-100ms 粒度）。
  - 内置 10s 心跳（客户端发 `{"event":"ping"}`，服务器回 `{"event":"pong"}`）精确测量端到端往返延迟（RTT）。
  - 弱网处理：发送失败计为丢包（`droppedPackets`），断线后按 3s 间隔自动重连；本地录制不受弱网影响（上行与落盘完全解耦）。
