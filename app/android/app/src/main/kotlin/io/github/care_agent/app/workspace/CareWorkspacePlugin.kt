package io.github.care_agent.app.workspace

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Base64
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.github.care_agent.app.vault.PrivacyVaultPathGuard
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * Validates relative paths inside a per-bot local workspace (blocks traversal & absolute paths).
 */
object CareWorkspacePathGuard {
    private val SAFE_SEGMENT =
        Regex("^[a-zA-Z0-9._\\-\\u4e00-\\u9fff ()（）\\[\\]【】+&#]{1,100}$")

    fun normalizeRelativePath(raw: String): String {
        val cleaned = raw.trim().replace('\\', '/').trimStart('/')
        require(cleaned.isNotEmpty() && cleaned.length <= 260) { "Invalid workspace path." }
        val parts = cleaned.split('/').filter { it.isNotEmpty() }
        require(parts.isNotEmpty()) { "Empty workspace path." }
        for (seg in parts) {
            require(seg != "." && seg != ".." && !seg.startsWith(".") && SAFE_SEGMENT.matches(seg)) {
                "Unsafe path segment: $seg"
            }
        }
        return parts.joinToString("/")
    }

    fun sanitizeFileName(raw: String): String {
        val base = raw.trim().replace('\\', '/').substringAfterLast('/')
        val cleaned = base.replace(Regex("[^a-zA-Z0-9._\\-\\u4e00-\\u9fff ()（）\\[\\]【】+&#]"), "_")
            .trimStart('.')
            .trim()
        val safe = if (cleaned.isEmpty()) "material_${System.currentTimeMillis()}.txt" else cleaned
        return if (safe.length > 90) safe.take(90) else safe
    }
}

/**
 * Native per-bot Agent Workspace, Knowledge Library (`资料库/`),
 * 3-way Attachment Picker (file / camera / photo), and Default-App Opener (`care/workspace`).
 *
 * - Normal bots store files under `filesDir/care_workspace/<botId>/` with `资料库/` pre-created.
 * - Privacy Bots (`isPrivate=true`) store files physically isolated under
 *   `filesDir/care_privacy_vault/<botId>/workspace/` (AGENTS.md §1.4) and are NEVER exposed via FileProvider.
 */
class CareWorkspacePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var appContext: Context
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var pendingPickerResult: MethodChannel.Result? = null
    private var pendingCameraFile: File? = null
    private var pendingLibraryTarget: Pair<String, Boolean>? = null
    private val ioExecutor = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "care/workspace").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        ioExecutor.shutdownNow()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        this.binding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        binding?.removeActivityResultListener(this)
        binding = null
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
            "listFiles" -> {
                try {
                    val dir = resolveWorkspaceRoot(
                        call.argument<String>("botId") ?: "chief",
                        call.argument<Boolean>("isPrivate") == true,
                    )
                    ensureLibraryFolder(dir)
                    val rootPath = dir.canonicalPath
                    val items = dir.walkTopDown()
                        .filter { it.isFile }
                        .map { file ->
                            val rel = file.canonicalPath
                                .removePrefix(rootPath)
                                .trimStart(File.separatorChar)
                                .replace(File.separatorChar, '/')
                            mapOf<String, Any>(
                                "path" to rel,
                                "sizeBytes" to file.length(),
                                "modifiedAtMs" to file.lastModified(),
                            )
                        }
                        .sortedByDescending { (it["modifiedAtMs"] as Number).toLong() }
                        .take(200)
                        .toList()
                    result.success(items)
                } catch (err: Exception) {
                    result.error("WORKSPACE_LIST_FAILED", err.message, null)
                }
            }
            "readFile" -> {
                try {
                    val file = resolveWorkspaceFile(
                        call.argument<String>("botId") ?: "chief",
                        call.argument<Boolean>("isPrivate") == true,
                        call.argument<String>("path") ?: "",
                    )
                    if (!file.exists() || !file.isFile) {
                        result.success(null)
                        return
                    }
                    val bytes = file.readBytes()
                    if (OfficeTextExtractor.isOfficeFile(file.name)) {
                        val extracted = OfficeTextExtractor.extract(file.name, bytes)
                        result.success(
                            extracted
                                ?: "[Office 文件：${file.name}（${file.length()} 字节），请点击「默认应用打开」查看]"
                        )
                        return
                    }
                    val mime = guessMimeFromName(file.name)
                    if (!isLikelyText(mime, file.name, bytes)) {
                        result.success(
                            "[二进制文件：${file.name}（${file.length()} 字节），请点击「默认应用打开」查看]"
                        )
                        return
                    }
                    val capped = if (bytes.size > MAX_TEXT_READ_BYTES) {
                        String(bytes, 0, MAX_TEXT_READ_BYTES, Charsets.UTF_8) + "\n\n... [truncated]"
                    } else {
                        String(bytes, Charsets.UTF_8)
                    }
                    result.success(capped)
                } catch (err: Exception) {
                    result.error("WORKSPACE_READ_FAILED", err.message, null)
                }
            }
            "writeFile" -> {
                try {
                    val botId = call.argument<String>("botId") ?: "chief"
                    val isPrivate = call.argument<Boolean>("isPrivate") == true
                    val rawPath = call.argument<String>("path") ?: ""
                    ensureLibraryFolder(resolveWorkspaceRoot(botId, isPrivate))
                    val file = resolveWorkspaceFile(botId, isPrivate, rawPath)
                    val content = call.argument<String>("content") ?: ""
                    file.parentFile?.mkdirs()
                    val tmp = File(file.parentFile, "${file.name}.tmp")
                    tmp.writeText(content, Charsets.UTF_8)
                    if (!tmp.renameTo(file)) {
                        file.writeText(content, Charsets.UTF_8)
                        tmp.delete()
                    }
                    result.success(
                        mapOf(
                            "ok" to true,
                            "path" to CareWorkspacePathGuard.normalizeRelativePath(rawPath),
                            "sizeBytes" to file.length(),
                        )
                    )
                } catch (err: Exception) {
                    result.error("WORKSPACE_WRITE_FAILED", err.message, null)
                }
            }
            "deleteFile" -> {
                try {
                    val file = resolveWorkspaceFile(
                        call.argument<String>("botId") ?: "chief",
                        call.argument<Boolean>("isPrivate") == true,
                        call.argument<String>("path") ?: "",
                    )
                    val deleted = !file.exists() || file.delete()
                    result.success(deleted)
                } catch (err: Exception) {
                    result.error("WORKSPACE_DELETE_FAILED", err.message, null)
                }
            }
            "pickAttachment" -> {
                val mode = call.argument<String>("mode") ?: "file"
                when (mode) {
                    "camera" -> launchCameraCapture(result)
                    "photo", "image" -> launchPhotoPicker(result)
                    else -> launchDocumentPicker(result)
                }
            }
            "importToLibrary" -> {
                val botId = call.argument<String>("botId") ?: "chief"
                val isPrivate = call.argument<Boolean>("isPrivate") == true
                launchLibraryImportPicker(botId, isPrivate, result)
            }
            "importStagedToLibrary" -> {
                try {
                    val botId = call.argument<String>("botId") ?: "chief"
                    val isPrivate = call.argument<Boolean>("isPrivate") == true
                    val stagedPath = call.argument<String>("stagedPath") ?: ""
                    val fileName = call.argument<String>("fileName") ?: "shared.txt"
                    val src = File(stagedPath).canonicalFile
                    val shareRoot = File(appContext.cacheDir, "shared").canonicalFile
                    require(src.path.startsWith(shareRoot.path + File.separator) && src.isFile) {
                        "Invalid staged share file."
                    }
                    val safeName = CareWorkspacePathGuard.sanitizeFileName(fileName)
                    val libDir = ensureLibraryFolder(resolveWorkspaceRoot(botId, isPrivate))
                    val dest = File(libDir, safeName)
                    src.copyTo(dest, overwrite = true)
                    result.success(
                        mapOf(
                            "ok" to true,
                            "path" to "$LIBRARY_DIR/$safeName",
                            "sizeBytes" to dest.length(),
                        )
                    )
                } catch (err: Exception) {
                    result.error("IMPORT_STAGED_FAILED", err.message, null)
                }
            }
            "searchLibrary" -> {
                try {
                    val botId = call.argument<String>("botId") ?: "chief"
                    val isPrivate = call.argument<Boolean>("isPrivate") == true
                    val query = (call.argument<String>("query") ?: "").trim()
                    val hits = searchLibraryFiles(botId, isPrivate, query)
                    result.success(hits)
                } catch (err: Exception) {
                    result.error("LIBRARY_SEARCH_FAILED", err.message, null)
                }
            }
            "openHtmlPreview" -> {
                try {
                    val botId = call.argument<String>("botId") ?: "chief"
                    val isPrivate = call.argument<Boolean>("isPrivate") == true
                    val path = call.argument<String>("path") ?: ""
                    val file = resolveWorkspaceFile(botId, isPrivate, path)
                    if (!file.exists() || !file.isFile) {
                        result.success(false)
                        return
                    }
                    val act = activity
                    if (act == null) {
                        result.success(false)
                        return
                    }
                    val html = file.readText(Charsets.UTF_8)
                    val intent = Intent(act, CareHtmlPreviewActivity::class.java).apply {
                        putExtra(CareHtmlPreviewActivity.EXTRA_TITLE, file.name)
                        putExtra(CareHtmlPreviewActivity.EXTRA_HTML, html)
                    }
                    act.startActivity(intent)
                    result.success(true)
                } catch (err: Exception) {
                    result.error("HTML_PREVIEW_FAILED", err.message, null)
                }
            }
            "openWithExternalApp" -> {
                try {
                    val botId = call.argument<String>("botId") ?: "chief"
                    val isPrivate = call.argument<Boolean>("isPrivate") == true
                    if (isPrivate) {
                        result.success(false)
                        return
                    }
                    val path = call.argument<String>("path") ?: ""
                    val file = resolveWorkspaceFile(botId, false, path)
                    val act = activity
                    if (act == null || !file.exists() || !file.isFile) {
                        result.success(false)
                        return
                    }
                    val uri = FileProvider.getUriForFile(
                        appContext,
                        "${appContext.packageName}.fileprovider",
                        file,
                    )
                    val mime = guessMimeFromName(file.name)
                    val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, mime)
                        clipData = ClipData.newRawUri(file.name, uri)
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_ACTIVITY_NEW_TASK,
                        )
                    }
                    try {
                        // Direct ACTION_VIEW invokes the system default app (or native resolver).
                        act.startActivity(viewIntent)
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        // Fallback to generic text/plain or wildcard chooser.
                        val fallbackIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, if (mime.startsWith("text/")) "text/plain" else "*/*")
                            clipData = ClipData.newRawUri(file.name, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        try {
                            val chooser = Intent.createChooser(fallbackIntent, "选择应用打开 ${file.name}").apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            act.startActivity(chooser)
                            result.success(true)
                        } catch (_: ActivityNotFoundException) {
                            result.success(false)
                        }
                    }
                } catch (err: Exception) {
                    result.error("EXTERNAL_OPEN_FAILED", err.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun resolveWorkspaceRoot(botId: String, isPrivate: Boolean): File {
        val safeBot = PrivacyVaultPathGuard.validateBotId(botId)
        return if (isPrivate) {
            File(File(File(appContext.filesDir, "care_privacy_vault"), safeBot), "workspace")
        } else {
            File(File(appContext.filesDir, "care_workspace"), safeBot)
        }
    }

    private fun ensureLibraryFolder(root: File): File {
        val lib = File(root, LIBRARY_DIR)
        if (!lib.exists()) {
            lib.mkdirs()
        }
        return lib
    }

    private fun resolveWorkspaceFile(botId: String, isPrivate: Boolean, rawPath: String): File {
        val root = resolveWorkspaceRoot(botId, isPrivate)
        val rel = CareWorkspacePathGuard.normalizeRelativePath(rawPath)
        val target = File(root, rel)
        val rootCanon = root.canonicalFile.path
        val targetCanon = target.canonicalFile.path
        require(targetCanon.startsWith(rootCanon + File.separator) || targetCanon == rootCanon) {
            "Resolved path escapes workspace."
        }
        return target
    }

    private fun searchLibraryFiles(
        botId: String,
        isPrivate: Boolean,
        query: String,
    ): List<Map<String, Any>> {
        val root = resolveWorkspaceRoot(botId, isPrivate)
        val libDir = ensureLibraryFolder(root)
        val terms = query.lowercase()
            .split(Regex("[\\s,，。！？?、;；:：]+"))
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        val results = mutableListOf<Pair<Int, Map<String, Any>>>()

        libDir.walkTopDown()
            .filter { it.isFile }
            .forEach { file ->
                val rel = "$LIBRARY_DIR/${file.relativeTo(libDir).path.replace(File.separatorChar, '/')}"
                val bytes = try {
                    file.readBytes()
                } catch (_: Exception) {
                    return@forEach
                }
                val mime = guessMimeFromName(file.name)
                val extractedOffice = if (OfficeTextExtractor.isOfficeFile(file.name)) {
                    OfficeTextExtractor.extract(file.name, bytes)
                } else {
                    null
                }
                if (extractedOffice == null && !isLikelyText(mime, file.name, bytes)) {
                    if (terms.isEmpty() || terms.any { file.name.lowercase().contains(it) }) {
                        results.add(
                            1 to mapOf(
                                "path" to rel,
                                "snippet" to "[附件文件：${file.name}，大小 ${file.length()} 字节]",
                            )
                        )
                    }
                    return@forEach
                }
                val text = extractedOffice ?: String(
                    bytes,
                    0,
                    minOf(bytes.size, MAX_TEXT_READ_BYTES),
                    Charsets.UTF_8,
                )
                if (terms.isEmpty()) {
                    results.add(
                        1 to mapOf(
                            "path" to rel,
                            "snippet" to text.take(400),
                        )
                    )
                    return@forEach
                }
                val lower = text.lowercase()
                val nameLower = file.name.lowercase()
                var score = 0
                var firstIdx = -1
                for (t in terms) {
                    if (nameLower.contains(t)) score += 4
                    val idx = lower.indexOf(t)
                    if (idx >= 0) {
                        score += 3
                        if (firstIdx < 0 || idx < firstIdx) firstIdx = idx
                    }
                }
                if (score > 0) {
                    val start = maxOf(0, (if (firstIdx >= 0) firstIdx else 0) - 120)
                    val end = minOf(text.length, start + 600)
                    val snippet = text.substring(start, end).trim()
                    results.add(
                        score to mapOf(
                            "path" to rel,
                            "snippet" to snippet,
                        )
                    )
                }
            }

        return results.sortedByDescending { it.first }.take(6).map { it.second }
    }

    private fun launchDocumentPicker(result: MethodChannel.Result) {
        val act = activity ?: run {
            result.success(null)
            return
        }
        pendingPickerResult?.success(null)
        pendingPickerResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
        }
        try {
            @Suppress("DEPRECATION")
            act.startActivityForResult(intent, REQ_PICK_ATTACHMENT)
        } catch (err: Exception) {
            pendingPickerResult = null
            result.error("PICKER_FAILED", err.message, null)
        }
    }

    private fun launchPhotoPicker(result: MethodChannel.Result) {
        val act = activity ?: run {
            result.success(null)
            return
        }
        pendingPickerResult?.success(null)
        pendingPickerResult = result

        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
        }
        try {
            @Suppress("DEPRECATION")
            act.startActivityForResult(intent, REQ_PICK_ATTACHMENT)
        } catch (err: Exception) {
            pendingPickerResult = null
            result.error("PHOTO_PICKER_FAILED", err.message, null)
        }
    }

    private fun launchCameraCapture(result: MethodChannel.Result) {
        val act = activity ?: run {
            result.success(null)
            return
        }
        pendingPickerResult?.success(null)
        pendingPickerResult = result

        try {
            val camDir = File(appContext.cacheDir, "camera").apply { mkdirs() }
            val photoFile = File(camDir, "capture_${System.currentTimeMillis()}.jpg")
            pendingCameraFile = photoFile
            val photoUri = FileProvider.getUriForFile(
                appContext,
                "${appContext.packageName}.fileprovider",
                photoFile,
            )
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
                clipData = ClipData.newRawUri("photo", photoUri)
                addFlags(
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            @Suppress("DEPRECATION")
            act.startActivityForResult(intent, REQ_CAPTURE_CAMERA)
        } catch (err: Exception) {
            pendingCameraFile?.delete()
            pendingCameraFile = null
            pendingPickerResult = null
            result.error("CAMERA_FAILED", err.message, null)
        }
    }

    private fun launchLibraryImportPicker(
        botId: String,
        isPrivate: Boolean,
        result: MethodChannel.Result,
    ) {
        val act = activity ?: run {
            result.success(null)
            return
        }
        pendingPickerResult?.success(null)
        pendingPickerResult = result
        pendingLibraryTarget = botId to isPrivate

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
        }
        try {
            @Suppress("DEPRECATION")
            act.startActivityForResult(intent, REQ_IMPORT_LIBRARY)
        } catch (err: Exception) {
            pendingLibraryTarget = null
            pendingPickerResult = null
            result.error("IMPORT_LIBRARY_FAILED", err.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQ_CAPTURE_CAMERA) {
            val pending = pendingPickerResult ?: return false
            pendingPickerResult = null
            val file = pendingCameraFile
            pendingCameraFile = null
            if (resultCode != Activity.RESULT_OK || file == null || !file.exists() || file.length() == 0L) {
                file?.delete()
                pending.success(null)
                return true
            }
            ioExecutor.execute {
                try {
                    val uri = Uri.fromFile(file)
                    val encoded = encodeResizedImageBase64(uri)
                    val size = file.length()
                    val name = "photo_${System.currentTimeMillis() % 100000}.jpg"
                    file.delete()
                    runOnUi {
                        pending.success(
                            mapOf(
                                "name" to name,
                                "mimeType" to "image/jpeg",
                                "sizeBytes" to size,
                                "isImage" to true,
                                "base64Image" to encoded,
                                "textContent" to "",
                            )
                        )
                    }
                } catch (err: Exception) {
                    file.delete()
                    runOnUi { pending.error("CAMERA_READ_FAILED", err.message, null) }
                }
            }
            return true
        }

        if (requestCode == REQ_IMPORT_LIBRARY) {
            val pending = pendingPickerResult ?: return false
            pendingPickerResult = null
            val target = pendingLibraryTarget
            pendingLibraryTarget = null
            val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
            if (uri == null || target == null) {
                pending.success(null)
                return true
            }
            ioExecutor.execute {
                try {
                    val imported = copyUriToLibrary(target.first, target.second, uri)
                    runOnUi { pending.success(imported) }
                } catch (err: Exception) {
                    runOnUi { pending.error("IMPORT_LIBRARY_FAILED", err.message, null) }
                }
            }
            return true
        }

        if (requestCode != REQ_PICK_ATTACHMENT) return false
        val pending = pendingPickerResult ?: return false
        pendingPickerResult = null

        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            pending.success(null)
            return true
        }

        ioExecutor.execute {
            try {
                val parsed = readAttachmentFromUri(uri)
                runOnUi { pending.success(parsed) }
            } catch (err: Exception) {
                runOnUi { pending.error("READ_ATTACHMENT_FAILED", err.message, null) }
            }
        }
        return true
    }

    private fun copyUriToLibrary(botId: String, isPrivate: Boolean, uri: Uri): Map<String, Any> {
        val resolver = appContext.contentResolver
        var rawName = "material.txt"
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) rawName = c.getString(idx) ?: rawName
            }
        }
        val safeName = CareWorkspacePathGuard.sanitizeFileName(rawName)
        val root = resolveWorkspaceRoot(botId, isPrivate)
        val libDir = ensureLibraryFolder(root)
        val dest = File(libDir, safeName)
        resolver.openInputStream(uri)?.use { input ->
            dest.outputStream().use { output ->
                val buf = ByteArray(8192)
                var total = 0L
                while (total < MAX_LIBRARY_FILE_BYTES) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    output.write(buf, 0, n)
                    total += n
                }
            }
        } ?: throw IllegalStateException("Cannot read selected file.")
        val relPath = "$LIBRARY_DIR/$safeName"
        return mapOf(
            "ok" to true,
            "path" to relPath,
            "sizeBytes" to dest.length(),
        )
    }

    private fun readAttachmentFromUri(uri: Uri): Map<String, Any> {
        val resolver = appContext.contentResolver
        var name = "attachment"
        var size = 0L
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIdx >= 0) name = cursor.getString(nameIdx) ?: name
                    if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) size = cursor.getLong(sizeIdx)
                }
            }

        val mime = resolver.getType(uri) ?: guessMimeFromName(name)
        val isImage = mime.startsWith("image/")

        if (isImage) {
            val encoded = encodeResizedImageBase64(uri)
            return mapOf(
                "name" to name,
                "mimeType" to "image/jpeg",
                "sizeBytes" to size,
                "isImage" to true,
                "base64Image" to encoded,
                "textContent" to "",
            )
        }

        val rawBytes = resolver.openInputStream(uri)?.use { input ->
            val cap = if (OfficeTextExtractor.isOfficeFile(name)) MAX_OFFICE_READ_BYTES else MAX_TEXT_READ_BYTES
            val out = ByteArrayOutputStream()
            val buf = ByteArray(8192)
            var total = 0
            while (total < cap) {
                val n = input.read(buf, 0, minOf(buf.size, cap - total))
                if (n <= 0) break
                out.write(buf, 0, n)
                total += n
            }
            out.toByteArray()
        } ?: ByteArray(0)

        val text = if (OfficeTextExtractor.isOfficeFile(name)) {
            OfficeTextExtractor.extract(name, rawBytes)
                ?: "[Office 文件：$name，暂未能提取正文内容]"
        } else if (isLikelyText(mime, name, rawBytes)) {
            String(rawBytes, Charsets.UTF_8)
        } else {
            "[二进制文件：$name，类型 $mime，大小 ${if (size > 0) size else rawBytes.size} 字节；建议导入到资料库并用默认应用打开]"
        }

        return mapOf(
            "name" to name,
            "mimeType" to mime,
            "sizeBytes" to (if (size > 0) size else rawBytes.size.toLong()),
            "isImage" to false,
            "base64Image" to "",
            "textContent" to text,
        )
    }

    private fun encodeResizedImageBase64(uri: Uri): String {
        val resolver = appContext.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }

        var sample = 1
        val maxDim = maxOf(bounds.outWidth, bounds.outHeight)
        while (maxDim / sample > 1280) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        val bmp = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
            ?: throw IllegalStateException("Unable to decode image.")
        try {
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, 82, out)
            return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
        } finally {
            bmp.recycle()
        }
    }

    private fun guessMimeFromName(name: String): String {
        val lower = name.lowercase()
        return when {
            lower.endsWith(".png") -> "image/png"
            lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
            lower.endsWith(".webp") -> "image/webp"
            lower.endsWith(".gif") -> "image/gif"
            lower.endsWith(".svg") -> "image/svg+xml"
            lower.endsWith(".html") || lower.endsWith(".htm") -> "text/html"
            lower.endsWith(".md") || lower.endsWith(".markdown") -> "text/plain"
            lower.endsWith(".json") -> "application/json"
            lower.endsWith(".csv") -> "text/csv"
            lower.endsWith(".xml") -> "application/xml"
            lower.endsWith(".pdf") -> "application/pdf"
            lower.endsWith(".doc") -> "application/msword"
            lower.endsWith(".docx") -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            lower.endsWith(".xls") -> "application/vnd.ms-excel"
            lower.endsWith(".xlsx") -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            lower.endsWith(".ppt") -> "application/vnd.ms-powerpoint"
            lower.endsWith(".pptx") -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
            lower.endsWith(".zip") -> "application/zip"
            lower.endsWith(".mp3") -> "audio/mpeg"
            lower.endsWith(".mp4") -> "video/mp4"
            else -> "text/plain"
        }
    }

    private fun isLikelyText(mime: String, name: String, bytes: ByteArray): Boolean {
        if (mime.startsWith("text/") || mime.contains("json") || mime.contains("xml") || mime.contains("javascript")) {
            return true
        }
        val lower = name.lowercase()
        val textExts = listOf(
            ".txt", ".md", ".markdown", ".json", ".yaml", ".yml", ".toml", ".csv", ".tsv",
            ".py", ".js", ".ts", ".jsx", ".tsx", ".dart", ".kt", ".java", ".c", ".cpp", ".h",
            ".go", ".rs", ".sh", ".ps1", ".sql", ".html", ".htm", ".css", ".xml", ".log", ".ini", ".env",
        )
        if (textExts.any { lower.endsWith(it) }) return true
        val checkLen = minOf(bytes.size, 2048)
        for (i in 0 until checkLen) {
            if (bytes[i].toInt() == 0) return false
        }
        return checkLen > 0
    }

    private fun runOnUi(block: () -> Unit) {
        val act = activity
        if (act != null) act.runOnUiThread(block) else block()
    }

    companion object {
        const val LIBRARY_DIR = "资料库"
        private const val REQ_PICK_ATTACHMENT = 4109
        private const val REQ_CAPTURE_CAMERA = 4110
        private const val REQ_IMPORT_LIBRARY = 4111
        private const val MAX_TEXT_READ_BYTES = 128 * 1024
        private const val MAX_OFFICE_READ_BYTES = 4 * 1024 * 1024
        private const val MAX_LIBRARY_FILE_BYTES = 20L * 1024 * 1024
    }
}
