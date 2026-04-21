package com.lingoprisoner.lingo_prisoner

import android.app.*
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.core.app.NotificationCompat

/**
 * 监狱模式监控服务
 * 负责监控应用使用情况并阻止非白名单应用
 */
class PrisonModeMonitorService : Service() {
    
    private var windowManager: WindowManager? = null
    private var blockOverlay: View? = null
    private var allowedApps = arrayOf<String>()
    private val handler = Handler(Looper.getMainLooper())
    
    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "prison_mode_channel"
        
        /**
         * 获取当前前台应用包名
         */
        private fun getCurrentForegroundApp(context: Context): String? {
            val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val currentTime = System.currentTimeMillis()
            
            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                currentTime - 60 * 1000,
                currentTime
            )
            
            if (stats.isNullOrEmpty()) return null
            
            return stats.maxByOrNull { it.lastTimeUsed }?.packageName
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.getStringArrayExtra("allowedApps")?.let {
            allowedApps = it
        }
        startMonitoring()
        return START_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopMonitoring()
    }
    
    /**
     * 开始监控
     */
    private fun startMonitoring() {
        val monitorTask = object : Runnable {
            override fun run() {
                checkAndBlockApps()
                handler.postDelayed(this, 1000)
            }
        }
        handler.post(monitorTask)
    }
    
    /**
     * 停止监控
     */
    private fun stopMonitoring() {
        handler.removeCallbacksAndMessages(null)
        blockOverlay?.let {
            windowManager?.removeView(it)
            blockOverlay = null
        }
    }
    
    /**
     * 检查并阻止非白名单应用
     */
    private fun checkAndBlockApps() {
        val currentApp = getCurrentForegroundApp(this) ?: return
        
        if (currentApp == packageName || allowedApps.contains(currentApp)) {
            blockOverlay?.let {
                if (it.isAttachedToWindow) {
                    windowManager?.removeView(it)
                }
                blockOverlay = null
            }
            return
        }
        
        if (blockOverlay == null || blockOverlay?.isAttachedToWindow == false) {
            showBlockOverlay()
        }
    }
    
    /**
     * 显示阻止覆盖层
     */
    private fun showBlockOverlay() {
        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        
        layoutParams.gravity = Gravity.CENTER
        
        blockOverlay = LayoutInflater.from(this).inflate(R.layout.prison_block_layout, null)
        
        blockOverlay?.findViewById<Button>(R.id.btn_back_to_app)?.setOnClickListener {
            val homeIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            startActivity(homeIntent)
        }
        
        val allowedAppsText = blockOverlay?.findViewById<TextView>(R.id.tv_allowed_apps)
        allowedAppsText?.text = allowedApps.joinToString("\n") { pkg ->
            when (pkg) {
                "com.android.dialer" -> "📞 电话"
                "com.android.mms" -> "💬 短信"
                "com.tencent.mm" -> "💬 微信"
                "com.android.settings" -> "⚙️ 设置"
                else -> pkg
            }
        }
        
        windowManager?.addView(blockOverlay, layoutParams)
    }
    
    /**
     * 创建通知渠道
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "监狱模式监控",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "监控应用使用，确保学习任务完成"
            }
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    /**
     * 创建前台服务通知
     */
    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("监狱模式运行中")
            .setContentText("完成学习后自动解锁其他应用")
            .setSmallIcon(R.drawable.ic_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}
