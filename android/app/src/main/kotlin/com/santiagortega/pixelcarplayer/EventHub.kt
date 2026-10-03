package com.santiagortega.pixelcarplayer

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel

const val TAG = "PCP"

/**
 * Single event stream towards Flutter (`EventChannel("pcp/events")`).
 *
 * Any thread may [post]; delivery always happens on the main thread. When no Dart listener is
 * attached events are dropped (except the latest `transmitterStatus`, which is replayed to a new
 * listener so the phone UI is immediately in sync).
 */
object EventHub : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null // main thread only
    @Volatile private var lastStatus: Map<String, Any?>? = null

    fun post(event: Map<String, Any?>) {
        if (event["type"] == "transmitterStatus") lastStatus = event
        main.post {
            try {
                sink?.success(event)
            } catch (e: Exception) {
                Log.w(TAG, "EventHub delivery failed", e)
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        lastStatus?.let { status -> main.post { sink?.success(status) } }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /** Main thread only (e.g. from Activity.onDestroy / engine cleanup). */
    fun detach() {
        sink = null
    }
}
