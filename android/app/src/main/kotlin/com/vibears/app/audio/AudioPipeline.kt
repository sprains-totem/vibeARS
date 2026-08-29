package com.vibears.app.audio

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.sqrt

interface AudioPipelineListener {
    fun onAudioFrame(pcmData: ByteArray, amplitude: Double, db: Double, aacData: ByteArray? = null)
    fun onSliceCompleted(sliceInfo: Map<String, Any>)
    fun onError(errorMessage: String)
}

class AudioPipeline(
    private val context: Context,
    private val sampleRate: Int = 48000,
    private val channelCount: Int = 2,
    private val format: String = "wav", // wav | m4a
    private val bitRate: Int = 128000,
    private val preferredDeviceId: Int? = null,
    private val slicerEnabled: Boolean = true,
    private val sliceDurationMs: Long = 5 * 60 * 1000L, // 5 minutes default
    private val outputDir: String,
    private val uplinkAac: Boolean = false,
    private val listener: AudioPipelineListener
) {
    private val TAG = "AudioPipeline"
    private val isRecording = AtomicBoolean(false)
    private val isPaused = AtomicBoolean(false)
    private var startupThread: Thread? = null
    private var recordThread: Thread? = null
    private var audioRecord: AudioRecord? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val audioDeviceManager = AudioDeviceManager(context)

    /** Log to logcat AND forward to the in-app LogCollector. */
    private fun nl(tag: String, message: String) {
        Log.d(tag, message)
        VibeAudioPlugin.reportNativeLog(tag, message)
    }

    /** WAV (PCM + RIFF header) output. */
    private val isWavOutput: Boolean = format.lowercase() == "wav"

    /** AAC/M4A output via MediaCodec + MediaMuxer. */
    private val isM4aOutput: Boolean = format.lowercase() in setOf("m4a", "aac")

    // Current slice file tracking
    private var currentSliceFile: File? = null
    private var currentSliceOutputStream: FileOutputStream? = null
    private var currentSlicePcmBytesWritten: Long = 0L
    private var currentSliceFramesWritten: Long = 0L
    private var currentSliceStartTime: Long = 0L
    private var sliceSequence: Int = 1
    private val sessionId: String = UUID.randomUUID().toString()

    // AAC encoder state (m4a only)
    private var mediaCodec: MediaCodec? = null
    private var mediaMuxer: MediaMuxer? = null
    private var muxerTrackIndex: Int = -1
    private var muxerStarted: Boolean = false
    private var encoderPtsUs: Long = 0L

    // Real-time uplink AAC/ADTS encoder (used when the streaming protocol is
    // webSocketAac). Emits standalone ADTS frames that the server can decode
    // as a continuous stream — mirroring how cameras push encoded audio up.
    private var uplinkCodec: MediaCodec? = null
    private var uplinkPtsUs: Long = 0L

    fun start(): Boolean {
        if (isRecording.get()) return true

        val isSco = audioDeviceManager.isScoDevice(preferredDeviceId)
        Log.d(TAG, "start() isSco=$isSco preferredDeviceId=$preferredDeviceId")
        nl(TAG, "start() isSco=$isSco preferredDeviceId=$preferredDeviceId")

        if (isSco) {
            // SCO activation is asynchronous (waits for the CONNECTED
            // broadcast), so run the whole startup on a background thread to
            // avoid blocking the main thread / ANR.
            isRecording.set(true)
            startupThread = Thread({ startCapture(awaitSco = true) }, "AudioStartupThread")
            startupThread?.priority = Thread.MAX_PRIORITY
            startupThread?.start()
            return true
        }
        return startCapture(awaitSco = false)
    }

    private fun startCapture(awaitSco: Boolean): Boolean {
        if (isRecording.get() && audioRecord != null) return true

        Log.d(TAG, "startCapture(awaitSco=$awaitSco) sampleRate=$sampleRate channels=$channelCount format=$format")
        nl(TAG, "startCapture(awaitSco=$awaitSco) sampleRate=$sampleRate channels=$channelCount format=$format")

        // Validate that the output directory is actually writable before
        // starting the capture loop, otherwise the session would silently
        // produce no files at all.
        try {
            val dir = File(outputDir)
            if (!dir.exists() && !dir.mkdirs()) {
                listener.onError("Failed to create output directory: $outputDir")
                isRecording.set(false)
                return false
            }
            if (!dir.canWrite()) {
                listener.onError("Output directory is not writable: $outputDir")
                isRecording.set(false)
                return false
            }
            val probe = File(dir, ".vibears_write_probe")
            if (!probe.createNewFile()) {
                listener.onError("Output directory is not writable: $outputDir")
                isRecording.set(false)
                return false
            }
            probe.delete()
        } catch (e: Exception) {
            listener.onError("Output directory is not writable: ${e.message}")
            isRecording.set(false)
            return false
        }

        val channelConfig = if (channelCount == 1) {
            AudioFormat.CHANNEL_IN_MONO
        } else {
            AudioFormat.CHANNEL_IN_STEREO
        }
        val audioEncoding = AudioFormat.ENCODING_PCM_16BIT

        // Bluetooth SCO capture: activate the communication route BEFORE the
        // AudioRecord is created, and use VOICE_COMMUNICATION as the source so
        // the hardware routes the microphone through the HFP/SCO path.
        val routeReady = audioDeviceManager.prepareDeviceRoute(preferredDeviceId)
        if (awaitSco && !routeReady) {
            listener.onError("Bluetooth SCO 未在超时内建立连接，请确认耳机已连接并重试")
            isRecording.set(false)
            return false
        }
        val audioSource = audioDeviceManager.resolveAudioSource(preferredDeviceId)

        val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioEncoding)
        if (minBufferSize <= 0) {
            listener.onError("Sample rate $sampleRate is not supported by this device")
            isRecording.set(false)
            return false
        }
        val bufferSize = (minBufferSize * 2).coerceAtLeast(sampleRate * channelCount * 2 / 10) // 100ms buffer

        try {
            audioRecord = AudioRecord(
                audioSource,
                sampleRate,
                channelConfig,
                audioEncoding,
                bufferSize
            )
            Log.d(TAG, "AudioRecord created: source=$audioSource rate=$sampleRate ch=$channelConfig buf=$bufferSize state=${audioRecord?.state}")
            nl(TAG, "AudioRecord created: source=$audioSource rate=$sampleRate ch=$channelConfig buf=$bufferSize state=${audioRecord?.state}")

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                listener.onError("AudioRecord failed to initialize")
                isRecording.set(false)
                return false
            }

            // Apply preferred hardware microphone if specified
            if (preferredDeviceId != null) {
                audioDeviceManager.applyPreferredDevice(audioRecord!!, preferredDeviceId)
            }

            isRecording.set(true)
            isPaused.set(false)
            audioRecord?.startRecording()
            Log.d(TAG, "AudioRecord.startRecording() OK")
            nl(TAG, "AudioRecord.startRecording() OK")
            // If a preferred device was routed, confirm the record object's
            // actual routed input device (verifies SCO data path, not just API
            // success).
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                val routed = audioRecord?.routedDevice
                nl(
                    TAG,
                    "AudioRecord.routedDevice: " +
                        (routed?.let { "id=${it.id} type=${it.type}" } ?: "null")
                )
            }

            // Start the uplink AAC encoder if requested (ADTS stream output).
            if (uplinkAac) {
                uplinkCodec = configureUplinkAacEncoder()
                uplinkPtsUs = 0L
            }

            // Initialize the first slice file
            if (!openNextSlice()) {
                isRecording.set(false)
                listener.onError("Failed to create initial slice file")
                return false
            }

            recordThread = Thread({ recordLoop(bufferSize) }, "AudioCaptureThread")
            recordThread?.priority = Thread.MAX_PRIORITY
            recordThread?.start()
            Log.d(TAG, "Audio recording pipeline started (format=$format, bitRate=$bitRate, sco=$awaitSco)")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start audio recording", e)
            isRecording.set(false)
            listener.onError("Failed to start audio recording: ${e.message}")
            return false
        }
    }

    fun pause() {
        isPaused.set(true)
    }

    fun resume() {
        isPaused.set(false)
    }

    fun stop() {
        if (!isRecording.get()) return
        isRecording.set(false)

        try {
            startupThread?.join(5000)
            startupThread = null
        } catch (e: Exception) {
            Log.e(TAG, "Error waiting for startup thread", e)
        }

        try {
            recordThread?.join(1000)
        } catch (e: Exception) {
            Log.e(TAG, "Error waiting for record thread to stop", e)
        }

        try {
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping AudioRecord", e)
        }

        // Release the uplink encoder.
        try {
            uplinkCodec?.stop()
            uplinkCodec?.release()
            uplinkCodec = null
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing uplink codec", e)
        }

        // Release the Bluetooth SCO route if it was activated.
        audioDeviceManager.stopBluetoothRoute()

        // Close and finalize the last slice
        closeCurrentSlice()
        Log.d(TAG, "Audio recording pipeline stopped")
    }

    private fun recordLoop(bufferSize: Int) {
        val audioBuffer = ShortArray(bufferSize / 2)
        val bytesPerSample = 2 // 16-bit
        val bytesPerSecond = sampleRate * channelCount * bytesPerSample
        val maxBytesPerSlice = (sliceDurationMs * bytesPerSecond / 1000L)
        val maxFramesPerSlice = sampleRate * sliceDurationMs / 1000L

        while (isRecording.get()) {
            if (isPaused.get()) {
                try {
                    Thread.sleep(50)
                } catch (_: InterruptedException) {}
                continue
            }

            val readCount = audioRecord?.read(audioBuffer, 0, audioBuffer.size) ?: 0
            if (readCount > 0) {
                val frames = readCount / channelCount

                // 1. Calculate Amplitude and Decibel for UI visualizer
                var sumSquare = 0.0
                var maxSample = 0
                for (i in 0 until readCount) {
                    val sample = audioBuffer[i].toInt()
                    sumSquare += sample * sample
                    val absVal = abs(sample)
                    if (absVal > maxSample) {
                        maxSample = absVal
                    }
                }
                val rms = sqrt(sumSquare / readCount)
                val normalizedAmplitude = (maxSample / 32768.0).coerceIn(0.0, 1.0)
                val db = if (rms > 0) (20 * kotlin.math.log10(rms / 32768.0) + 90).coerceIn(0.0, 100.0) else 0.0

                // 2. Convert ShortArray to ByteArray (Little-Endian PCM)
                val byteBuffer = ByteBuffer.allocate(readCount * 2).order(ByteOrder.LITTLE_ENDIAN)
                for (i in 0 until readCount) {
                    byteBuffer.putShort(audioBuffer[i])
                }
                val pcmBytes = byteBuffer.array()

                // Encode this PCM block into one or more ADTS AAC frames for
                // the real-time uplink (if enabled).
                val uplinkFrames = drainUplinkAac(pcmBytes)

                // Dispatch PCM frame (+ optional AAC uplink frames) for
                // real-time streaming & UI visualization
                mainHandler.post {
                    listener.onAudioFrame(pcmBytes, normalizedAmplitude, db, uplinkFrames)
                }

                try {
                    if (isM4aOutput) {
                        // Encode through MediaCodec and mux into the .m4a file.
                        encodeAacFrame(pcmBytes, frames)
                        currentSliceFramesWritten += frames
                        if (slicerEnabled && currentSliceFramesWritten >= maxFramesPerSlice) {
                            finishM4aSlice()
                            if (!openNextSlice()) {
                                listener.onError("Failed to create next slice file, recording stopped")
                                isRecording.set(false)
                            }
                        }
                    } else {
                        // 3. Write to the current WAV slice file
                        currentSliceOutputStream?.write(pcmBytes)
                        currentSlicePcmBytesWritten += pcmBytes.size

                        // 4. Check if slice duration reached -> Seamless Rollover
                        if (slicerEnabled && currentSlicePcmBytesWritten >= maxBytesPerSlice) {
                            closeCurrentSlice()
                            if (!openNextSlice()) {
                                listener.onError("Failed to create next slice file, recording stopped")
                                isRecording.set(false)
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error writing audio slice", e)
                    listener.onError("Error writing audio slice: ${e.message}")
                    isRecording.set(false)
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // AAC (M4A) encoding via MediaCodec + MediaMuxer
    // ------------------------------------------------------------------

    /** Uplink encoder with ADTS output for live streaming (no muxer). */
    private fun configureUplinkAacEncoder(): MediaCodec {
        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channelCount)
        format.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
        format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
        format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 100 * 1024)
        format.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
        // ADTS framing: each output buffer is a self-contained AAC frame with
        // an ADTS header, which servers can decode as a continuous stream.
        format.setInteger(MediaFormat.KEY_IS_ADTS, 1)

        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
        return codec
    }

    /** Feeds one PCM block into the uplink encoder and drains all available
     *  ADTS frames, concatenated, or null when nothing is ready yet. */
    private fun drainUplinkAac(pcmBytes: ByteArray): ByteArray? {
        val codec = uplinkCodec ?: return null

        val inIndex = codec.dequeueInputBuffer(10_000)
        if (inIndex >= 0) {
            val inBuf = codec.getInputBuffer(inIndex) ?: return null
            inBuf.clear()
            inBuf.put(pcmBytes)
            val frames = pcmBytes.size / 2 / channelCount
            codec.queueInputBuffer(inIndex, 0, pcmBytes.size, uplinkPtsUs, 0)
            uplinkPtsUs += frames * 1_000_000L / sampleRate
        }

        // Collect every ready ADTS frame; a single PCM block can yield 1+ AAC
        // frames (AAC frame = 1024 samples), so drain the output queue fully.
        val chunks = mutableListOf<ByteArray>()
        val info = MediaCodec.BufferInfo()
        while (true) {
            val outIndex = codec.dequeueOutputBuffer(info, 0)
            if (outIndex < 0) break
            if (info.size > 0) {
                val outBuf = codec.getOutputBuffer(outIndex) ?: break
                val bytes = ByteArray(info.size)
                outBuf.position(info.offset)
                outBuf.get(bytes, 0, info.size)
                chunks.add(bytes)
            }
            codec.releaseOutputBuffer(outIndex, false)
        }
        if (chunks.isEmpty()) return null
        val total = chunks.sumOf { it.size }
        val merged = ByteArray(total)
        var offset = 0
        for (chunk in chunks) {
            System.arraycopy(chunk, 0, merged, offset, chunk.size)
            offset += chunk.size
        }
        return merged
    }

    private fun configureAacEncoder(): MediaCodec {
        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channelCount)
        format.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
        format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
        format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 100 * 1024)
        format.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)

        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
        encoderPtsUs = 0L
        return codec
    }

    private fun encodeAacFrame(pcmBytes: ByteArray, frames: Int) {
        val codec = mediaCodec ?: return
        val muxer = mediaMuxer ?: return

        val inIndex = codec.dequeueInputBuffer(10_000)
        if (inIndex >= 0) {
            val inBuf = codec.getInputBuffer(inIndex) ?: return
            inBuf.clear()
            inBuf.put(pcmBytes)
            codec.queueInputBuffer(inIndex, 0, pcmBytes.size, encoderPtsUs, 0)
        }
        encoderPtsUs += frames * 1_000_000L / sampleRate

        drainAacOutputs(muxer, endOfStream = false)
    }

    /** Writes one encoded sample to the muxer, stripping any ADTS header. */
    private fun writeAacSample(
        muxer: MediaMuxer,
        codec: MediaCodec,
        outIndex: Int,
        info: MediaCodec.BufferInfo
    ) {
        val outBuf = codec.getOutputBuffer(outIndex) ?: return
        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
            // Codec config is delivered via the muxer format; skip it.
            return
        }
        if (!muxerStarted || info.size <= 0) return

        var offset = info.offset
        var size = info.size
        // Some encoders emit an ADTS header; MediaMuxer needs raw AAC.
        if (size > 0 && (outBuf.get(offset).toInt() and 0xFF) == 0xFF) {
            val headerLen =
                ((outBuf.get(offset + 1).toInt() and 0x03) shl 11) or
                    ((outBuf.get(offset + 2).toInt() and 0xFF) shl 3) or
                    ((outBuf.get(offset + 3).toInt() and 0xE0) shr 5)
            offset += headerLen
            size -= headerLen
        }
        if (size <= 0) return

        outBuf.position(offset)
        outBuf.limit(offset + size)
        val sampleInfo = MediaCodec.BufferInfo()
        sampleInfo.set(offset, size, info.presentationTimeUs, info.flags)
        muxer.writeSampleData(muxerTrackIndex, outBuf, sampleInfo)
    }

    private fun drainAacOutputs(muxer: MediaMuxer, endOfStream: Boolean) {
        val codec = mediaCodec ?: return
        val info = MediaCodec.BufferInfo()

        while (true) {
            val outIndex = codec.dequeueOutputBuffer(info, if (endOfStream) 10_000 else 0)
            when {
                outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (!muxerStarted) {
                        muxerTrackIndex = muxer.addTrack(codec.outputFormat)
                        muxer.start()
                        muxerStarted = true
                    }
                }
                outIndex >= 0 -> {
                    writeAacSample(muxer, codec, outIndex, info)
                    codec.releaseOutputBuffer(outIndex, false)
                    if (endOfStream && info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        return
                    }
                }
                else -> {
                    // INFO_TRY_AGAIN_LATER: nothing more available right now.
                    if (!endOfStream) return
                    // While finishing, keep draining until EOS flag or timeout.
                    // The 10s timeout on dequeueOutputBuffer prevents a hang.
                    if (outIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                        return
                    }
                }
            }
        }
    }

    private fun finishM4aSlice() {
        val codec = mediaCodec ?: return
        val muxer = mediaMuxer ?: return

        try {
            // Signal end-of-stream and drain remaining encoded frames.
            val inIndex = codec.dequeueInputBuffer(10_000)
            if (inIndex >= 0) {
                codec.queueInputBuffer(inIndex, 0, 0, encoderPtsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            }
            drainAacOutputs(muxer, endOfStream = true)

            codec.stop()
            codec.release()
            mediaCodec = null

            if (muxerStarted) {
                muxer.stop()
            }
            muxer.release()
            mediaMuxer = null
            muxerStarted = false
            muxerTrackIndex = -1
        } catch (e: Exception) {
            Log.e(TAG, "Error finalizing m4a slice", e)
            listener.onError("Failed to finalize m4a slice: ${e.message}")
        }
    }

    // ------------------------------------------------------------------
    // Slice file lifecycle
    // ------------------------------------------------------------------

    private fun openNextSlice(): Boolean {
        return try {
            val dir = File(outputDir)
            if (!dir.exists()) {
                dir.mkdirs()
            }
            val timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            val extension = if (isM4aOutput) "m4a" else "wav"
            val fileName = "vibe_slice_${timeStamp}_part${sliceSequence}.$extension"
            val file = File(dir, fileName)

            if (isM4aOutput) {
                mediaMuxer = MediaMuxer(file.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                muxerStarted = false
                muxerTrackIndex = -1
                mediaCodec = configureAacEncoder()
            } else {
                val fos = FileOutputStream(file)
                // Write 44-byte empty placeholder header for WAV
                val emptyHeader = ByteArray(44)
                fos.write(emptyHeader)
                currentSliceOutputStream = fos
            }

            currentSliceFile = file
            currentSlicePcmBytesWritten = 0L
            currentSliceFramesWritten = 0L
            currentSliceStartTime = System.currentTimeMillis()
            Log.d(TAG, "Opened new slice file: ${file.absolutePath}, sequence: $sliceSequence")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open new slice file", e)
            listener.onError("Failed to create slice file: ${e.message}")
            false
        }
    }

    private fun closeCurrentSlice() {
        val file = currentSliceFile ?: return

        try {
            if (isM4aOutput) {
                finishM4aSlice()
            } else {
                val fos = currentSliceOutputStream
                if (fos == null) {
                    currentSliceFile = null
                    return
                }
                fos.flush()
                fos.close()
                currentSliceOutputStream = null

                if (isWavOutput) {
                    // Update WAV header with exact total length
                    writeWavHeader(file, currentSlicePcmBytesWritten, sampleRate, channelCount, 16)
                }
            }

            val actualDurationMs = if (isM4aOutput) {
                (currentSliceFramesWritten * 1000L) / sampleRate
            } else if (sampleRate > 0 && channelCount > 0) {
                (currentSlicePcmBytesWritten * 1000L) / (sampleRate * channelCount * 2)
            } else {
                System.currentTimeMillis() - currentSliceStartTime
            }

            val sizeBytes = file.length().coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
            val sliceMap = mapOf(
                "id" to UUID.randomUUID().toString(),
                "sequence" to sliceSequence,
                "sessionId" to sessionId,
                "localPath" to file.absolutePath,
                "fileName" to file.name,
                "durationMs" to actualDurationMs.toInt(),
                "fileSizeBytes" to sizeBytes,
                "createdAt" to SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).format(Date())
            )

            Log.d(TAG, "Slice completed: ${file.name}, size: ${file.length()} bytes, duration: ${actualDurationMs}ms")
            sliceSequence++

            mainHandler.post {
                listener.onSliceCompleted(sliceMap)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error closing slice file", e)
            listener.onError("Error closing slice file: ${e.message}")
        } finally {
            currentSliceOutputStream = null
            currentSliceFile = null
        }
    }

    private fun writeWavHeader(
        wavFile: File,
        totalAudioLen: Long,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int
    ) {
        val totalDataLen = totalAudioLen + 36
        val byteRate = (sampleRate * channels * bitsPerSample / 8).toLong()
        val blockAlign = (channels * bitsPerSample / 8)

        val header = ByteArray(44)
        val raf = RandomAccessFile(wavFile, "rw")
        try {
            header[0] = 'R'.code.toByte() // RIFF/WAVE header
            header[1] = 'I'.code.toByte()
            header[2] = 'F'.code.toByte()
            header[3] = 'F'.code.toByte()
            header[4] = (totalDataLen and 0xffL).toByte()
            header[5] = (totalDataLen shr 8 and 0xffL).toByte()
            header[6] = (totalDataLen shr 16 and 0xffL).toByte()
            header[7] = (totalDataLen shr 24 and 0xffL).toByte()
            header[8] = 'W'.code.toByte()
            header[9] = 'A'.code.toByte()
            header[10] = 'V'.code.toByte()
            header[11] = 'E'.code.toByte()
            header[12] = 'f'.code.toByte() // 'fmt ' chunk
            header[13] = 'm'.code.toByte()
            header[14] = 't'.code.toByte()
            header[15] = ' '.code.toByte()
            header[16] = 16 // 4 bytes: size of 'fmt ' chunk
            header[17] = 0
            header[18] = 0
            header[19] = 0
            header[20] = 1 // format = 1 (PCM)
            header[21] = 0
            header[22] = channels.toByte()
            header[23] = 0
            header[24] = (sampleRate and 0xff).toByte()
            header[25] = (sampleRate shr 8 and 0xff).toByte()
            header[26] = (sampleRate shr 16 and 0xff).toByte()
            header[27] = (sampleRate shr 24 and 0xff).toByte()
            header[28] = (byteRate and 0xffL).toByte()
            header[29] = (byteRate shr 8 and 0xffL).toByte()
            header[30] = (byteRate shr 16 and 0xffL).toByte()
            header[31] = (byteRate shr 24 and 0xffL).toByte()
            header[32] = blockAlign.toByte()
            header[33] = 0
            header[34] = bitsPerSample.toByte()
            header[35] = 0
            header[36] = 'd'.code.toByte()
            header[37] = 'a'.code.toByte()
            header[38] = 't'.code.toByte()
            header[39] = 'a'.code.toByte()
            header[40] = (totalAudioLen and 0xffL).toByte()
            header[41] = (totalAudioLen shr 8 and 0xffL).toByte()
            header[42] = (totalAudioLen shr 16 and 0xffL).toByte()
            header[43] = (totalAudioLen shr 24 and 0xffL).toByte()

            raf.seek(0)
            raf.write(header)
        } finally {
            raf.close()
        }
    }
}
