package com.hiddify.hiddify.bg

// 穿云 1.11.0 - home-screen widget: one tap connects / disconnects, and it shows the node in use with
// its delay. Event driven only: it is redrawn when the service status changes (BoxService /
// CompatService observe their own status) and when 穿云 tells it the node or delay changed
// (ChuanyunHandler "widget_update"). updatePeriodMillis is 0 — no timer, no polling, no wake-ups.
// The tap goes to QuickActionActivity (com.chuanyun.app.action.TOGGLE), the same path as automation
// and the quick-settings tile. Part of 穿云 (GPLv3).

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.hiddify.hiddify.Application
import com.hiddify.hiddify.MainActivity
import com.hiddify.hiddify.QuickActionActivity
import com.hiddify.hiddify.R
import com.hiddify.hiddify.constant.Status

/** What the widget shows (pure, unit-testable). */
data class ChuanyunWidgetView(val title: String, val detail: String, val on: Boolean)

class ChuanyunWidget : AppWidgetProvider() {

    companion object {
        private const val PREFS = "chuanyun_widget"
        private const val KEY_STATUS = "status"
        private const val KEY_NODE = "node"
        private const val KEY_DELAY = "delay"

        /** The widget's text for a status, node name and delay (0 = unknown). */
        fun view(status: String, node: String, delay: Int): ChuanyunWidgetView {
            val on = status == Status.Started.name
            val title = when (status) {
                Status.Started.name -> "已连接"
                Status.Starting.name -> "正在连接…"
                Status.Stopping.name -> "正在断开…"
                else -> "未连接"
            }
            val detail = when {
                node.isBlank() -> if (on) "穿云" else "点按连接"
                on && delay in 1..64999 -> "$node · $delay ms"
                else -> node
            }
            return ChuanyunWidgetView(title, detail, on)
        }

        /**
         * Service status changed (main or :compat process).
         *
         * 穿云 1.11.1 (1.11.0 启动闪退): BoxService / CompatService are built in their Service's field
         * initialiser, before the Service has a base context, and LiveData.observeForever calls this
         * at once with the current status. 1.11.0 read the preferences through that Service
         * (getSharedPreferences on a ContextWrapper whose base is still null → NullPointerException),
         * and since MainActivity binds the service on every start, the app died on launch. Now it
         * always uses the application context (attached before any component is created) and a
         * widget problem can never take the service or the app down.
         */
        fun onStatus(status: Status) {
            try {
                val context = appContext() ?: return
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                if (prefs.getString(KEY_STATUS, null) == status.name) return
                prefs.edit().putString(KEY_STATUS, status.name).apply()
                redraw(context)
            } catch (_: Throwable) {
            }
        }

        /** 穿云 says the node in use or its delay changed. */
        fun onNode(node: String, delay: Int) {
            try {
                val context = appContext() ?: return
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                if (prefs.getString(KEY_NODE, "") == node && prefs.getInt(KEY_DELAY, 0) == delay) return
                prefs.edit().putString(KEY_NODE, node).putInt(KEY_DELAY, delay).apply()
                redraw(context)
            } catch (_: Throwable) {
            }
        }

        /** The application context (never a Service / Activity that may not be attached yet). */
        private fun appContext(): Context? = try {
            Application.application.applicationContext
        } catch (_: Throwable) {
            null
        }

        private fun redraw(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context) ?: return
                val ids = manager.getAppWidgetIds(ComponentName(context, ChuanyunWidget::class.java))
                if (ids.isEmpty()) return
                manager.updateAppWidget(ids, build(context))
            } catch (_: Throwable) {
            }
        }

        private fun build(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val v = view(
                prefs.getString(KEY_STATUS, Status.Stopped.name) ?: Status.Stopped.name,
                prefs.getString(KEY_NODE, "") ?: "",
                prefs.getInt(KEY_DELAY, 0),
            )
            val views = RemoteViews(context.packageName, R.layout.chuanyun_widget)
            views.setTextViewText(R.id.widget_title, v.title)
            views.setTextViewText(R.id.widget_detail, v.detail)
            views.setImageViewResource(R.id.widget_toggle, if (v.on) R.drawable.widget_power_on else R.drawable.widget_power_off)
            views.setContentDescription(R.id.widget_toggle, if (v.on) "断开" else "连接")
            val toggle = Intent(context, QuickActionActivity::class.java)
                .setAction(QuickActionActivity.ACTION_TOGGLE)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            views.setOnClickPendingIntent(
                R.id.widget_toggle,
                PendingIntent.getActivity(context, 1, toggle, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
            )
            val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            views.setOnClickPendingIntent(
                R.id.widget_text,
                PendingIntent.getActivity(context, 2, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
            )
            return views
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        try {
            manager.updateAppWidget(ids, build(context))
        } catch (_: Throwable) {
        }
    }
}
