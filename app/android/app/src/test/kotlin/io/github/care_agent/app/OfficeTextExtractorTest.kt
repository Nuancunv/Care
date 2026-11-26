package io.github.care_agent.app

import io.github.care_agent.app.workspace.OfficeTextExtractor
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class OfficeTextExtractorTest {

    private fun buildZip(entries: Map<String, String>): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zos ->
            for ((name, content) in entries) {
                zos.putNextEntry(ZipEntry(name))
                zos.write(content.toByteArray(Charsets.UTF_8))
                zos.closeEntry()
            }
        }
        return out.toByteArray()
    }

    @Test
    fun extractsDocxParagraphs() {
        val docx = buildZip(
            mapOf(
                "word/document.xml" to
                    "<w:document><w:body><w:p><w:r><w:t>线性代数第一章</w:t></w:r></w:p>" +
                    "<w:p><w:r><w:t>矩阵与特征值</w:t></w:r></w:p></w:body></w:document>"
            )
        )
        val text = OfficeTextExtractor.extract("notes.docx", docx)
        assertNotNull(text)
        assertTrue(text!!.contains("线性代数第一章"))
        assertTrue(text.contains("矩阵与特征值"))
    }

    @Test
    fun extractsPptxSlidesInOrder() {
        val pptx = buildZip(
            mapOf(
                "ppt/slides/slide2.xml" to "<p:sld><a:p><a:t>第二页总结</a:t></a:p></p:sld>",
                "ppt/slides/slide1.xml" to "<p:sld><a:p><a:t>第一页标题</a:t></a:p></p:sld>",
            )
        )
        val text = OfficeTextExtractor.extract("lecture.pptx", pptx)
        assertNotNull(text)
        assertTrue(text!!.indexOf("第一页标题") < text.indexOf("第二页总结"))
    }

    @Test
    fun extractsXlsxSharedStrings() {
        val xlsx = buildZip(
            mapOf(
                "xl/sharedStrings.xml" to "<sst><si><t>月度预算</t></si><si><t>饮食开销</t></si></sst>"
            )
        )
        val text = OfficeTextExtractor.extract("budget.xlsx", xlsx)
        assertNotNull(text)
        assertTrue(text!!.contains("月度预算"))
        assertTrue(text.contains("饮食开销"))
    }
}
