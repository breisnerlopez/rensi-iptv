package info.breisner.rensi.iptv

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.speech.RecognizerIntent
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Rational
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val pipChannel = "info.breisner.rensi.iptv/pip"
    private val pipEventsChannel = "info.breisner.rensi.iptv/pip_events"
    private val voiceChannel = "info.breisner.rensi.iptv/voice"
    private val hwVolumeChannel = "info.breisner.rensi.iptv/hwvolume"
    private val callStateChannel = "info.breisner.rensi.iptv/callstate"

    // While casting, the phone's hardware VOLUME_UP/DOWN keys must control the
    // TV's cast volume, not the phone's. Dart flips [castingActive] via the
    // hwvolume channel; [dispatchKeyEvent] consumes the keys and forwards each
    // press to Dart only while it is true. When false, the keys fall through to
    // the system unchanged (normal phone volume).
    private var hwVolumeMethodChannel: MethodChannel? = null
    private var castingActive = false

    // The system voice overlay is a foreign activity: we hand its result back
    // to Dart through a saved MethodChannel.Result, completed exactly once in
    // onActivityResult. Guarded so a second launch while one is pending can't
    // orphan the first Result.
    private val voiceRequestCode = 0x5645 // 'VE'
    private var pendingVoiceResult: MethodChannel.Result? = null

    private var pipEventSink: EventChannel.EventSink? = null
    // Last aspect ratio requested by Dart, used by auto-PiP on user-leave.
    private var lastAspectRatio: Rational = Rational(16, 9)
    // Whether Dart wants us to enter PiP automatically on home/back gesture.
    private var autoPipEnabled: Boolean = false

    // Phone call-state bridge (feature: pause the cast on an incoming call). Dart
    // listens on [callStateChannel] ONLY while casting AND the toggle is on; on
    // onListen we register a telephony listener that emits "ringing"/"offhook"/
    // "idle", and on onCancel we UNREGISTER it (so we never hold the listener —
    // nor need READ_PHONE_STATE — when the feature is inactive). Registration is
    // wrapped in try/catch: without the permission it can throw SecurityException
    // or simply deliver nothing; either way we no-op and never crash.
    private var callStateSink: EventChannel.EventSink? = null
    // API < 31 path (legacy PhoneStateListener via TelephonyManager.listen).
    private var phoneStateListener: PhoneStateListener? = null
    // API >= 31 path (TelephonyCallback via registerTelephonyCallback). Kept as
    // Any? so the class still loads on older API levels (the type is 31+).
    private var telephonyCallback: Any? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(isPipSupported())
                    "isTelevision" -> result.success(isTelevision())
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isVoiceAvailable" -> result.success(isVoiceAvailable())
                    "startVoiceSearch" -> startVoiceSearch(
                        call.argument<String>("locale"),
                        call.argument<String>("prompt"),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }

        hwVolumeMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, hwVolumeChannel).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "setCastingActive" -> {
                            castingActive = (call.arguments as? Boolean) ?: false
                            result.success(null)
                        }
                        "ping" -> result.success(null)
                        else -> result.notImplemented()
                    }
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, callStateChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    callStateSink = events
                    registerCallStateListener()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterCallStateListener()
                    callStateSink = null
                }
            })
    }

    // Maps an Android CALL_STATE_* constant to the string Dart expects and pushes
    // it to the sink (on the main thread — EventSink is not thread-safe).
    private fun emitCallState(state: Int) {
        val name = when (state) {
            TelephonyManager.CALL_STATE_RINGING -> "ringing"
            TelephonyManager.CALL_STATE_OFFHOOK -> "offhook"
            else -> "idle"
        }
        runOnUiThread { callStateSink?.success(name) }
    }

    // Registers the phone-state listener behind the API-level split. Best-effort:
    // if READ_PHONE_STATE isn't granted the platform can throw SecurityException
    // (or just never deliver) — we catch and no-op so the feature degrades to
    // "never pauses" instead of crashing.
    private fun registerCallStateListener() {
        val tm = getSystemService(TELEPHONY_SERVICE) as? TelephonyManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) = emitCallState(state)
                }
                telephonyCallback = cb
                tm.registerTelephonyCallback(mainExecutor, cb)
            } else {
                val listener = object : PhoneStateListener() {
                    @Deprecated("Deprecated in API 31; used only on API < 31")
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) =
                        emitCallState(state)
                }
                phoneStateListener = listener
                @Suppress("DEPRECATION")
                tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
            }
        } catch (_: SecurityException) {
            // No READ_PHONE_STATE → silently give up (feature just won't pause).
        } catch (_: Exception) {
            // Any other platform hiccup → no-op, never crash the activity.
        }
    }

    // Releases the listener so we don't hold it (nor the permission requirement)
    // once Dart stops listening (cast ended / toggle off). Idempotent.
    private fun unregisterCallStateListener() {
        val tm = getSystemService(TELEPHONY_SERVICE) as? TelephonyManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (telephonyCallback as? TelephonyCallback)?.let { tm?.unregisterTelephonyCallback(it) }
            } else {
                phoneStateListener?.let {
                    @Suppress("DEPRECATION")
                    tm?.listen(it, PhoneStateListener.LISTEN_NONE)
                }
            }
        } catch (_: Exception) {
            // Ignore: unregistering a listener that was never fully registered.
        }
        telephonyCallback = null
        phoneStateListener = null
    }

    // While casting, hijack the hardware VOLUME_UP/DOWN keys: forward each press
    // to Dart (which nudges the TV's cast volume) and CONSUME the event so the
    // system volume UI / phone volume never changes. VOLUME_MUTE and every other
    // key — and all keys when not casting — fall through to super unchanged.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (castingActive &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                val up = event.keyCode == KeyEvent.KEYCODE_VOLUME_UP
                runOnUiThread {
                    hwVolumeMethodChannel?.invokeMethod(
                        "onVolumeKey",
                        mapOf("dir" to if (up) "up" else "down"),
                    )
                }
            }
            // Consume both DOWN and UP so the OS never applies phone volume.
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    // True when a recognizer that can satisfy ACTION_RECOGNIZE_SPEECH is
    // installed. Many TV boxes have none — Dart hides the mic when this is false.
    private fun isVoiceAvailable(): Boolean {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        return intent.resolveActivity(packageManager) != null
    }

    // Launches the system voice overlay and stores [result] to be completed once
    // by onActivityResult. Uses FREE_FORM (dictation, not command grammar). No
    // RECORD_AUDIO permission is needed: the overlay owns the mic.
    private fun startVoiceSearch(
        locale: String?,
        prompt: String?,
        result: MethodChannel.Result,
    ) {
        // Only one session at a time. If one is already pending, decline the
        // newcomer with null rather than drop the in-flight Result on the floor.
        if (pendingVoiceResult != null) {
            result.success(null)
            return
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            if (!prompt.isNullOrBlank()) {
                putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
            }
            if (!locale.isNullOrBlank()) {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            }
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.success(null)
            return
        }
        pendingVoiceResult = result
        try {
            startActivityForResult(intent, voiceRequestCode)
        } catch (_: Exception) {
            pendingVoiceResult = null
            result.success(null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != voiceRequestCode) return
        val pending = pendingVoiceResult ?: return
        pendingVoiceResult = null
        if (resultCode == Activity.RESULT_OK && data != null) {
            val matches =
                data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            pending.success(matches?.firstOrNull())
        } else {
            // Cancelled, no match, or error → null so Dart leaves the query be.
            pending.success(null)
        }
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

    // True on real Android TV / leanback devices. Used by Dart as the primary
    // (platform-level) TV signal instead of guessing from screen width.
    private fun isTelevision(): Boolean {
        val uiModeManager = getSystemService(android.content.Context.UI_MODE_SERVICE)
            as? android.app.UiModeManager
        if (uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) {
            return true
        }
        return packageManager.hasSystemFeature(
            android.content.pm.PackageManager.FEATURE_LEANBACK
        ) || packageManager.hasSystemFeature("android.hardware.type.television")
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
