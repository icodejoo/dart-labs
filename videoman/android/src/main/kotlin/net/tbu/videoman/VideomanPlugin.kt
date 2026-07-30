package net.tbu.videoman

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** VideomanPlugin: platform version + system picture-in-picture. */
class VideomanPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "videoman")
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
            else -> result.notImplemented()
        }
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
        activity = binding.activity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
