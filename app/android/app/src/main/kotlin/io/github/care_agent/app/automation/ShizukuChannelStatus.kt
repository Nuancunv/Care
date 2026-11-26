package io.github.care_agent.app.automation

import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings

/**
 * Lightweight self-check helper for Accessibility and optional Shizuku/Sui readiness
 * (ColorOS / OPPO Find X8s+ friendly; never crashes if Shizuku is absent).
 */
object ShizukuChannelStatus {
    private val SHIZUKU_PACKAGES = listOf(
        "moe.shizuku.privileged.api",
        "rikka.sui",
    )

    fun isShizukuInstalled(context: Context): Boolean {
        val pm = context.packageManager
        return SHIZUKU_PACKAGES.any { pkg ->
            runCatching {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkg, 0)
                true
            }.getOrDefault(false)
        }
    }

    fun isAccessibilityEnabledInSystem(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        return enabled.contains(context.packageName) && enabled.contains("CareA11yService")
    }
}
