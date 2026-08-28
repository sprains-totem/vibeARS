package com.vibears.app.audio

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class VibeAudioPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private val TAG = "VibeAudioPlugin"
    private val METHOD_CHANNEL_NAME = "com.vibears.app/audio_engine"
    private val AUDIO_STREAM_CHANNEL_NAME = "com.vibears.app/audio_stream"
    private val SLICE_STREAM_CHANNEL_NAME = "com.vibears.app/slice_stream"

    private lateinit var methodChannel: MethodChannel
    private lateinit var audioEventChannel: EventChannel
    private lateinit var sliceEventChannel: EventChannel

    private var context: Context? = null
    private var activity: Activity? = null
    private var audioDeviceManager: AudioDeviceManager? = null

    private var audioSink: EventChannel.EventSink? = null
    private var sliceSink: EventChannel.EventSink? = null

    private var audioCaptureService: AudioCaptureService? = null
    private var isServiceBound = false

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val binder = service as? AudioCaptureService.LocalBinder
            audioCaptureService = binder?.getService()
            isServiceBound = true
            Log.d(TAG, "AudioCaptureService bound")
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            audioCaptureService = null
            isServiceBound = false
            Log.d(TAG, "AudioCaptureService unbound")
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        audioDeviceManager = AudioDeviceManager(binding.applicationContext)

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)

        audioEventChannel = EventChannel(binding.binaryMessenger, AUDIO_STREAM_CHANNEL_NAME)
        audioEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                audioSink = events
            }

            override fun onCancel(arguments: Any?) {
                audioSink = null
            }
        })

        sliceEventChannel = EventChannel(binding.binaryMessenger, SLICE_STREAM_CHANNEL_NAME)
        sliceEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sliceSink = events
            }

            override fun onCancel(arguments: Any?) {
                sliceSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        audioEventChannel.setStreamHandler(null)
        sliceEventChannel.setStreamHandler(null)
        unbindCaptureService()
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAudioDevices" -> {
                try {
                    val devices = audioDeviceManager?.getAvailableInputDevices() ?: emptyList()
                    result.success(devices)
                } catch (e: Exception) {
                    result.error("DEVICE_ERROR", e.message, null)
                }
            }
            "startRecording" -> {
                val sampleRate = call.argument<Int>("sampleRate") ?: 48000
                val channelCount = call.argument<Int>("channelCount") ?: 2
                val format = call.argument<String>("format") ?: "wav"
                val preferredDeviceId = call.argument<Int>("preferredDeviceId")
                val slicerEnabled = call.argument<Boolean>("slicerEnabled") ?: true
                val sliceDurationMinutes = call.argument<Int>("sliceDurationMinutes") ?: 5
                val outputDir = call.argument<String>("outputDir") ?: (context?.filesDir?.absolutePath ?: "")

                startServiceAndRecord(
                    sampleRate,
                    channelCount,
                    format,
                    preferredDeviceId,
                    slicerEnabled,
                    sliceDurationMinutes * 60 * 1000L,
                    outputDir,
                    result
                )
            }
            "pauseRecording" -> {
                audioCaptureService?.pauseRecording()
                result.success(true)
            }
            "resumeRecording" -> {
                audioCaptureService?.resumeRecording()
                result.success(true)
            }
            "stopRecording" -> {
                audioCaptureService?.stopRecording()
                unbindCaptureService()
                result.success(true)
            }
            "requestIgnoreBatteryOptimizations" -> {
                requestBatteryOptimizations()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun startServiceAndRecord(
        sampleRate: Int,
        channelCount: Int,
        format: String,
        preferredDeviceId: Int?,
        slicerEnabled: Boolean,
        sliceDurationMs: Long,
        outputDir: String,
        result: MethodChannel.Result
    ) {
        val ctx = context ?: run {
            result.error("NO_CONTEXT", "Context is null", null)
            return
        }

        val serviceIntent = Intent(ctx, AudioCaptureService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ctx.startForegroundService(serviceIntent)
        } else {
            ctx.startService(serviceIntent)
        }

        ctx.bindService(serviceIntent, object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
                val binder = service as? AudioCaptureService.LocalBinder
                audioCaptureService = binder?.getService()
                isServiceBound = true

                audioCaptureService?.startRecording(
                    sampleRate = sampleRate,
                    channelCount = channelCount,
                    format = format,
                    preferredDeviceId = preferredDeviceId,
                    slicerEnabled = slicerEnabled,
                    sliceDurationMs = sliceDurationMs,
                    outputDir = outputDir,
                    listener = object : AudioPipelineListener {
                        override fun onAudioFrame(pcmData: ByteArray, amplitude: Double, db: Double) {
                            activity?.runOnUiThread {
                                audioSink?.success(
                                    mapOf(
                                        "amplitude" to amplitude,
                                        "db" to db,
                                        "pcm" to pcmData
                                    )
                                )
                            }
                        }

                        override fun onSliceCompleted(sliceInfo: Map<String, Any>) {
                            activity?.runOnUiThread {
                                sliceSink?.success(sliceInfo)
                            }
                        }

                        override fun onError(errorMessage: String) {
                            Log.e(TAG, "Pipeline error: $errorMessage")
                        }
                    }
                )
                result.success(true)
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                audioCaptureService = null
                isServiceBound = false
            }
        }, Context.BIND_AUTO_CREATE)
    }

    private fun unbindCaptureService() {
        if (isServiceBound && context != null) {
            try {
                context?.unbindService(serviceConnection)
            } catch (_: Exception) {}
            isServiceBound = false
        }
    }

    private fun requestBatteryOptimizations() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = context?.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val pkg = context?.packageName
            if (pm != null && pkg != null && !pm.isIgnoringBatteryOptimizations(pkg)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$pkg")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context?.startActivity(intent)
            }
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
