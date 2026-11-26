// Adapted in concept from ccch1mneyyy/dsh-Go (AGPL-3.0); see root THIRD_PARTY_NOTICES.md.
package io.github.care_agent.app.automation

/**
 * Hard native security fence for on-device Android automation (AGENTS.md §1.3).
 * Cannot be overridden by LLM prompts, plugins, or settings flags.
 */
object ProtectedAppsPolicy {
    /** System security, settings, password managers, and payment wallets that reject blind automation. */
    private val HARD_PROTECTED_PACKAGES = setOf(
        "com.android.settings",
        "com.android.systemui",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.oplus.safecenter",
        "com.coloros.safecenter",
        "com.oplus.securitypermission",
        "com.miui.securitycenter",
        "com.huawei.systemmanager",
        "com.eg.android.AlipayGphone",
        "com.unionpay",
        "com.onepassword.android",
        "com.x8bit.bitwarden",
        "keepass2android.keepass2android",
    )

    private val SENSITIVE_TEXT_PATTERN = Regex(
        """(?i)(立即支付|确认付款|确认支付|转账|确认下单|提交订单|输入密码|支付密码|清空数据|永久删除|卸载|授予权限|pay\s*now|confirm\s*payment|transfer\s*money|delete\s*all|uninstall)""",
    )

    fun isHardProtectedPackage(packageName: String?): Boolean {
        val pkg = packageName?.trim()?.lowercase().orEmpty()
        if (pkg.isEmpty()) return false
        return HARD_PROTECTED_PACKAGES.any { it.equals(pkg, ignoreCase = true) }
    }

    fun containsSensitiveActionText(text: String?): Boolean {
        if (text.isNullOrBlank()) return false
        return SENSITIVE_TEXT_PATTERN.containsMatchIn(text)
    }

    /**
     * Validates whether an automated write gesture is allowed to proceed (still requires
     * a native single-use SafetyGate approval token separately).
     * Returns null when eligible for gated execution, or a refusal reason when hard-blocked.
     */
    fun hardRefusalReason(
        packageName: String?,
        targetIsPassword: Boolean = false,
    ): String? {
        if (targetIsPassword) {
            return "Password input fields are strictly blocked from automated access."
        }
        if (isHardProtectedPackage(packageName)) {
            return "Package '$packageName' is a protected system/payment/security app and cannot be automated."
        }
        return null
    }
}
