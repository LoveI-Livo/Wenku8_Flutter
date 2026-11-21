package org.mewx.wenku8_flutter

import android.app.Activity
import android.net.Uri
import java.io.File

/**
 * 源码预览构建的文件夹扫描占位实现。
 *
 * 公开仓库不包含原项目未公开的 SAF 扫描模块，因此这里只保证工程可编译、
 * 通道在调用时返回明确错误，不会伪造扫描结果。需要完整扫描能力时请合并
 * 上游完整源码或在设备上改用单文件导入。
 */
internal class BookFolderScanner(@Suppress("UNUSED_PARAMETER") private val activity: Activity) {
    fun canReadAll(): Boolean = false
    fun selectAll(): Nothing = unavailable()
    fun info(): Nothing = unavailable()
    fun scan(): Nothing = unavailable()
    fun formats(): List<String> = listOf("txt", "epub")
    fun setFormats(@Suppress("UNUSED_PARAMETER") extensions: List<String>): Nothing = unavailable()
    fun setAutomatic(@Suppress("UNUSED_PARAMETER") value: Boolean): Nothing = unavailable()
    fun disconnect(): Nothing = unavailable()
    fun select(@Suppress("UNUSED_PARAMETER") uri: Uri, @Suppress("UNUSED_PARAMETER") flags: Int): Nothing = unavailable()
    fun stage(@Suppress("UNUSED_PARAMETER") token: String, @Suppress("UNUSED_PARAMETER") root: File, @Suppress("UNUSED_PARAMETER") copy: (Uri, File, Long) -> Unit): Nothing = unavailable()
    fun link(@Suppress("UNUSED_PARAMETER") token: String, @Suppress("UNUSED_PARAMETER") links: BookTextLinks, @Suppress("UNUSED_PARAMETER") root: File, @Suppress("UNUSED_PARAMETER") copy: (Uri, File, Long) -> Unit): Nothing = unavailable()
    fun markImported(@Suppress("UNUSED_PARAMETER") token: String): Nothing = unavailable()
    fun finish(): Nothing = unavailable()

    private fun unavailable(): Nothing = throw IllegalStateException("当前源码构建未包含文件夹扫描模块，请使用单文件导入")
}
