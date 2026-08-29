package com.vibears.app.audio

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.AudioRecord
import android.os.Build
import android.util.Log

class AudioDeviceManager(private val context: Context) {
    private val TAG = "AudioDeviceManager"
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    fun getAvailableInputDevices(): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
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
                
                result.add(deviceMap)
            }
        } else {
            // Fallback for older APIs
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

    fun applyPreferredDevice(audioRecord: AudioRecord, deviceId: Int?): Boolean {
        if (deviceId == null) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
            val target = devices.find { it.id == deviceId }
            if (target != null) {
                // For Bluetooth SCO, the SCO channel must be activated *before*
                // AudioRecord is created/routed, otherwise the hardware path is
                // not available for capture.
                if (target.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) {
                    startBluetoothSco()
                }
                val success = audioRecord.setPreferredDevice(target)
                Log.d(TAG, "setPreferredDevice ($deviceId): $success")
                return success
            }
        }
        return false
    }

    fun startBluetoothSco() {
        try {
            audioManager.startBluetoothSco()
            audioManager.isBluetoothScoOn = true
            Log.d(TAG, "Bluetooth SCO started")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting Bluetooth SCO: ${e.message}")
        }
    }

    fun stopBluetoothSco() {
        try {
            if (audioManager.isBluetoothScoOn) {
                audioManager.stopBluetoothSco()
                audioManager.isBluetoothScoOn = false
                Log.d(TAG, "Bluetooth SCO stopped")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping Bluetooth SCO: ${e.message}")
        }
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
