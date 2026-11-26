package io.github.care_agent.app.workspace

import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream

/**
 * Pure JVM zero-dependency text extractor for Office Open XML formats
 * (`.docx`, `.pptx`, `.xlsx`) so Care's per-Bot `资料库/` Notebook search
 * and attachment reader can natively understand Word/PPT/Excel files
 * with ZERO APK size bloat.
 */
object OfficeTextExtractor {
    private const val MAX_OUTPUT_CHARS = 96 * 1024

    fun isOfficeFile(fileName: String): Boolean {
        val lower = fileName.lowercase()
        return lower.endsWith(".docx") || lower.endsWith(".pptx") || lower.endsWith(".xlsx")
    }

    fun extract(fileName: String, bytes: ByteArray): String? {
        val lower = fileName.lowercase()
        return try {
            when {
                lower.endsWith(".docx") -> extractDocx(bytes)
                lower.endsWith(".pptx") -> extractPptx(bytes)
                lower.endsWith(".xlsx") -> extractXlsx(bytes)
                else -> null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun extractDocx(bytes: ByteArray): String? {
        ZipInputStream(ByteArrayInputStream(bytes)).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                if (entry.name == "word/document.xml") {
                    val xml = zis.readBytes().toString(Charsets.UTF_8)
                    val out = extractParagraphXml(xml, paraTag = "w:p", textTag = "w:t")
                    return out.ifBlank { null }
                }
                entry = zis.nextEntry
            }
        }
        return null
    }

    private fun extractPptx(bytes: ByteArray): String? {
        val slides = mutableListOf<Pair<Int, String>>()
        val slideRegex = Regex("^ppt/slides/slide(\\d+)\\.xml$")
        ZipInputStream(ByteArrayInputStream(bytes)).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                val match = slideRegex.matchEntire(entry.name)
                if (match != null) {
                    val idx = match.groupValues[1].toIntOrNull() ?: 0
                    val xml = zis.readBytes().toString(Charsets.UTF_8)
                    val text = extractParagraphXml(xml, paraTag = "a:p", textTag = "a:t")
                    if (text.isNotBlank()) {
                        slides.add(idx to text)
                    }
                }
                entry = zis.nextEntry
            }
        }
        if (slides.isEmpty()) return null
        val sb = StringBuilder()
        for ((idx, text) in slides.sortedBy { it.first }) {
            if (sb.length >= MAX_OUTPUT_CHARS) break
            sb.append("## 第 ").append(idx).append(" 页\n").append(text).append("\n\n")
        }
        return sb.toString().trim().take(MAX_OUTPUT_CHARS)
    }

    private fun extractXlsx(bytes: ByteArray): String? {
        ZipInputStream(ByteArrayInputStream(bytes)).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                if (entry.name == "xl/sharedStrings.xml") {
                    val xml = zis.readBytes().toString(Charsets.UTF_8)
                    val text = extractParagraphXml(xml, paraTag = "si", textTag = "t")
                    return text.ifBlank { null }
                }
                entry = zis.nextEntry
            }
        }
        return null
    }

    private fun extractParagraphXml(xml: String, paraTag: String, textTag: String): String {
        val paraRegex = Regex("<$paraTag(?:\\s[^>]*)?>(.*?)</$paraTag>", RegexOption.DOT_MATCHES_ALL)
        val textRegex = Regex("<$textTag(?:\\s[^>]*)?>(.*?)</$textTag>", RegexOption.DOT_MATCHES_ALL)
        val sb = StringBuilder()
        for (p in paraRegex.findAll(xml)) {
            if (sb.length >= MAX_OUTPUT_CHARS) break
            val line = StringBuilder()
            for (t in textRegex.findAll(p.groupValues[1])) {
                line.append(unescapeXml(t.groupValues[1]))
            }
            val cleaned = line.toString().trim()
            if (cleaned.isNotEmpty()) {
                sb.append(cleaned).append('\n')
            }
        }
        if (sb.isEmpty()) {
            // Fallback: grab all textTag occurrences directly
            for (t in textRegex.findAll(xml)) {
                if (sb.length >= MAX_OUTPUT_CHARS) break
                val piece = unescapeXml(t.groupValues[1]).trim()
                if (piece.isNotEmpty()) sb.append(piece).append('\n')
            }
        }
        return sb.toString().trim().take(MAX_OUTPUT_CHARS)
    }

    private fun unescapeXml(raw: String): String = raw
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
}
