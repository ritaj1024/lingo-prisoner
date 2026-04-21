package com.lingoprisoner.lingo_prisoner

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class PrisonModeHandler(private val context: Context) {
    
    companion object {
        const val CHANNEL = "com.lingoprisoner/prison"
        const val METHOD_ACTIVATE = "activatePrisonMode"
        const val METHOD_DEACTIVATE = "deactivatePrisonMode"
        const val METHOD_CHECK_PERMISSION = "checkPermissions"
        
        // 白名单应用包名
        val ALLOWED_PACKAGES = listOf(
            "com.android.dialer",      // 电话
            "com.android.mms",          // 短信
            "com.tencent.mm",           // 微信
            "com.android.settings",     // 设置
            "com.lingoprisoner.lingo_prisoner" // 本应用
        )
    }
    
    private val methodChannelHandler = MethodChannel.MethodCallHandler { call, result ->
        when (call.method) {
            METHOD_ACTIVATE -> {
                val allowedApps = call.argument<List<String>>("allowedApps")
                if (activatePrisonMode(allowedApps)) {
                    result.success(true)
                } else {
                    result.error("ACTIVATION_FAILED", "Failed to activate prison mode", null)
                }
            }
            METHOD_DEACTIVATE -> {
                if (deactivatePrisonMode()) {
                    result.success(true)
                } else {
                    result.error("DEACTIVATION_FAILED", "Failed to deactivate prison mode", null)
                }
            }
            METHOD_CHECK_PERMISSION -> {
                val hasPermission = checkRequiredPermissions()
                result.success(hasPermission)
            }
            else -> result.notImplemented()
        }
    }
    
    /**
     * 激活监狱模式
     */
    private fun activatePrisonMode(allowedApps: List<String>?): Boolean {
        // 检查权限
        if (!checkRequiredPermissions()) {
            requestPermissions()
            return false
        }
        
        // 启动监狱模式服务
        val serviceIntent = Intent(context, PrisonModeMonitorService::class.java).apply {
            putExtra("allowedApps", allowedApps?.toTypedArray() ?: ALLOWED_PACKAGES.toTypedArray())
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
        
        return true
    }
    
    /**
     * 解除监狱模式
     */
    private fun deactivatePrisonMode(): Boolean {
        val serviceIntent = Intent(context, PrisonModeMonitorService::class.java)
        context.stopService(serviceIntent)
        return true
    }
    
    /**
     * 检查必需的权限
     */
    private fun checkRequiredPermissions(): Boolean {
        // 检查是否有覆盖层权限
        if (!Settings.canDrawOverlays(context)) {
            return false
        }
        
        // 检查是否有使用情况访问权限
        if (!hasUsageStatsPermission()) {
            return false
        }
        
        return true
    }
    
    /**
     * 检查是否有使用情况访问权限
     */
    private fun hasUsageStatsPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        }
        
        return mode == AppOpsManager.MODE_ALLOWED
    }
    
    /**
     * 请求必需的权限
     */
    private fun requestPermissions() {
        // 启动权限请求Activity
        val intent = Intent(context, PrisonPermissionActivity::class.java)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        context.startActivity(intent)
    }
    
    /**
     * 检查应用是否在白名单中
     */
    fun isAppAllowed(packageName: String): Boolean {
        return ALLOWED_PACKAGES.contains(packageName)
    }
}
