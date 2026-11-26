package io.github.care_agent.app.vault

import org.json.JSONObject
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * Pure local AES-256-GCM + PBKDF2-HMAC-SHA256 backup crypto for Care (M4).
 *
 * Guarantees:
 * - Zero cloud relay or key escrow; passphrase stays in memory only for the call.
 * - Authenticated encryption (GCM 128-bit tag) detects any tampering or wrong passphrase.
 */
object CareVaultCrypto {
    const val FORMAT_VERSION = "care-backup-v1"
    private const val KDF_ALGO = "PBKDF2WithHmacSHA256"
    private const val KDF_ITERATIONS = 120_000
    private const val KEY_BITS = 256
    private const val SALT_BYTES = 16
    private const val IV_BYTES = 12
    private const val GCM_TAG_BITS = 128
    private const val MIN_PASSPHRASE_LENGTH = 6

    private val random = SecureRandom()

    fun encrypt(passphrase: String, plaintextUtf8: String): String {
        require(passphrase.length >= MIN_PASSPHRASE_LENGTH) {
            "Passphrase must be at least $MIN_PASSPHRASE_LENGTH characters."
        }
        val salt = ByteArray(SALT_BYTES).also { random.nextBytes(it) }
        val iv = ByteArray(IV_BYTES).also { random.nextBytes(it) }
        val key = deriveKey(passphrase, salt, KDF_ITERATIONS)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
        val ciphertext = cipher.doFinal(plaintextUtf8.toByteArray(Charsets.UTF_8))

        val b64 = Base64.getEncoder()
        return JSONObject().apply {
            put("format", FORMAT_VERSION)
            put("cipher", "AES-256-GCM")
            put("kdf", KDF_ALGO)
            put("iterations", KDF_ITERATIONS)
            put("salt", b64.encodeToString(salt))
            put("iv", b64.encodeToString(iv))
            put("ciphertext", b64.encodeToString(ciphertext))
        }.toString()
    }

    fun decrypt(passphrase: String, envelopeJson: String): String {
        require(passphrase.isNotEmpty()) { "Passphrase is required." }
        val env = JSONObject(envelopeJson)
        val format = env.optString("format", "")
        require(format == FORMAT_VERSION) { "Unsupported backup format: $format" }

        val iterations = env.optInt("iterations", KDF_ITERATIONS)
        require(iterations in 10_000..1_000_000) { "Invalid KDF iterations." }

        val b64 = Base64.getDecoder()
        val salt = b64.decode(env.getString("salt"))
        val iv = b64.decode(env.getString("iv"))
        val ciphertext = b64.decode(env.getString("ciphertext"))
        val key = deriveKey(passphrase, salt, iterations)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
        val plainBytes = cipher.doFinal(ciphertext)
        return String(plainBytes, Charsets.UTF_8)
    }

    private fun deriveKey(passphrase: String, salt: ByteArray, iterations: Int): SecretKeySpec {
        val spec = PBEKeySpec(passphrase.toCharArray(), salt, iterations, KEY_BITS)
        try {
            val factory = SecretKeyFactory.getInstance(KDF_ALGO)
            val bytes = factory.generateSecret(spec).encoded
            return SecretKeySpec(bytes, "AES")
        } finally {
            spec.clearPassword()
        }
    }
}

/**
 * Validates identifiers and filenames for physically isolated Privacy Bot vaults (AGENTS.md §1.4).
 */
object PrivacyVaultPathGuard {
    private val SAFE_ID = Regex("^[a-zA-Z0-9_-]{1,48}$")
    private val SAFE_FILE = Regex("^[a-zA-Z0-9._-]{1,64}$")

    fun validateBotId(botId: String): String {
        val clean = botId.trim()
        require(SAFE_ID.matches(clean)) { "Invalid privacy bot identifier." }
        return clean
    }

    fun validateFilename(filename: String): String {
        val clean = filename.trim()
        require(SAFE_FILE.matches(clean) && !clean.contains("..") && !clean.startsWith(".")) {
            "Invalid privacy document filename."
        }
        return clean
    }
}
