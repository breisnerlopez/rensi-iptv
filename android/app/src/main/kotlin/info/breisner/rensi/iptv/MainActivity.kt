package info.breisner.rensi.iptv

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val pipChannel = "info.breisner.rensi.iptv/pip"
    private val pipEventsChannel = "info.breisner.rensi.iptv/pip_events"

    private var pipEventSink: EventChannel.EventSink? = null
    // Last aspect ratio requested by Dart, used by auto-PiP on user-leave.
    private var lastAspectRatio: Rational = Rational(16, 9)
    // Whether Dart wants us to enter PiP automatically on home/back gesture.
    private var autoPipEnabled: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(isPipSupported())
                    "setAutoEnter" -> {
                        autoPipEnabled = (call.arguments as? Boolean) ?: false
                        result.success(null)
                    }
                    "updateAspectRatio" -> {
                        val w = (call.argument<Int>("width") ?: 16).coerceAtLeast(1)
                        val h = (call.argument<Int>("height") ?: 9).coerceAtLeast(1)
                        lastAspectRatio = clampAspect(Rational(w, h))
                        result.success(null)
                    }
                    "enterPip" -> {
                        val w = (call.argument<Int>("width") ?: lastAspectRatio.numerator)
                            .coerceAtLeast(1)
                        val h = (call.argument<Int>("height") ?: lastAspectRatio.denominator)
                            .coerceAtLeast(1)
                        result.success(enterPip(clampAspect(Rational(w, h))))
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, pipEventsChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    pipEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    pipEventSink = null
                }
            })
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPipEnabled && isPipSupported() && !isInPictureInPictureMode) {
            enterPip(lastAspectRatio)
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipEventSink?.success(isInPictureInPictureMode)
    }

    private fun isPipSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return packageManager.hasSystemFeature(
            android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE
        )
    }

    private fun enterPip(aspect: Rational): Boolean {
        if (!isPipSupported()) return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(aspect)
                    .build()
                enterPictureInPictureMode(params)
            } else {
                false
            }
        } catch (_: IllegalStateException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    // Android requires the PiP aspect ratio to be between ~0.418 and ~2.39.
    private fun clampAspect(r: Rational): Rational {
        val value = r.toFloat()
        return when {
            value < 0.42f -> Rational(42, 100)
            value > 2.39f -> Rational(239, 100)
            else -> r
        }
    }
}
