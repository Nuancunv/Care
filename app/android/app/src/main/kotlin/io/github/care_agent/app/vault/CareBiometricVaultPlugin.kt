package io.github.care_agent.app.vault

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.concurrent.Executors

/**
 * Native Privacy Bot Vault & Encrypted Local Backup plugin (`care/vault`, M4).
 *
 * Enforces:
 * - Physical storage isolation (`filesDir/care_privacy_vault/<botId>/`) separate from Chief/shared docs (AGENTS.md §1.4).
 * - Native Android BiometricPrompt / Keyguard device-credential verification without external cloud auth.
 * - Pure local AES-256-GCM backup encryption/decryption (AGENTS.md §1.1 & §1.2).
 */
class CareBiometricVaultPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var appContext: Context
    private var methodChannel: MethodChannel? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingKeyguardResult: MethodChannel.Result? = null
    private val cryptoExecutor = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "care/vault").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        cryptoExecutor.shutdownNow()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "biometricStatus" -> result.success(queryBiometricStatus())
            "authenticate" -> {
                val title = call.argument<String>("title")?.takeIf { it.isNotBlank() } ?: "解锁 Care 隐私空间"
                val subtitle = call.argument<String>("subtitle")?.takeIf { it.isNotBlank() }
                    ?: "需要验证本机指纹、面容或锁屏密码"
                authenticateNative(title, subtitle, result)
            }
            "encryptBackup" -> {
                val passphrase = call.argument<String>("passphrase") ?: ""
                val payload = call.argument<String>("payload") ?: ""
                cryptoExecutor.execute {
                    try {
                        val encrypted = CareVaultCrypto.encrypt(passphrase, payload)
                        runOnUi { result.success(encrypted) }
                    } catch (err: Exception) {
                        runOnUi { result.error("ENCRYPT_FAILED", err.message ?: "Encryption failed", null) }
                    }
                }
            }
            "decryptBackup" -> {
                val passphrase = call.argument<String>("passphrase") ?: ""
                val envelope = call.argument<String>("envelope") ?: ""
                cryptoExecutor.execute {
                    try {
                        val plain = CareVaultCrypto.decrypt(passphrase, envelope)
                        runOnUi { result.success(plain) }
                    } catch (err: Exception) {
                        runOnUi { result.error("DECRYPT_FAILED", err.message ?: "Decryption failed", null) }
                    }
                }
            }
            "readPrivacyDoc" -> {
                try {
                    val botId = PrivacyVaultPathGuard.validateBotId(call.argument<String>("botId") ?: "")
                    val filename = PrivacyVaultPathGuard.validateFilename(call.argument<String>("filename") ?: "")
                    val file = File(vaultDir(botId), filename)
                    result.success(if (file.exists()) file.readText(Charsets.UTF_8) else null)
                } catch (err: Exception) {
                    result.error("PRIVACY_READ_FAILED", err.message, null)
                }
            }
            "writePrivacyDoc" -> {
                try {
                    val botId = PrivacyVaultPathGuard.validateBotId(call.argument<String>("botId") ?: "")
                    val filename = PrivacyVaultPathGuard.validateFilename(call.argument<String>("filename") ?: "")
                    val content = call.argument<String>("content") ?: ""
                    val dir = vaultDir(botId).apply { mkdirs() }
                    val target = File(dir, filename)
                    val tmp = File(dir, "$filename.tmp")
                    tmp.writeText(content, Charsets.UTF_8)
                    if (!tmp.renameTo(target)) {
                        target.writeText(content, Charsets.UTF_8)
                        tmp.delete()
                    }
                    result.success(true)
                } catch (err: Exception) {
                    result.error("PRIVACY_WRITE_FAILED", err.message, null)
                }
            }
            "wipePrivacyVault" -> {
                try {
                    val botId = PrivacyVaultPathGuard.validateBotId(call.argument<String>("botId") ?: "")
                    val dir = vaultDir(botId)
                    val deleted = !dir.exists() || dir.deleteRecursively()
                    result.success(deleted)
                } catch (err: Exception) {
                    result.error("PRIVACY_WIPE_FAILED", err.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun vaultDir(botId: String): File =
        File(File(appContext.filesDir, "care_privacy_vault"), botId)

    private fun queryBiometricStatus(): Map<String, Any> {
        val km = appContext.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val deviceSecure = km?.isDeviceSecure == true
        var biometricReady = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val bm = appContext.getSystemService(BiometricManager::class.java)
            if (bm != null) {
                val status = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    bm.canAuthenticate(
                        BiometricManager.Authenticators.BIOMETRIC_WEAK or
                            BiometricManager.Authenticators.DEVICE_CREDENTIAL
                    )
                } else {
                    @Suppress("DEPRECATION")
                    bm.canAuthenticate()
                }
                biometricReady = status == BiometricManager.BIOMETRIC_SUCCESS
            }
        }
        return mapOf(
            "biometricReady" to biometricReady,
            "deviceSecure" to deviceSecure,
            "available" to (biometricReady || deviceSecure),
        )
    }

    private fun authenticateNative(title: String, subtitle: String, result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            result.success(mapOf("authenticated" to false, "reason" to "Activity unavailable"))
            return
        }

        val status = queryBiometricStatus()
        if (status["available"] != true) {
            // Device has no lock screen or biometric enrolled; report transparently so UI can prompt user.
            result.success(
                mapOf(
                    "authenticated" to false,
                    "deviceUnsecured" to true,
                    "reason" to "No screen lock or biometric enrolled on this device.",
                )
            )
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val builder = BiometricPrompt.Builder(act)
                    .setTitle(title)
                    .setSubtitle(subtitle)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    builder.setAllowedAuthenticators(
                        BiometricManager.Authenticators.BIOMETRIC_WEAK or
                            BiometricManager.Authenticators.DEVICE_CREDENTIAL
                    )
                } else {
                    @Suppress("DEPRECATION")
                    builder.setDeviceCredentialAllowed(true)
                }

                val prompt = builder.build()
                val cancellation = CancellationSignal()
                var responded = false
                prompt.authenticate(
                    cancellation,
                    act.mainExecutor,
                    object : BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                            if (responded) return
                            responded = true
                            result.success(mapOf("authenticated" to true))
                        }

                        override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                            if (responded) return
                            responded = true
                            result.success(
                                mapOf(
                                    "authenticated" to false,
                                    "reason" to errString.toString(),
                                )
                            )
                        }
                    }
                )
                return
            } catch (_: Throwable) {
                // Fall back to Keyguard confirm device credential intent below.
            }
        }

        val km = act.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        @Suppress("DEPRECATION")
        val intent = km?.createConfirmDeviceCredentialIntent(title, subtitle)
        if (intent == null) {
            result.success(mapOf("authenticated" to false, "reason" to "Screen lock unavailable"))
            return
        }
        pendingKeyguardResult = result
        @Suppress("DEPRECATION")
        act.startActivityForResult(intent, REQ_CONFIRM_CREDENTIAL)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_CONFIRM_CREDENTIAL) return false
        val pending = pendingKeyguardResult ?: return false
        pendingKeyguardResult = null
        pending.success(
            mapOf(
                "authenticated" to (resultCode == Activity.RESULT_OK),
                "reason" to if (resultCode == Activity.RESULT_OK) "" else "Verification canceled",
            )
        )
        return true
    }

    private fun runOnUi(block: () -> Unit) {
        val act = activity
        if (act != null) {
            act.runOnUiThread(block)
        } else {
            block()
        }
    }

    companion object {
        private const val REQ_CONFIRM_CREDENTIAL = 4108
    }
}
