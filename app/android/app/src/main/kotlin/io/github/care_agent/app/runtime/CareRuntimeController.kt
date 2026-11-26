// Adapted from ccch1mneyyy/dsh-Go (AGPL-3.0); see root THIRD_PARTY_NOTICES.md.
package io.github.care_agent.app.runtime

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

/**
 * Single source of truth on Android Kotlin side for local PRoot runtime lifecycle (AGENTS.md §3.2).
 * Flutter Dart layer mirrors status snapshots over EventChannel `care/runtime/events`.
 */
class CareRuntimeController private constructor(private val app: Context) : CareRuntimeProcess.Listener {
    enum class Phase(val wire: String) {
        NOT_BUNDLED("notBundled"),
        NOT_INSTALLED("notInstalled"),
        INSTALLING("installing"),
        INSTALLED("installed"),
        STARTING("starting"),
        RUNNING("running"),
        STOPPING("stopping"),
        ERROR("error"),
    }

    fun interface EventSink {
        fun emit(event: Map<String, Any?>)
    }

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "care-runtime") }
    private val sinks = LinkedHashSet<EventSink>()
    private val logRing = ArrayDeque<String>()

    private val manifest: RuntimeManifest? = RuntimeManifest.loadOrNull(app)
    private val installer: CareRuntimeInstaller? = manifest?.let { CareRuntimeInstaller(app, it, ::appendLog) }

    @Volatile var phase: Phase = Phase.NOT_BUNDLED
        private set
    @Volatile private var baseUrl: String? = null
    @Volatile private var token: String? = null
    @Volatile private var errorMessage: String? = null
    @Volatile private var installBytesRead: Long = 0L
    @Volatile private var installBytesTotal: Long = 0L
    @Volatile private var activeProcess: CareRuntimeProcess? = null
    @Volatile private var idleSleepMinutes: Int = 15
    private val idleSleepRunnable = Runnable {
        if (phase == Phase.RUNNING) {
            appendLog("[care] idle sleep timeout (${idleSleepMinutes}m) reached in background; stopping local runtime to save battery")
            stop()
        }
    }

    fun setIdleSleepMinutes(minutes: Int) {
        idleSleepMinutes = minutes.coerceIn(0, 240)
    }

    fun onAppForegrounded() {
        main.removeCallbacks(idleSleepRunnable)
    }

    fun onAppBackgrounded() {
        main.removeCallbacks(idleSleepRunnable)
        val mins = idleSleepMinutes
        if (mins > 0 && phase == Phase.RUNNING) {
            main.postDelayed(idleSleepRunnable, mins * 60_000L)
        }
    }

    init {
        phase = when {
            manifest == null -> Phase.NOT_BUNDLED
            installer?.isCurrent() == true -> Phase.INSTALLED
            else -> Phase.NOT_INSTALLED
        }
    }

    fun addSink(sink: EventSink) = synchronized(sinks) { sinks += sink }
    fun removeSink(sink: EventSink) = synchronized(sinks) { sinks -= sink }

    fun status(): Map<String, Any?> = mapOf(
        "abi" to (manifest?.abi ?: Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"),
        "bundledVersion" to manifest?.runtimeVersion,
        "installedVersion" to installer?.installedVersion(),
        "dshVersion" to manifest?.dshVersion,
        "nodeVersion" to manifest?.nodeVersion,
        "phase" to phase.wire,
        "baseUrl" to baseUrl,
        "token" to token,
        "error" to errorMessage,
        "installBytesRead" to installBytesRead,
        "installBytesTotal" to installBytesTotal,
    )

    fun recentLogs(maxLines: Int = 200): List<String> = synchronized(logRing) {
        val count = maxLines.coerceIn(0, logRing.size)
        logRing.takeLast(count)
    }

    fun install(onComplete: (Throwable?) -> Unit) {
        val currentInstaller = installer
        if (currentInstaller == null) {
            val err = IllegalStateException("No offline ARM64 runtime bundled in this APK build.")
            main.post { onComplete(err) }
            return
        }
        if (phase == Phase.INSTALLING) {
            main.post { onComplete(IllegalStateException("Install already in progress")) }
            return
        }
        phase = Phase.INSTALLING
        errorMessage = null
        installBytesRead = 0L
        installBytesTotal = 0L
        CareRuntimeService.start(app, CareRuntimeService.ACTION_INSTALL)
        emitStatus()

        worker.execute {
            try {
                currentInstaller.install { read, total ->
                    installBytesRead = read
                    installBytesTotal = total
                    emitStatus()
                }
                phase = Phase.INSTALLED
                CareRuntimeService.start(app, CareRuntimeService.ACTION_STOP)
                emitStatus()
                main.post { onComplete(null) }
            } catch (t: Throwable) {
                phase = Phase.ERROR
                errorMessage = SecretRedactor.redact(t.message ?: t.toString())
                CareRuntimeService.start(app, CareRuntimeService.ACTION_STOP)
                emitStatus()
                main.post { onComplete(t) }
            }
        }
    }

    fun start(guestEnv: Map<String, String>) {
        val m = manifest ?: run {
            phase = Phase.NOT_BUNDLED
            errorMessage = "Offline runtime archive not bundled yet."
            emitStatus()
            return
        }
        val inst = installer ?: return
        if (phase == Phase.RUNNING || phase == Phase.STARTING) return
        if (!inst.isCurrent()) {
            errorMessage = "Offline runtime is not installed yet."
            phase = Phase.NOT_INSTALLED
            emitStatus()
            return
        }
        phase = Phase.STARTING
        errorMessage = null
        baseUrl = null
        token = null
        CareRuntimeService.start(app, CareRuntimeService.ACTION_RUN)
        emitStatus()

        worker.execute {
            try {
                val proc = CareRuntimeProcess(app, m, inst.rootfs, this)
                activeProcess = proc
                proc.start(guestEnv)
            } catch (t: Throwable) {
                activeProcess = null
                phase = Phase.ERROR
                errorMessage = SecretRedactor.redact(t.message ?: t.toString())
                CareRuntimeService.start(app, CareRuntimeService.ACTION_STOP)
                emitStatus()
            }
        }
    }

    fun stop() {
        val proc = activeProcess
        if (proc == null) {
            if (phase == Phase.RUNNING || phase == Phase.STARTING) {
                phase = if (installer?.isCurrent() == true) Phase.INSTALLED else Phase.NOT_INSTALLED
                baseUrl = null
                token = null
                CareRuntimeService.start(app, CareRuntimeService.ACTION_STOP)
                emitStatus()
            }
            return
        }
        phase = Phase.STOPPING
        emitStatus()
        proc.stop()
    }

    override fun onLog(line: String, stream: String) {
        appendLog("[$stream] $line")
    }

    override fun onReady(baseUrl: String, token: String) {
        this.baseUrl = baseUrl
        this.token = token
        this.phase = Phase.RUNNING
        this.errorMessage = null
        emitStatus()
    }

    override fun onExit(code: Int, expected: Boolean) {
        activeProcess = null
        baseUrl = null
        token = null
        CareRuntimeService.start(app, CareRuntimeService.ACTION_STOP)
        if (expected || code == 0) {
            phase = if (installer?.isCurrent() == true) Phase.INSTALLED else Phase.NOT_INSTALLED
        } else {
            phase = Phase.ERROR
            errorMessage = "Local runtime exited unexpectedly (code $code)"
        }
        emitStatus()
    }

    private fun appendLog(line: String) {
        val safe = SecretRedactor.redact(line)
        synchronized(logRing) {
            if (logRing.size >= MAX_LOG_LINES) logRing.removeFirst()
            logRing.addLast(safe)
        }
        emit(mapOf("type" to "log", "line" to safe))
    }

    private fun emitStatus() {
        emit(mapOf("type" to "status", "status" to status()))
    }

    private fun emit(event: Map<String, Any?>) {
        main.post {
            val targets = synchronized(sinks) { sinks.toList() }
            targets.forEach { it.emit(event) }
        }
    }

    companion object {
        private const val MAX_LOG_LINES = 500
        @Volatile private var instance: CareRuntimeController? = null

        fun get(context: Context): CareRuntimeController =
            instance ?: synchronized(this) {
                instance ?: CareRuntimeController(context.applicationContext).also { instance = it }
            }
    }
}
