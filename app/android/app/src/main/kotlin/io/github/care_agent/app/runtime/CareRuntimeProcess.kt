// Adapted from ccch1mneyyy/dsh-Go (AGPL-3.0); see root THIRD_PARTY_NOTICES.md.
package io.github.care_agent.app.runtime

import android.content.Context
import java.io.BufferedReader
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import kotlin.concurrent.thread

/**
 * Spawns the local PRoot `dsh web` engine bound strictly to 127.0.0.1.
 * User secrets (DEEPSEEK_API_KEY) are injected exclusively via process environment memory
 * and redacted from every log line (AGENTS.md §1.2).
 */
class CareRuntimeProcess(
    private val context: Context,
    private val manifest: RuntimeManifest,
    private val rootfs: File,
    private val listener: Listener,
) {
    interface Listener {
        fun onLog(line: String, stream: String)
        fun onReady(baseUrl: String, token: String)
        fun onExit(code: Int, expected: Boolean)
    }

    @Volatile private var process: Process? = null
    @Volatile private var expectedExit = false
    @Volatile private var readyReported = false
    var port: Int = DEFAULT_PORT
        private set

    fun start(guestEnv: Map<String, String>) {
        check(process == null) { "Care runtime already started" }
        check(manifest.launchArgv.isNotEmpty()) { "Runtime manifest missing launch.argv" }

        port = pickLoopbackPort()
        val tmp = File(context.cacheDir, "proot-tmp").apply { mkdirs() }
        val vars = mapOf(
            "{NATIVE_LIB_DIR}" to context.applicationInfo.nativeLibraryDir,
            "{ROOTFS}" to rootfs.canonicalPath,
            "{TMP}" to tmp.absolutePath,
            "{FILES_DIR}" to context.filesDir.absolutePath,
            "{PORT}" to port.toString(),
        )
        fun expand(s: String): String = vars.entries.fold(s) { acc, (k, v) -> acc.replace(k, v) }

        val effectiveGuestEnv = LinkedHashMap<String, String>().apply {
            putAll(guestEnv)
            put("CARE_LOCAL_FIRST", "1")
            put("DSH_TELEMETRY_DISABLED", "1")
        }

        val argv = ArrayList<String>()
        var guestEnvPlaced = false
        for (arg in manifest.launchArgv) {
            if (arg == GUEST_ENV_PLACEHOLDER) {
                effectiveGuestEnv.forEach { (k, v) -> argv += "$k=$v" }
                guestEnvPlaced = true
            } else {
                argv += expand(arg)
            }
        }

        val builder = ProcessBuilder(argv).directory(context.filesDir)
        val env = builder.environment()
        env.clear()
        env["PATH"] = "/system/bin:/system/xbin"
        env["HOME"] = context.filesDir.absolutePath
        env["TMPDIR"] = tmp.absolutePath
        env["ANDROID_ROOT"] = System.getenv("ANDROID_ROOT") ?: "/system"
        env["ANDROID_DATA"] = System.getenv("ANDROID_DATA") ?: "/data"
        env["PROOT_TMP_DIR"] = tmp.absolutePath
        manifest.launchEnv.forEach { (k, v) -> env[k] = expand(v) }
        if (!guestEnvPlaced) env.putAll(effectiveGuestEnv)

        listener.onLog("[care] starting local engine on 127.0.0.1:$port", "system")
        val p = builder.start()
        process = p

        val outPump = pump(p.inputStream.bufferedReader(), "stdout")
        val errPump = pump(p.errorStream.bufferedReader(), "stderr")

        thread(name = "care-dsh-wait", isDaemon = true) {
            val code = try { p.waitFor() } catch (_: InterruptedException) { -1 }
            try {
                outPump.join(1500)
                errPump.join(1500)
            } catch (_: InterruptedException) {}
            process = null
            listener.onExit(code, expectedExit)
        }
    }

    fun stop() {
        expectedExit = true
        val p = process ?: return
        p.destroy()
        thread(name = "care-dsh-stop", isDaemon = true) {
            try {
                if (!p.waitFor(2500, java.util.concurrent.TimeUnit.MILLISECONDS)) {
                    p.destroyForcibly()
                }
            } catch (_: InterruptedException) {
                p.destroyForcibly()
            }
        }
    }

    private fun pump(reader: BufferedReader, stream: String): Thread =
        thread(name = "care-dsh-$stream", isDaemon = true) {
            reader.useLines { lines ->
                for (raw in lines) {
                    if (!readyReported) {
                        val match = READY_URL_REGEX.find(raw)
                        if (match != null) {
                            readyReported = true
                            val baseUrl = match.groupValues[1]
                            val token = match.groupValues[2]
                            listener.onReady(baseUrl, token)
                        }
                    }
                    listener.onLog(SecretRedactor.redact(raw), stream)
                }
            }
        }

    private fun pickLoopbackPort(): Int {
        val candidates = listOf(DEFAULT_PORT, 0)
        for (candidate in candidates) {
            runCatching {
                ServerSocket(candidate, 1, InetAddress.getByName("127.0.0.1")).use { return it.localPort }
            }
        }
        return DEFAULT_PORT
    }

    companion object {
        const val DEFAULT_PORT = 3080
        private const val GUEST_ENV_PLACEHOLDER = "{GUEST_ENV}"
        private val READY_URL_REGEX = Regex("""(http://127\.0\.0\.1:\d+)/?#?token=([A-Za-z0-9._~-]+)""")
    }
}
