package com.example.etl_manager_app  // apna package name same rakho

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity  // ✅ Change karo

class MainActivity : FlutterFragmentActivity() {  // ✅ FlutterActivity → FlutterFragmentActivity

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    /**
     * Create the notification channel our pushes are posted to.
     *
     * WHY THIS EXISTS
     * Nothing used to create this channel — it was only *named* in
     * AndroidManifest.xml (`default_notification_channel_id`) and in the
     * backend payload (`android.notification.channel_id`). A comment in
     * backend_fastapi/app/services/notice_service.py even claimed the Flutter
     * app created it; it did not.
     *
     * On Android 8+ a channel the app never created is auto-created by the
     * Firebase SDK at IMPORTANCE_DEFAULT, which posts to the status bar and
     * makes a sound but deliberately does NOT "peek" — so no heads-up banner
     * ever appeared, which is exactly the reported symptom. Heads-up banners
     * require IMPORTANCE_HIGH, and only the app can ask for that.
     *
     * The id carries a `_v2` suffix on purpose. A channel's importance belongs
     * to the USER once it exists: re-creating an existing id can never raise it
     * back up. Existing installs already hold `etl_default` at the SDK's
     * default importance, so the only way to give them banners is a new id.
     * Keep it in step with:
     *   • AndroidManifest.xml  → default_notification_channel_id
     *   • notice_service.py    → _ANDROID_CHANNEL_ID
     *   • fcm_service.py       → send_push(android_channel_id=...) default
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Alerts",
            // HIGH = heads-up banner over whatever is on screen. The backend
            // already sends android priority "high" / apns-priority 10; without
            // a HIGH channel that request is silently downgraded.
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Attendance, maintenance, feedback and roster alerts"
            enableVibration(true)
            setShowBadge(true)
        }

        // Idempotent: creating an existing channel is a no-op, so this is safe
        // to run on every launch.
        val manager = getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(channel)
    }

    companion object {
        const val NOTIFICATION_CHANNEL_ID = "etl_default_v2"
    }
}
