package io.github.care_agent.app

import io.github.care_agent.app.automation.ProtectedAppsPolicy
import io.github.care_agent.app.ecosystem.NoticePrivacyFilter
import io.github.care_agent.app.proactive.QuietHoursPolicy
import io.github.care_agent.app.runtime.RuntimeManifest
import io.github.care_agent.app.runtime.SecretRedactor
import io.github.care_agent.app.safety.CareSafetyGateCoordinator
import io.github.care_agent.app.safety.RiskLevel
import io.github.care_agent.app.safety.SafetyGatePolicy
import io.github.care_agent.app.vault.CareVaultCrypto
import io.github.care_agent.app.vault.PrivacyVaultPathGuard
import io.github.care_agent.app.workspace.CareWorkspacePathGuard
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CareNativeTests {
    @Test
    fun secretRedactorMasksApiKeysAndBearerHeaders() {
        val raw = "Starting with DEEPSEEK_API_KEY=sk-1234567890abcdef123456 Authorization: Bearer tok_abcdef123456"
        val redacted = SecretRedactor.redact(raw)
        assertFalse(redacted.contains("sk-1234567890"))
        assertFalse(redacted.contains("tok_abcdef123456"))
        assertTrue(redacted.contains("[REDACTED]"))
    }

    @Test
    fun safetyGatePolicyEnforcesL2ApprovalAndFailsClosed() {
        assertEquals(RiskLevel.L2_HIGH_RISK, SafetyGatePolicy.classify("payment_action"))
        assertEquals(RiskLevel.L2_HIGH_RISK, SafetyGatePolicy.classify("accessibility_write"))
        assertEquals(RiskLevel.L2_HIGH_RISK, SafetyGatePolicy.classify("send_external_message"))
        assertEquals(RiskLevel.L2_HIGH_RISK, SafetyGatePolicy.classify("delete_file"))
        assertEquals(RiskLevel.L2_HIGH_RISK, SafetyGatePolicy.classify("unknown_tool_attempt"))
        assertTrue(SafetyGatePolicy.requiresExplicitApproval("shell_high_risk"))
        assertEquals(RiskLevel.L1_LOCAL_LOW_RISK, SafetyGatePolicy.classify("calendar_write"))
        assertFalse(SafetyGatePolicy.requiresExplicitApproval("calendar_write"))
    }

    @Test
    fun runtimeManifestParsesSchemaV2Arm64Layers() {
        val json = JSONObject(
            """
            {
              "schema": 2,
              "runtimeVersion": "care-0.1.0",
              "abi": "arm64-v8a",
              "dshVersion": "0.2.2-rc.1",
              "nodeVersion": "24.22.1",
              "layers": {
                "base": { "asset": "base-arm64-v8a.tar.xz", "bytes": 1000, "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "uncompressedBytes": 4000 },
                "engine": { "asset": "engine-arm64-v8a.tar.xz", "bytes": 2000, "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "uncompressedBytes": 6000 }
              },
              "launch": {
                "argv": ["{NATIVE_LIB_DIR}/libproot.so", "-r", "{ROOTFS}", "/usr/bin/env", "{GUEST_ENV}", "/usr/local/bin/dsh", "web", "--host", "127.0.0.1", "--port", "{PORT}"],
                "env": { "PROOT_NO_SECCOMP": "1" }
              }
            }
            """.trimIndent(),
        )
        val manifest = RuntimeManifest.fromJson(json)
        assertEquals("care-0.1.0", manifest.runtimeVersion)
        assertEquals("arm64-v8a", manifest.abi)
        assertEquals(2, manifest.archives.size)
        assertEquals("base-arm64-v8a.tar.xz", manifest.archives[0].asset)
        assertEquals("engine-arm64-v8a.tar.xz", manifest.archives[1].asset)
    }

    @Test
    fun quietHoursPolicyHandlesOvernightWrapAroundAndDailyDelay() {
        val start = QuietHoursPolicy.parseMinutesOfDay("23:00", 0)
        val end = QuietHoursPolicy.parseMinutesOfDay("07:30", 0)
        assertTrue(QuietHoursPolicy.isQuietMinute(23 * 60 + 15, start, end))
        assertTrue(QuietHoursPolicy.isQuietMinute(2 * 60, start, end))
        assertTrue(QuietHoursPolicy.isQuietMinute(7 * 60 + 29, start, end))
        assertFalse(QuietHoursPolicy.isQuietMinute(7 * 60 + 30, start, end))
        assertFalse(QuietHoursPolicy.isQuietMinute(12 * 60, start, end))

        val delay = QuietHoursPolicy.delayUntilNextDailyMs(System.currentTimeMillis(), "08:30")
        assertTrue(delay >= 60_000L)
        assertTrue(delay <= 24L * 3600_000L + 60_000L)
    }

    @Test
    fun noticePrivacyFilterBlocksOtpAndEnforcesAllowList() {
        val allow = setOf("com.express.app", "com.calendar.app")
        assertTrue(NoticePrivacyFilter.shouldCapture("com.express.app", "快递签收", "您的包裹已放入丰巢", allow))
        assertFalse(NoticePrivacyFilter.shouldCapture("com.bank.app", "消费提醒", "消费 100 元", allow))
        assertFalse(NoticePrivacyFilter.shouldCapture("com.express.app", "登录提醒", "您的验证码是 123456", allow))
        assertFalse(NoticePrivacyFilter.shouldCapture("com.express.app", "Security", "Your OTP code is 998877", allow))
        assertFalse(NoticePrivacyFilter.shouldCapture("com.express.app", "快递", "已到达", emptySet()))
    }

    @Test
    fun protectedAppsPolicyBlocksSystemPaymentAndPasswordFields() {
        assertTrue(ProtectedAppsPolicy.isHardProtectedPackage("com.oplus.safecenter"))
        assertTrue(ProtectedAppsPolicy.isHardProtectedPackage("com.eg.android.AlipayGphone"))
        assertTrue(ProtectedAppsPolicy.isHardProtectedPackage("com.android.settings"))
        assertFalse(ProtectedAppsPolicy.isHardProtectedPackage("com.example.notes"))

        assertTrue(ProtectedAppsPolicy.containsSensitiveActionText("立即支付 ¥99.00"))
        assertTrue(ProtectedAppsPolicy.containsSensitiveActionText("Confirm Payment"))
        assertFalse(ProtectedAppsPolicy.containsSensitiveActionText("保存备忘录"))

        assertTrue(ProtectedAppsPolicy.hardRefusalReason("com.example.notes", targetIsPassword = true) != null)
        assertTrue(ProtectedAppsPolicy.hardRefusalReason("com.oplus.safecenter", targetIsPassword = false) != null)
        assertEquals(null, ProtectedAppsPolicy.hardRefusalReason("com.example.notes", targetIsPassword = false))
    }

    @Test
    fun safetyGateCoordinatorEnforcesSingleUseTokensAndEmergencyStop() {
        CareSafetyGateCoordinator.resetForTest()
        val now = 1_700_000_000_000L
        val token = CareSafetyGateCoordinator.issueApprovalToken("accessibility_click", now)

        // Mismatched action must fail (and consumes/invalidates or rejects)
        assertFalse(CareSafetyGateCoordinator.consumeApprovalToken(null, "accessibility_click", now))
        assertTrue(CareSafetyGateCoordinator.consumeApprovalToken(token, "accessibility_click", now + 1000L))
        // Replay of the same token must fail!
        assertFalse(CareSafetyGateCoordinator.consumeApprovalToken(token, "accessibility_click", now + 2000L))

        // Expired token must fail
        val expired = CareSafetyGateCoordinator.issueApprovalToken("accessibility_write", now)
        assertFalse(CareSafetyGateCoordinator.consumeApprovalToken(expired, "accessibility_write", now + 120_000L))

        // Emergency stop immediately invalidates active tokens and blocks execution
        val live = CareSafetyGateCoordinator.issueApprovalToken("accessibility_click", now)
        CareSafetyGateCoordinator.triggerEmergencyStop()
        assertTrue(CareSafetyGateCoordinator.isEmergencyStopped())
        assertFalse(CareSafetyGateCoordinator.consumeApprovalToken(live, "accessibility_click", now + 100L))
        CareSafetyGateCoordinator.clearEmergencyStop()
        assertFalse(CareSafetyGateCoordinator.isEmergencyStopped())
    }

    @Test
    fun vaultCryptoRoundTripsAndRejectsWrongPassphraseOrTampering() {
        val payload = """{"soul":"# Care","memory":"# 长期记忆\n- 不吃香菜"}"""
        val encrypted = CareVaultCrypto.encrypt("care-secret-2026", payload)
        assertFalse(encrypted.contains("不吃香菜"))
        assertTrue(encrypted.contains(CareVaultCrypto.FORMAT_VERSION))

        val decrypted = CareVaultCrypto.decrypt("care-secret-2026", encrypted)
        assertEquals(payload, decrypted)

        var wrongFailed = false
        try {
            CareVaultCrypto.decrypt("wrong-passphrase", encrypted)
        } catch (_: Exception) {
            wrongFailed = true
        }
        assertTrue(wrongFailed)

        val env = JSONObject(encrypted)
        val tamperedCipher = env.getString("ciphertext").reversed()
        env.put("ciphertext", tamperedCipher)
        var tamperFailed = false
        try {
            CareVaultCrypto.decrypt("care-secret-2026", env.toString())
        } catch (_: Exception) {
            tamperFailed = true
        }
        assertTrue(tamperFailed)
    }

    @Test
    fun privacyVaultPathGuardBlocksTraversalAndInvalidIds() {
        assertEquals("privacy-vault", PrivacyVaultPathGuard.validateBotId("privacy-vault"))
        assertEquals("PRIVATE_MEMORY.md", PrivacyVaultPathGuard.validateFilename("PRIVATE_MEMORY.md"))

        fun fails(block: () -> Unit): Boolean = try {
            block()
            false
        } catch (_: IllegalArgumentException) {
            true
        }

        assertTrue(fails { PrivacyVaultPathGuard.validateBotId("../chief") })
        assertTrue(fails { PrivacyVaultPathGuard.validateBotId("a/b") })
        assertTrue(fails { PrivacyVaultPathGuard.validateFilename("../MEMORY.md") })
        assertTrue(fails { PrivacyVaultPathGuard.validateFilename(".hidden") })
    }

    @Test
    fun workspacePathGuardAllowsNestedSafeFilesAndBlocksTraversal() {
        assertEquals("notes/plan.md", CareWorkspacePathGuard.normalizeRelativePath("/notes/plan.md"))
        assertEquals("code/hello.py", CareWorkspacePathGuard.normalizeRelativePath("code\\hello.py"))
        assertEquals("学习计划.md", CareWorkspacePathGuard.normalizeRelativePath("学习计划.md"))

        fun fails(block: () -> Unit): Boolean = try {
            block()
            false
        } catch (_: IllegalArgumentException) {
            true
        }

        assertTrue(fails { CareWorkspacePathGuard.normalizeRelativePath("../secret.txt") })
        assertTrue(fails { CareWorkspacePathGuard.normalizeRelativePath("notes/../../etc/passwd") })
        assertTrue(fails { CareWorkspacePathGuard.normalizeRelativePath(".env") })
        assertTrue(fails { CareWorkspacePathGuard.normalizeRelativePath("") })
    }
}
