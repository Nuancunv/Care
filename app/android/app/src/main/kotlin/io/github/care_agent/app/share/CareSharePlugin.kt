package io.github.care_agent.app.share

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.care_agent.app.workspace.CareWorkspacePathGuard
import io.github.care_agent.app.workspace.OfficeTextExtractor
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * Receives Android system Share Intents (`ACTION_SEND`) — text, URLs, images,
 * PDFs, Office docs, and files — so users can send or save content from any app
 * straight into a chosen Bot's chat or `资料库/`.
 */
class CareSharePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods = MethodChannel(binding.binaryMessenger, "care/share").also {
            it.setMethodCallHandler(this)
        }
        events = EventChannel(binding.binaryMessenger, "care/share/events").also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods?.setMethodCallHandler(null)
        methods = null
        events?.setStreamHandler(null)
        events = null
        synchronized(LOCK) { eventSink = null }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takePendingShare" -> {
                val payload = synchronized(LOCK) {
                    val p = pendingPayload
                    pendingPayload = null
                    p
                }
                result.success(payload)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val queued = synchronized(LOCK) {
            eventSink = events
            val p = pendingPayload
            pendingPayload = null
            p
        }
        if (queued != null && events != null) {
            mainHandler.post { events.success(queued) }
        }
    }

    override fun onCancel(arguments: Any?) {
        synchronized(LOCK) { eventSink = null }
    }

    companion object {
        private val LOCK = Any()
        private val mainHandler = Handler(Looper.getMainLooper())
        private val ioExecutor = Executors.newSingleThreadExecutor()
        private var eventSink: EventChannel.EventSink? = null
        private var pendingPayload: Map<String, Any>? = null

        fun handleIntent(context: Context, intent: Intent?) {
            if (intent == null || intent.action != Intent.ACTION_SEND) return
            val appCtx = context.applicationContext
            val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim() ?: ""
            val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim() ?: ""
            val streamUri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }

            if (sharedText.isEmpty() && streamUri == null) return

            ioExecutor.execute {
                try {
                    val payload = buildPayload(appCtx, subject, sharedText, streamUri, intent.type)
                    if (payload != null) {
                        emit(payload)
                    }
                } catch (_: Exception) {
                }
            }
        }

        private fun emit(payload: Map<String, Any>) {
            val sink = synchronized(LOCK) {
                val s = eventSink
                if (s == null) {
                    pendingPayload = payload
                }
                s
            }
            if (sink != null) {
                mainHandler.post { sink.success(payload) }
            }
        }

        private fun buildPayload(
            ctx: Context,
            subject: String,
            sharedText: String,
            uri: Uri?,
            intentMime: String?,
        ): Map<String, Any>? {
            if (uri == null) {
                return mapOf(
                    "kind" to "text",
                    "subject" to subject,
                    "text" to sharedText,
                )
            }

            val resolver = ctx.contentResolver
            var name = "shared_file"
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) name = c.getString(idx) ?: name
                }
            }
            val mime = resolver.getType(uri) ?: intentMime ?: "application/octet-stream"
            val isImage = mime.startsWith("image/")
            val safeName = CareWorkspacePathGuard.sanitizeFileName(
                if (name.contains('.')) name else if (isImage) "$name.jpg" else "$name.txt"
            )

            // Stage a copy into cacheDir/shared/ so Flutter can import it into any Bot's 资料库/ later.
            val shareDir = File(ctx.cacheDir, "shared").apply {
                mkdirs()
                listFiles()?.forEach { old ->
                    if (System.currentTimeMillis() - old.lastModified() > 30 * 60 * 1000L) {
                        old.delete()
                    }
                }
            }
            val staged = File(shareDir, "${System.currentTimeMillis()}_$safeName")
            resolver.openInputStream(uri)?.use { input ->
                staged.outputStream().use { output ->
                    val buf = ByteArray(8192)
                    var total = 0L
                    while (total < 20L * 1024 * 1024) {
                        val n = input.read(buf)
                        if (n <= 0) break
                        output.write(buf, 0, n)
                        total += n
                    }
                }
            } ?: return null

            var base64Img = ""
            var textContent = ""
            if (isImage) {
                base64Img = encodeResizedImage(staged)
            } else {
                val bytes = staged.readBytes()
                textContent = if (OfficeTextExtractor.isOfficeFile(safeName)) {
                    OfficeTextExtractor.extract(safeName, bytes) ?: ""
                } else if (bytes.size <= 128 * 1024 && bytes.none { it.toInt() == 0 }) {
                    String(bytes, Charsets.UTF_8)
                } else {
                    ""
                }
            }

            return mapOf(
                "kind" to (if (isImage) "image" else "file"),
                "subject" to subject,
                "text" to sharedText,
                "fileName" to safeName,
                "mimeType" to (if (isImage) "image/jpeg" else mime),
                "sizeBytes" to staged.length(),
                "stagedPath" to staged.canonicalPath,
                "isImage" to isImage,
                "base64Image" to base64Img,
                "textContent" to textContent,
            )
        }

        private fun encodeResizedImage(file: File): String {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.path, bounds)
            var sample = 1
            val maxDim = maxOf(bounds.outWidth, bounds.outHeight)
            while (maxDim / sample > 1280) sample *= 2
            val bmp = BitmapFactory.decodeFile(
                file.path,
                BitmapFactory.Options().apply { inSampleSize = sample },
            ) ?: return ""
            return try {
                val out = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.JPEG, 82, out)
                Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
            } finally {
                bmp.recycle()
            }
        }
    }
}
