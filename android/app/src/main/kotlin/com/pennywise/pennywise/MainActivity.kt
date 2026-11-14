package com.pennywise.pennywise

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (instead of FlutterActivity) is required for the
// fingerprint / face prompt used by App lock.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.pennywise.pennywise/shortcuts"
    private var initialIntentData: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialAction" -> {
                    val data = initialIntentData
                    initialIntentData = null
                    result.success(data)
                }
                else -> result.notImplemented()
            }
        }

        // Check if intent was received before flutter engine was configured
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val processText = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()

        val map = mutableMapOf<String, String>()
        if (action != null) {
            map["action"] = action
        }
        if (processText != null && processText.isNotEmpty()) {
            map["text"] = processText
        }

        if (map.isNotEmpty()) {
            val engine = flutterEngine
            if (engine != null) {
                MethodChannel(engine.dartExecutor.binaryMessenger, channelName).invokeMethod("onActionReceived", map)
            } else {
                initialIntentData = map
            }
        }
    }
}
