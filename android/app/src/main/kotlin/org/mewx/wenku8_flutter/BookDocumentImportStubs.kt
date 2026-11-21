package org.mewx.wenku8_flutter

import android.app.Activity
import java.io.File

/**
 * 公开源码构建的文档转换占位实现。
 *
 * 上游公开仓库未包含 archive/markup/PDF 转换模块，这里提供可编译、
 * 可运行的降级实现：把原文件复制进应用暂存目录并返回，不进行格式转换。
 */
internal class BookPdfImport(@Suppress("UNUSED_PARAMETER") activity: Activity,
                             @Suppress("UNUSED_PARAMETER") root: File) {
    fun read(@Suppress("UNUSED_PARAMETER") file: File): String? = null
}

internal class BookMarkupImport(@Suppress("UNUSED_PARAMETER") root: File,
                                @Suppress("UNUSED_PARAMETER") reader: (File) -> String?) {
    @Suppress("UNUSED_PARAMETER")
    fun convert(source: File, target: File): Boolean = false
}

internal class BookArchiveImport(private val root: File) {
    var documents: Any? = null

    fun prepare(name: String, source: BookDocumentInput): List<Map<String, Any?>> =
        copy(name, source.file)

    fun prepare(name: String, source: File): List<Map<String, Any?>> = copy(name, source)

    private fun copy(name: String, source: File?): List<Map<String, Any?>> {
        if (source == null || !source.isFile) {
            return listOf(mapOf("name" to name, "path" to null, "error" to "源文件不可读取"))
        }
        return try {
            val target = File(root, name.replace(Regex("[\\\\/:*?\"<>|]"), "_")).apply { parentFile?.mkdirs() }
            source.copyTo(target, overwrite = true)
            listOf(mapOf("name" to name, "path" to target.path, "error" to null))
        } catch (error: Exception) {
            listOf(mapOf("name" to name, "path" to null, "error" to (error.message ?: "文档暂存失败")))
        }
    }
}
