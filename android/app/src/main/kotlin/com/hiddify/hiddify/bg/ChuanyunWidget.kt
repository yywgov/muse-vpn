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
import android.net.Uri
import android.view.View
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
        private const val KEY_FAVS = "favs"
        private const val MAX_FAVS = 3
        private val favIds = intArrayOf(R.id.widget_fav1, R.id.widget_fav2, R.id.widget_fav3)

        /** 1.16.0 R25: (tag, name) pairs from the two lists 穿云 sends, at most 3. */
        fun zipFavs(tags: List<String>, names: List<String>): List<Pair<String, String>> =
            tags.zip(names).filter { it.first.isNotBlank() }.take(MAX_FAVS)

        /** Saved form: one 「tag \u001F name」 per line (neither can hold these control characters). */
        fun encodeFavs(favs: List<Pair<String, String>>): String =
            favs.joinToString("\n") { "${it.first.replace('\n', ' ')}\u001F${it.second.replace('\n', ' ')}" }

        fun decodeFavs(raw: String?): List<Pair<String, String>> =
            (raw ?: "").split('\n').mapNotNull { line ->
                val i = line.indexOf('\u001F')
                if (i <= 0) null else Pair(line.substring(0, i), line.substring(i + 1))
            }.take(MAX_FAVS)

        /** The link a 常用节点 tap opens: switch to [tag] and connect (same as chuanyun://connect?node=). */
        fun favLink(tag: String): String = "chuanyun://connect?node=" + Uri.encode(tag)

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
                // 穿云 1.13.0 安全模式: no widget updates (cached flag only — no Context, no file read)
                if (ChuanyunHealth.safeModeCached) return
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
                if (ChuanyunHealth.safeModeCached) return
                val context = appContext() ?: return
                save(context, node, delay, null)
            } catch (_: Throwable) {
            }
        }

        /** 1.16.0 R25: the node, its delay and the 常用节点 in one redraw. */
        fun onNodeFavs(node: String, delay: Int, favs: List<Pair<String, String>>) {
            try {
                if (ChuanyunHealth.safeModeCached) return
                val context = appContext() ?: return
                save(context, node, delay, encodeFavs(favs))
            } catch (_: Throwable) {
            }
        }

        /** [favRaw] null keeps the saved 常用节点. Redraws only when something changed. */
        private fun save(context: Context, node: String, delay: Int, favRaw: String?) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getString(KEY_NODE, "") == node && prefs.getInt(KEY_DELAY, 0) == delay &&
                (favRaw == null || prefs.getString(KEY_FAVS, "") == favRaw)
            ) return
            val edit = prefs.edit().putString(KEY_NODE, node).putInt(KEY_DELAY, delay)
            if (favRaw != null) edit.putString(KEY_FAVS, favRaw)
            edit.apply()
            redraw(context)
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
            // 1.16.0 R25: 常用节点 — tap one to switch to it and connect (opens 穿云 via chuanyun://connect?node=)
            val favs = decodeFavs(prefs.getString(KEY_FAVS, ""))
            views.setViewVisibility(R.id.widget_favs, if (favs.isEmpty()) View.GONE else View.VISIBLE)
            for (i in favIds.indices) {
                val id = favIds[i]
                val fav = favs.getOrNull(i)
                if (fav == null) {
                    views.setViewVisibility(id, View.INVISIBLE)
                    continue
                }
                views.setViewVisibility(id, View.VISIBLE)
                views.setTextViewText(id, fav.second)
                views.setContentDescription(id, "切换到节点 ${fav.second}")
                val pick = Intent(Intent.ACTION_VIEW, Uri.parse(favLink(fav.first)), context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                views.setOnClickPendingIntent(
                    id,
                    PendingIntent.getActivity(context, 10 + i, pick, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
                )
            }
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
