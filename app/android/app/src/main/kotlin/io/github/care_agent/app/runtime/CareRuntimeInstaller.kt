// Adapted from ccch1mneyyy/dsh-Go (AGPL-3.0); see root THIRD_PARTY_NOTICES.md.
package io.github.care_agent.app.runtime

import android.content.Context
import android.content.res.AssetManager
import java.io.File
import java.security.DigestInputStream
import java.security.MessageDigest

/**
 * Verifies and unpacks the all-in-one offline ARM64 rootfs archives from APK assets
 * into app-private storage (`filesDir/runtime/rootfs`). Zero network calls.
 */
class CareRuntimeInstaller(
    private val context: Context,
    private val manifest: RuntimeManifest,
    private val onLog: (String) -> Unit,
) {
    val baseDir = File(context.filesDir, "runtime")
    val rootfs = File(baseDir, "rootfs")
    private val versionFile = File(baseDir, "rootfs.version")
    private val staging = File(baseDir, "staging")

    fun installedVersion(): String? =
        if (rootfs.isDirectory && versionFile.isFile) versionFile.readText().trim().ifEmpty { null } else null

    fun isCurrent(): Boolean = installedVersion() == manifest.runtimeVersion

    fun install(onProgress: (Long, Long) -> Unit) {
        val needBytes = (manifest.archives.sumOf { it.uncompressedBytes.coerceAtLeast(0L) }
            .takeIf { it > 0 } ?: 512L * 1024 * 1024) * 115 / 100
        val freeBytes = context.filesDir.usableSpace
        check(freeBytes >= needBytes) {
            "Insufficient storage: need ${needBytes / (1024 * 1024)} MB, free ${freeBytes / (1024 * 1024)} MB"
        }

        baseDir.mkdirs()
        if (staging.exists()) staging.deleteRecursively()
        staging.mkdirs()

        val lengths = manifest.archives.map { archive ->
            runCatching {
                context.assets.openFd("${RuntimeManifest.ASSET_DIR}/${archive.asset}").use { it.length }
            }.getOrDefault(archive.bytes.coerceAtLeast(0L))
        }
        val total = lengths.sum().coerceAtLeast(1L)
        var completed = 0L
        var lastReported = 0L

        for ((index, archive) in manifest.archives.withIndex()) {
            val assetPath = "${RuntimeManifest.ASSET_DIR}/${archive.asset}"
            val progress: (Long) -> Unit = { read ->
                val aggregate = (completed + read).coerceAtMost(total)
                if (aggregate - lastReported >= 512 * 1024 || aggregate == total) {
                    lastReported = aggregate
                    onProgress(aggregate, total)
                }
            }

            if (archive.sha256 != null) {
                onLog("[care] verifying ${archive.asset}")
                val digest = MessageDigest.getInstance("SHA-256")
                DigestInputStream(
                    context.assets.open(assetPath, AssetManager.ACCESS_STREAMING),
                    digest,
                ).use { input ->
                    val buf = ByteArray(1 shl 16)
                    while (input.read(buf) >= 0) {}
                }
                val actual = digest.digest().joinToString("") { "%02x".format(it) }
                if (!archive.sha256.equals(actual, ignoreCase = true)) {
                    staging.deleteRecursively()
                    error("Offline runtime checksum mismatch for ${archive.asset}")
                }
            }

            onLog("[care] extracting ${archive.asset}")
            val extractor = TarExtractor(staging, progress)
            if (archive.asset.endsWith(".xz") && lengths[index] > 0) {
                val decoded = ParallelXZInputStream.open(
                    { AssetSeekableInputStream(context.assets.openFd(assetPath)) },
                    progress,
                )
                extractor.extractDecoded(decoded)
            } else {
                context.assets.open(assetPath, AssetManager.ACCESS_STREAMING).use { raw ->
                    extractor.extract(raw, archive.asset)
                }
            }
            completed += lengths[index]
        }

        val oldRootfs = File(baseDir, "rootfs.old")
        if (oldRootfs.exists()) oldRootfs.deleteRecursively()
        if (rootfs.exists()) check(rootfs.renameTo(oldRootfs)) { "Failed to stage previous rootfs" }
        check(staging.renameTo(rootfs)) { "Failed to activate extracted rootfs" }
        versionFile.writeText("${manifest.runtimeVersion}\n")
        oldRootfs.deleteRecursively()
        onProgress(total, total)
        onLog("[care] offline runtime ${manifest.runtimeVersion} installed")
    }
}
