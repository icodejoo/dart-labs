package com.icodejoo.mova

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.ComponentCallbacks
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** Delays (ms) for re-reading the PiP mode after a configuration change. */
private val PIP_RECHECK_MS = longArrayOf(50, 150, 400, 1000)

/** MovaPlugin: platform version + system picture-in-picture. */
class MovaPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    /** Last PiP state pushed to Dart, so only real changes are sent. */
    private var lastPip = false

    /**
     * Entering/leaving PiP resizes the window, which delivers a configuration
     * change to the activity even when the host handles it via configChanges.
     * We re-read the real PiP mode there and push it to Dart.
     */
    private val pipWatcher =
        object : ComponentCallbacks {
            override fun onConfigurationChanged(newConfig: Configuration) {
                pushPipState()
                // On exit the configuration change arrives before the PiP flag
                // flips, so re-check a few times; pushPipState de-duplicates.
                for (delay in PIP_RECHECK_MS) mainHandler.postDelayed({ pushPipState() }, delay)
            }

            override fun onLowMemory() {}
        }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "mova")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
            "isPipSupported" -> result.success(isPipSupported())
            "enterPip" -> result.success(enterPip(call.argument<Int>("width"), call.argument<Int>("height")))
            "getSystemVolume" -> result.success(getSystemVolume())
            "setSystemVolume" -> result.success(setSystemVolume(call.argument<Double>("percent") ?: 0.0))
            else -> result.notImplemented()
        }
    }

    /** Reads the media-stream volume as a 0..100 percentage, or null if unavailable. */
    private fun getSystemVolume(): Double? {
        val am = audioManager() ?: return null
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return null
        val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
        return cur.toDouble() / max.toDouble() * 100.0
    }

    /** Sets the media-stream volume from a 0..100 percentage; returns success. */
    private fun setSystemVolume(percent: Double): Boolean {
        val am = audioManager() ?: return false
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return false
        val index = Math.round(percent.coerceIn(0.0, 100.0) / 100.0 * max).toInt()
        return try {
            am.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
            true
        } catch (e: SecurityException) {
            false
        }
    }

    /** The AudioManager from the current activity/application context. */
    private fun audioManager(): AudioManager? {
        val ctx = activity?.applicationContext ?: return null
        return ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    }

    /** Reads the activity's real PiP mode and pushes it to Dart when it changed. */
    private fun pushPipState() {
        val a = activity ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val now = a.isInPictureInPictureMode
        if (now == lastPip) return
        lastPip = now
        channel.invokeMethod("pipChanged", now)
    }

    /** True when the OS + device support PiP (API 26+ with the PiP feature). */
    private fun isPipSupported(): Boolean {
        val a = activity ?: return false
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            a.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    /** Enters PiP with a clamped aspect ratio; returns whether it succeeded. */
    private fun enterPip(
        width: Int?,
        height: Int?
    ): Boolean {
        val a = activity ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !isPipSupported()) return false
        return try {
            val builder = PictureInPictureParams.Builder()
            if (width != null && height != null && width > 0 && height > 0) {
                // Android requires the aspect ratio within (0.418, 2.39).
                val ratio = (width.toFloat() / height.toFloat()).coerceIn(0.42f, 2.39f)
                builder.setAspectRatio(Rational((ratio * 1000).toInt(), 1000))
            }
            a.enterPictureInPictureMode(builder.build())
        } catch (e: Exception) {
            false
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attach(binding.activity)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attach(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detach()
    }

    override fun onDetachedFromActivity() {
        detach()
    }

    /** Binds to [a] and starts watching its PiP mode. */
    private fun attach(a: Activity) {
        detach()
        activity = a
        a.registerComponentCallbacks(pipWatcher)
    }

    /** Stops watching and drops the activity reference. */
    private fun detach() {
        mainHandler.removeCallbacksAndMessages(null)
        activity?.unregisterComponentCallbacks(pipWatcher)
        activity = null
    }
}
