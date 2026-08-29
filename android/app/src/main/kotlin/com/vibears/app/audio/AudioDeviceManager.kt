package com.vibears.app.audio

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class AudioDeviceManager(private val context: Context) {
    private val TAG = "AudioDeviceManager"
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    /** Log to logcat AND forward to the in-app LogCollector. */
    private fun nl(tag: String, message: String) {
        Log.d(tag, message)
        VibeAudioPlugin.reportNativeLog(tag, message)
    }

    fun getAvailableInputDevices(): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
            nl(TAG, "Enumerating input devices: ${devices.size} found")
            for (device in devices) {
                val deviceMap = mutableMapOf<String, Any>()
                deviceMap["id"] = device.id.toString()
                deviceMap["name"] = if (device.productName.isNotEmpty()) {
                    device.productName.toString()
                } else {
                    getDeviceTypeName(device.type) + " (" + device.id + ")"
                }
                deviceMap["type"] = getDeviceTypeName(device.type)
                
                // Sample rates supported
                val sampleRates = if (device.sampleRates.isNotEmpty()) {
                    device.sampleRates.toList()
                } else {
                    listOf(16000, 44100, 48000)
                }
                deviceMap["sampleRates"] = sampleRates

                // Channel counts supported
                val channelCounts = if (device.channelCounts.isNotEmpty()) {
                    device.channelCounts.toList()
                } else {
                    listOf(1, 2)
                }
                deviceMap["channelCounts"] = channelCounts

                // Encodings supported
                val encodings = if (device.encodings.isNotEmpty()) {
                    device.encodings.map { getEncodingName(it) }
                } else {
                    listOf("PCM_16BIT")
                }
                deviceMap["encodings"] = encodings

                nl(
                    TAG,
                    "Device #${device.id}: type=${getDeviceTypeName(device.type)} name=${deviceMap["name"]} " +
                        "rates=$sampleRates channels=$channelCounts enc=$encodings"
                )
                
                result.add(deviceMap)
            }
        } else {
            result.add(
                mapOf(
                    "id" to "0",
                    "name" to "默认麦克风 (Default Mic)",
                    "type" to "builtin_mic",
                    "sampleRates" to listOf(16000, 44100, 48000),
                    "channelCounts" to listOf(1, 2),
                    "encodings" to listOf("PCM_16BIT")
                )
            )
        }
        
        return result
    }

    fun isScoDevice(deviceId: Int?): Boolean {
        if (deviceId == null) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val target = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS).find { it.id == deviceId }
        val isSco = target?.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        nl(TAG, "isScoDevice($deviceId) = $isSco (target=$target)")
        return isSco
    }

    /**
     * Activates the Bluetooth SCO/communication route BEFORE an AudioRecord is
     * created and waits for the SCO channel to actually connect. SCO
     * activation is asynchronous: startBluetoothSco() returns immediately and
     * the hardware path becomes available only after the
     * ACTION_SCO_AUDIO_STATE_UPDATED broadcast reports CONNECTED. On Android
     * 11+ the modern setCommunicationDevice API is used instead.
     *
     * @return true when the SCO route is ready (or no SCO device was selected).
     */
    fun prepareDeviceRoute(deviceId: Int?): Boolean {
        if (!isScoDevice(deviceId)) return true
        val target = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS).find { it.id == deviceId }
        } else null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Modern API: synchronous-ish communication device selection.
            return try {
                if (target == null) {
                    nl(TAG, "SCO device $deviceId no longer present")
                    return false
                }
                audioManager.setCommunicationDevice(target)
                nl(TAG, "setCommunicationDevice(SCO) OK for $deviceId")
                // Give the framework a moment to route before AudioRecord init.
                Thread.sleep(300)
                true
            } catch (e: Exception) {
                nl(TAG, "setCommunicationDevice failed: ${e.message}")
                false
            }
        }

        // Legacy path: startBluetoothSco + wait for the CONNECTED broadcast.
        val latch = CountDownLatch(1)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                if (intent?.action == AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED) {
                    val state = intent.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, -1)
                    nl(TAG, "SCO_AUDIO_STATE_UPDATED state=$state (0=disconnected,1=connecting,2=connected)")
                    if (state == AudioManager.SCO_AUDIO_STATE_CONNECTED) {
                        latch.countDown()
                    }
                }
            }
        }
        val filter = IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.registerReceiver(receiver, filter)
            }
        } catch (e: Exception) {
            nl(TAG, "Failed to register SCO receiver: ${e.message}")
        }

        try {
            audioManager.startBluetoothSco()
            nl(TAG, "startBluetoothSco() called, waiting for CONNECTED...")
        } catch (e: Exception) {
            nl(TAG, "startBluetoothSco failed: ${e.message}")
        }

        val connected = try {
            latch.await(4, TimeUnit.SECONDS)
        } catch (e: InterruptedException) {
            nl(TAG, "Interrupted while waiting for SCO: ${e.message}")
            false
        }
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Exception) {}
        nl(TAG, "SCO route ready: $connected")
        return connected
    }

    fun stopBluetoothRoute() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audioManager.clearCommunicationDevice()
            } else {
                if (audioManager.isBluetoothScoOn) {
                    audioManager.stopBluetoothSco()
                    audioManager.isBluetoothScoOn = false
                }
            }
            nl(TAG, "Bluetooth route stopped")
        } catch (e: Exception) {
            nl(TAG, "Error stopping Bluetooth route: ${e.message}")
        }
    }

    /**
     * SCO capture requires the VOICE_COMMUNICATION audio source so the
     * hardware routes the microphone through the HFP/SCO path.
     */
    fun resolveAudioSource(deviceId: Int?): Int {
        val source = if (isScoDevice(deviceId)) {
            MediaRecorder.AudioSource.VOICE_COMMUNICATION
        } else {
            MediaRecorder.AudioSource.MIC
        }
        nl(TAG, "resolveAudioSource($deviceId) = $source")
        return source
    }

    fun applyPreferredDevice(audioRecord: AudioRecord, deviceId: Int?): Boolean {
        if (deviceId == null) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val target = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS).find { it.id == deviceId }
            if (target != null) {
                val success = audioRecord.setPreferredDevice(target)
                nl(TAG, "setPreferredDevice ($deviceId) -> $success")
                return success
            }
        }
        return false
    }

    private fun getDeviceTypeName(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "builtin_mic"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired_headset"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth_sco"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth_a2dp"
            AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> "usb_audio"
            AudioDeviceInfo.TYPE_LINE_ANALOG, AudioDeviceInfo.TYPE_LINE_DIGITAL -> "aux_line"
            AudioDeviceInfo.TYPE_TELEPHONY -> "telephony"
            else -> "unknown"
        }
    }

    private fun getEncodingName(encoding: Int): String {
        return when (encoding) {
            android.media.AudioFormat.ENCODING_PCM_16BIT -> "PCM_16BIT"
            android.media.AudioFormat.ENCODING_PCM_8BIT -> "PCM_8BIT"
            android.media.AudioFormat.ENCODING_PCM_FLOAT -> "PCM_FLOAT"
            else -> "ENCODING_$encoding"
        }
    }
}
