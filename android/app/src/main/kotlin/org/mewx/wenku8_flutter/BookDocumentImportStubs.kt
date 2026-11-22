package org.mewx.wenku8_flutter

import android.app.Activity
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import java.io.File

/**
 * 公开源码构建的文档转换占位实现。
 *
 * 公开构建保留纯 Dart 转换；这里只补齐 PDF 的文本提取和暂存回退。
 */
internal class BookPdfImport(activity: Activity,
                            @Suppress("UNUSED_PARAMETER") root: File) {
    init {
        PDFBoxResourceLoader.init(activity.applicationContext)
    }

    fun read(file: File): String? = try {
        PDDocument.load(file).use { document ->
            PDFTextStripper().getText(document).trim().ifEmpty { null }
        }
    } catch (_: Exception) {
        null
    }
}

internal class BookMarkupImport(@Suppress("UNUSED_PARAMETER") root: File,
                                private val reader: (File) -> String?) {
    fun convert(source: File, target: File): Boolean {
        if (source.extension.lowercase() != "pdf") return false
        val text = reader(source)?.trim().orEmpty()
        if (text.isEmpty()) return false
        return try {
            target.parentFile?.mkdirs()
            target.writeText(text)
            target.length() > 0
        } catch (_: Exception) {
            false
        }
    }
}

internal class BookArchiveImport(private val root: File) {
    var documents: BookMarkupImport? = null

    companion object {
        const val MAX_ARCHIVE: Long = 512L * 1024L * 1024L
        val supportedExtensions = setOf(
            "txt", "epub", "mobi", "azw", "azw3", "prc", "fb2", "pdf",
            "docx", "odt", "rtf", "html", "htm", "xhtml", "md", "markdown", "zip",
        )

        fun supported(name: String): Boolean =
            name.substringAfterLast('.', "").lowercase() in supportedExtensions

        fun limit(name: String): Long = when (name.substringAfterLast('.', "").lowercase()) {
            "epub", "pdf", "docx", "odt", "zip" -> 512L * 1024L * 1024L
            "mobi", "azw", "azw3", "prc" -> 256L * 1024L * 1024L
            "html", "htm", "xhtml", "md", "markdown" -> 32L * 1024L * 1024L
            else -> 128L * 1024L * 1024L
        }
    }

    fun prepare(name: String, source: BookDocumentInput): List<Map<String, Any?>> =
        copy(name, source.file)

    fun prepare(name: String, source: File): List<Map<String, Any?>> = copy(name, source)

    private fun copy(name: String, source: File?): List<Map<String, Any?>> {
        if (source == null || !source.isFile) {
            return listOf(mapOf("name" to name, "path" to null, "error" to "源文件不可读取"))
        }
        val safe = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        return try {
            if (source.extension.equals("pdf", ignoreCase = true) && documents != null) {
                val target = File(root, safe.substringBeforeLast('.', safe) + ".txt")
                if (documents!!.convert(source, target)) {
                    return listOf(mapOf("name" to target.name, "path" to target.path, "error" to null))
                }
                return listOf(mapOf("name" to name, "path" to null, "error" to "PDF 没有可提取的文字"))
            }
            val target = File(root, safe).apply { parentFile?.mkdirs() }
            source.copyTo(target, overwrite = true)
            listOf(mapOf("name" to name, "path" to target.path, "error" to null))
        } catch (error: Exception) {
            listOf(mapOf("name" to name, "path" to null, "error" to (error.message ?: "文档暂存失败")))
        }
    }
}
