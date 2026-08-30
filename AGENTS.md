# AI Agent Instructions & Context for vibeARS

## 1. Project Overview & Mission
**vibeARS** is a mobile audio recording application built with a decoupled architecture (Flutter UI + Native Audio Engines).
Core capabilities:
1. **Uninterrupted Background Audio Recording**: Foreground service with microphone permission on Android; background audio mode on iOS.
2. **Upstream Hardware Mic Discovery & Routing**: Real-time enumeration of audio input devices (built-in, bluetooth SCO/A2DP, USB audio interfaces, wired headsets) with capability breakdown (sample rates, channels, encodings, polar patterns) and runtime dynamic switching.
3. **Multi-Channel Fan-Out Pipeline**:
   - Real-time Low-Latency Streaming over WebSocket binary frames (Opus-compressed or raw PCM). WebRTC is NOT implemented — do not advertise it; a WebRTC channel would require a signaling server and is left as a possible extension.
   - 5-Minute Seamless Slicer (Sample-accurate rollover without frame loss/glitches).
   - Local Archiver supporting native **WAV** and **AAC/M4A** recording with a full-featured player & batch exporter (share/ZIP/copy).
4. **Multi-Cloud Remote Slicing Storage**:
   - WebDAV (RFC 4918).
   - S3-compatible object storage (AWS SigV4).
5. **Zero Local Compilation Constraint**:
   - All builds, testing, and artifact generations MUST occur via GitHub Actions CI/CD workflows (`.github/workflows/build-and-release.yml`), releasing APK and IPA automatically.

---

## 2. Directory Structure Map

```
vibeARS/
├── .github/
│   └── workflows/
│       └── build-and-release.yml    # CI/CD Workflow for Android APK & iOS IPA Release
├── android/
│   ├── app/
│   │   ├── build.gradle             # Android App build config (compileSdk 34, minSdk 24)
│   │   └── src/main/
│   │       ├── AndroidManifest.xml  # Permissions (RECORD_AUDIO, FOREGROUND_SERVICE_MICROPHONE)
│   │       └── kotlin/com/vibears/app/
│   │           ├── MainActivity.kt
│   │           └── audio/
│   │               ├── AudioCaptureService.kt   # Persistent Foreground Service & WakeLock
│   │               ├── AudioDeviceManager.kt   # Input devices discovery & routing
│   │               ├── AudioPipeline.kt        # AudioRecord loop, amplitude, 5min slicer
│   │               └── VibeAudioPlugin.kt      # MethodChannel & EventChannel bindings
├── ios/
│   ├── Podfile
│   └── Runner/
│       ├── Info.plist               # UIBackgroundModes (audio), Microphone descriptions
│       └── AppDelegate.swift        # Flutter bridge + AudioDeviceManager + AudioEngineManager
│           (Audio device discovery, AVAudioEngine capture, amplitude, 5min slicer,
│            and the VibeAudioPlugin MethodChannel/EventChannel are all in AppDelegate.swift)
├── lib/
│   ├── main.dart
│   ├── core/
│   │   └── models/
│   │       ├── audio_config.dart    # Format, bitrate, sample rate, channels
│   │       ├── audio_device.dart    # Hardware device & capability models
│   │       ├── slicer_config.dart   # Slicer interval, slice items, status
│   │       ├── storage_config.dart  # WebDAV & S3 configuration models
│   │       └── streaming_config.dart# WebSocket streaming models
│   ├── providers/
│   │   └── app_state.dart           # Master reactive coordinator & state provider
│   ├── services/
│   │   ├── audio_engine_service.dart# Native platform channel bridge & path resolver
│   │   ├── streaming_service.dart   # WebSocket low-latency streaming client
│   │   ├── local_storage_service.dart # Local file manager, advanced player & batch exporter
│   │   └── storage/
│   │       ├── storage_adapter.dart     # Storage contract
│   │       ├── webdav_storage_adapter.dart # WebDAV RFC 4918 client
│   │       ├── s3_storage_adapter.dart  # AWS SigV4 S3 client
│   │       └── upload_queue_manager.dart# Persistent upload queue & retry
│   └── ui/
│       ├── theme.dart               # Modern Material 3 dark audio theme
│       ├── main_navigation_scaffold.dart
│       ├── screens/
│       │   ├── dashboard_screen.dart        # Real-time visualizer, timer & master controls
│       │   ├── devices_screen.dart          # Upstream microphone hardware inspector
│       │   ├── streaming_screen.dart        # Live streaming console & telemetry
│       │   ├── slicer_screen.dart           # Segment slicer settings & upload queue
│       │   ├── storage_settings_screen.dart # Path selection, permissions & cloud settings
│       │   └── local_recordings_screen.dart # Local recordings, batch exporter & mini-player
│       └── widgets/
│           ├── waveform_visualizer.dart     # 60fps dynamic audio visualizer
│           └── full_player_bottom_sheet.dart# Full-featured player with speed/loop/skip
├── docs/
│   ├── ARCHITECTURE.md
│   ├── HARDWARE_AUDIO_ROUTING.md
│   └── STORAGE_AND_STREAMING.md
├── pubspec.yaml
├── README.md
└── AGENTS.md
```

---

## 3. Important Design Invariants for Future Agents

1. **Decoupled Architecture**:
   - The Flutter UI communicates exclusively via `AppState` -> `Services` -> `Native Plugin`.
   - If writing a pure Native UI (Kotlin Jetpack Compose or Swift SwiftUI) in the future, the underlying native audio engines (`android/.../audio` and `ios/.../Audio`) are already completely standalone and self-contained.
2. **Seamless Audio Slicing**:
   - Never stop the active `AudioRecord` / `AVAudioEngine` when rolling over slices. Keep the stream open and swap the output file descriptor on the fly based on sample count.
3. **Storage & Public Folder Priority**:
   - On Android, default storage path prioritizes system public directories (e.g. `/storage/emulated/0/Music/vibeARS`), with presets for Downloads, Documents, Recordings, and custom absolute paths.
4. **Enhanced Player & Batch Exporter**:
   - Player supports 0.5x-2.0x playback speed, +/-10s skipping, loop/single/shuffle play modes, and waveform display.
   - Batch exporter supports multi-selection, system Share Sheet, ZIP packaging and exporting, target directory copy, and bulk deletion.
5. **AWS SigV4 Client**:
   - The custom S3 client avoids heavy external dependencies and supports custom endpoints, path-style and virtual-hosted-style URLs out of the box.
   - The canonical query string is rebuilt from the decoded parameter map and encoded exactly once, and `listRemoteFiles` uses a proper ListObjectsV2 URL.
6. **CI/CD Build Rules**:
   - Do NOT run local compiler toolchains on host. Commit and push code to GitHub `main` branch to trigger the GitHub Actions workflow, which automatically generates both Android APK and iOS IPA in GitHub Releases.
   - The workflow runs `flutter create --no-overwrite` so README/docs and hand-written platform files are never clobbered.
7. **Known Implementation Constraints (verified by CI)**:
   - Recording formats (all available on both platforms): **WAV (PCM+RIFF)**, **AAC/M4A** (Android MediaCodec+MediaMuxer, iOS AVAudioFile), **MP3** (bundled LAME via `flutter_lame` 1.0.3 — WAV slices transcoded after recording stops; the `dart_lame` 1.0.3 API uses NAMED constructor args and async `encode(leftChannel:)/flush()/close()`), and **Opus** — Android real-time `.ogg` via system MediaCodec `audio/opus` + OGG muxer (API 29+), iOS via the vendored `ios/ThirdParty/Opus.xcframework` (libopusenc) called from Dart FFI (`lib/services/opus_converter.dart`, WAV→`.opus` transcode after recording stops; the pod uses `-force_load` so the symbols survive linking). AAC/MP3/Opus respect the configured bit rate.
   - `ffmpeg_kit_flutter_audio` is unusable (upstream `com.arthenica` AAR and iOS pods were taken offline — 404 on both Maven and CocoaPods). Do not reintroduce it.
   - On Android, MediaCodec AAC output may carry an ADTS header; the pipeline strips it before MediaMuxer, and the muxer track is added once `INFO_OUTPUT_FORMAT_CHANGED` is observed. ADTS stripping must stay AAC-only (Opus packets never start with 0xFF).
   - `ChoiceChip` has no `enabled` parameter — disable via a null `onSelected`.
   - The resolved `archive` version only supports the 3-argument `ArchiveFile(name, size, bytes)` constructor.
   - `double.clamp()` returns `num` — always append `.toDouble()` before assigning to `double` fields or widget `height`/`value` parameters.
   - Dart `List.filled()` is fixed-length: use `growable: true` before calling `removeAt`.
   - Recording start must surface real failure: native `startRecording` returns success/failure, and the writable-directory probe runs before capture starts.
