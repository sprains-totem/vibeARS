package com.vibears.app.audio

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
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
    fun onAudioFrame(pcmData: ByteArray, amplitude: Double, db: Double)
    fun onSliceCompleted(sliceInfo: Map<String, Any>)
    fun onError(errorMessage: String)
}

class AudioPipeline(
    private val context: Context,
    private val sampleRate: Int = 48000,
    private val channelCount: Int = 2,
    private val format: String = "wav", // wav, aac, etc.
    private val preferredDeviceId: Int? = null,
    private val slicerEnabled: Boolean = true,
    private val sliceDurationMs: Long = 5 * 60 * 1000L, // 5 minutes default
    private val outputDir: String,
    private val listener: AudioPipelineListener
) {
    private val TAG = "AudioPipeline"
    private val isRecording = AtomicBoolean(false)
    private val isPaused = AtomicBoolean(false)
    private var recordThread: Thread? = null
    private var audioRecord: AudioRecord? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val audioDeviceManager = AudioDeviceManager(context)

    // The native capture layer only emits raw PCM; recordings are ALWAYS
    // stored as standard WAV (with a proper RIFF header) regardless of the
    // requested format, so every file is playable and discoverable.
    private val isWavOutput: Boolean = true

    // Current slice file tracking
    private var currentSliceFile: File? = null
    private var currentSliceOutputStream: FileOutputStream? = null
    private var currentSlicePcmBytesWritten: Long = 0L
    private var currentSliceStartTime: Long = 0L
    private var sliceSequence: Int = 1
    private val sessionId: String = UUID.randomUUID().toString()

    fun start(): Boolean {
        if (isRecording.get()) return true

        // Validate that the output directory is actually writable before
        // starting the capture loop, otherwise the session would silently
        // produce no files at all.
        try {
            val dir = File(outputDir)
            if (!dir.exists() && !dir.mkdirs()) {
                listener.onError("Failed to create output directory: $outputDir")
                return false
            }
            if (!dir.canWrite()) {
                listener.onError("Output directory is not writable: $outputDir")
                return false
            }
            val probe = File(dir, ".vibears_write_probe")
            if (!probe.createNewFile()) {
                listener.onError("Output directory is not writable: $outputDir")
                return false
            }
            probe.delete()
        } catch (e: Exception) {
            listener.onError("Output directory is not writable: ${e.message}")
            return false
        }

        val channelConfig = if (channelCount == 1) {
            AudioFormat.CHANNEL_IN_MONO
        } else {
            AudioFormat.CHANNEL_IN_STEREO
        }
        val audioEncoding = AudioFormat.ENCODING_PCM_16BIT

        val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioEncoding)
        if (minBufferSize <= 0) {
            listener.onError("Sample rate $sampleRate is not supported by this device")
            return false
        }
        val bufferSize = (minBufferSize * 2).coerceAtLeast(sampleRate * channelCount * 2 / 10) // 100ms buffer

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                channelConfig,
                audioEncoding,
                bufferSize
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                listener.onError("AudioRecord failed to initialize")
                return false
            }

            // Apply preferred hardware microphone if specified
            if (preferredDeviceId != null) {
                audioDeviceManager.applyPreferredDevice(audioRecord!!, preferredDeviceId)
            }

            isRecording.set(true)
            isPaused.set(false)
            audioRecord?.startRecording()

            // Initialize the first slice file
            if (!openNextSlice()) {
                isRecording.set(false)
                listener.onError("Failed to create initial slice file")
                return false
            }

            recordThread = Thread({ recordLoop(bufferSize) }, "AudioCaptureThread")
            recordThread?.priority = Thread.MAX_PRIORITY
            recordThread?.start()
            Log.d(TAG, "Audio recording pipeline started successfully")
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

        // Close and finalize the last slice
        closeCurrentSlice()
        Log.d(TAG, "Audio recording pipeline stopped")
    }

    private fun recordLoop(bufferSize: Int) {
        val audioBuffer = ShortArray(bufferSize / 2)
        val bytesPerSample = 2 // 16-bit
        val bytesPerSecond = sampleRate * channelCount * bytesPerSample
        val maxBytesPerSlice = (sliceDurationMs * bytesPerSecond / 1000L)

        while (isRecording.get()) {
            if (isPaused.get()) {
                try {
                    Thread.sleep(50)
                } catch (_: InterruptedException) {}
                continue
            }

            val readCount = audioRecord?.read(audioBuffer, 0, audioBuffer.size) ?: 0
            if (readCount > 0) {
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

                // Dispatch PCM frame for real-time streaming & UI visualization
                mainHandler.post {
                    listener.onAudioFrame(pcmBytes, normalizedAmplitude, db)
                }

                // 3. Write to the current slice file
                try {
                    currentSliceOutputStream?.write(pcmBytes)
                    currentSlicePcmBytesWritten += pcmBytes.size

                    // 4. Check if slice duration reached -> Seamless Rollover
                    if (slicerEnabled && currentSlicePcmBytesWritten >= maxBytesPerSlice) {
                        closeCurrentSlice()
                        if (!openNextSlice()) {
                            // Failed to open the next slice: stop the session
                            // rather than silently dropping all audio.
                            listener.onError("Failed to create next slice file, recording stopped")
                            isRecording.set(false)
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error writing audio slice bytes", e)
                    listener.onError("Error writing audio slice: ${e.message}")
                    isRecording.set(false)
                }
            }
        }
    }

    private fun openNextSlice(): Boolean {
        return try {
            val dir = File(outputDir)
            if (!dir.exists()) {
                dir.mkdirs()
            }
            val timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            val extension = if (isWavOutput) "wav" else "pcm"
            val fileName = "vibe_slice_${timeStamp}_part${sliceSequence}.$extension"
            val file = File(dir, fileName)

            val fos = FileOutputStream(file)
            if (isWavOutput) {
                // Write 44-byte empty placeholder header for WAV
                val emptyHeader = ByteArray(44)
                fos.write(emptyHeader)
            }

            currentSliceFile = file
            currentSliceOutputStream = fos
            currentSlicePcmBytesWritten = 0L
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
        val fos = currentSliceOutputStream ?: return

        try {
            fos.flush()
            fos.close()

            val actualDurationMs = if (sampleRate > 0 && channelCount > 0) {
                (currentSlicePcmBytesWritten * 1000L) / (sampleRate * channelCount * 2)
            } else {
                System.currentTimeMillis() - currentSliceStartTime
            }

            if (isWavOutput) {
                // Update WAV header with exact total length
                writeWavHeader(file, currentSlicePcmBytesWritten, sampleRate, channelCount, 16)
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
