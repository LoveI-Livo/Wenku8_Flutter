package org.mewx.wenku8_flutter

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import java.io.File

/**
 * 本地书库扫描：支持「所有文件」授权和 SAF 目录授权两种模式。
 *
 * token 直接使用文档 Uri（或 file Uri），导入时按 token 找到原文件并复制，
 * 不依赖上游未公开模块，也不会把扫描结果写入数据库。
 */
internal class BookFolderScanner(private val activity: Activity) {
    private val preferences = activity.getSharedPreferences("book_folder_scan", 0)
    private val imported = linkedSetOf<String>()
    private var formats = preferences.getStringSet("formats", null)
        ?.toMutableSet() ?: BookArchiveImport.supportedExtensions.toMutableSet()
    private var tree: Uri? = preferences.getString("tree", null)?.let(Uri::parse)
    private var automatic = preferences.getBoolean("automatic", true)

    fun canReadAll(): Boolean =
        if (Build.VERSION.SDK_INT >= 30) Environment.isExternalStorageManager()
        else activity.checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED ||
            activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

    fun info(): Map<String, Any?> {
        val all = automatic && tree == null && canReadAll()
        return mapOf(
            "name" to (if (all) "内部存储" else tree?.let { name(it) } ?: ""),
            "automatic" to automatic,
            "readable" to (all || tree != null),
            "all" to all,
        )
    }

    fun selectAll(): Map<String, Any?> {
        preferences.edit().putBoolean("all", true).remove("tree").apply()
        tree = null
        return info()
    }

    fun select(uri: Uri, flags: Int) {
        try {
            val take = flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
            if (take != 0) activity.contentResolver.takePersistableUriPermission(uri, take)
        } catch (_: SecurityException) {
            // 有些文件管理器只给一次性授权，仍允许本次会话扫描。
        }
        preferences.edit().putString("tree", uri.toString()).putBoolean("all", false).apply()
        tree = uri
    }

    fun formats(): List<String> = formats.sorted()

    fun setFormats(extensions: List<String>) {
        formats = extensions
            .map { it.trim().removePrefix(".").lowercase() }
            .filter { it in BookArchiveImport.supportedExtensions }
            .toMutableSet()
        preferences.edit().putStringSet("formats", formats).apply()
    }

    fun setAutomatic(value: Boolean) {
        automatic = value
        preferences.edit().putBoolean("automatic", value).apply()
    }

    fun disconnect() {
        tree?.let { uri ->
            try { activity.contentResolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
            catch (_: SecurityException) { }
        }
        tree = null
        imported.clear()
        preferences.edit().remove("tree").putBoolean("all", false).apply()
    }

    fun scan(): Map<String, Any?> {
        val books = mutableListOf<Map<String, Any?>>()
        val warnings = mutableListOf<String>()
        var total = 0
        var unchanged = 0
        val seen = linkedSetOf<String>()
        fun add(uri: Uri, display: String, folder: String, size: Long) {
            val extension = display.substringAfterLast('.', "").lowercase()
            if (extension !in formats) return
            total++
            val token = uri.toString()
            if (!seen.add(token)) return
            if (token in imported) { unchanged++; return }
            books += mapOf("token" to token, "name" to display, "size" to size, "folder" to folder)
        }
        if (tree != null) {
            walkTree(tree!!, "", add, warnings, 0)
        } else if (canReadAll()) {
            walkFiles(Environment.getExternalStorageDirectory(), "", add, warnings, 0)
        } else {
            throw IllegalStateException("尚未授权扫描目录，请先选择文件夹或授予「所有文件」权限")
        }
        return mapOf("books" to books, "total" to total, "unchanged" to unchanged, "warnings" to warnings)
    }

    private fun walkTree(
        tree: Uri,
        folder: String,
        add: (Uri, String, String, Long) -> Unit,
        warnings: MutableList<String>,
        depth: Int,
    ) {
        if (depth > 12) return
        try {
            val rootId = DocumentsContract.getTreeDocumentId(tree)
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, rootId)
            activity.contentResolver.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE,
                ), null, null, null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0) ?: continue
                    val name = cursor.getString(1) ?: continue
                    val mime = cursor.getString(2) ?: ""
                    val size = if (cursor.isNull(3)) 0L else cursor.getLong(3)
                    val uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        walkTree(uri, if (folder.isEmpty()) name else "$folder/$name", add, warnings, depth + 1)
                    } else add(uri, name, folder, size)
                }
            }
        } catch (error: Exception) {
            warnings += "目录无法读取：${error.message ?: folder}"
        }
    }

    private fun walkFiles(
        dir: File,
        folder: String,
        add: (Uri, String, String, Long) -> Unit,
        warnings: MutableList<String>,
        depth: Int,
    ) {
        if (depth > 12) return
        val children = dir.listFiles() ?: return
        for (child in children) {
            if (child.name.startsWith('.')) continue
            if (child.isDirectory) {
                walkFiles(child, if (folder.isEmpty()) child.name else "$folder/${child.name}", add, warnings, depth + 1)
            } else if (child.isFile) {
                add(Uri.fromFile(child), child.name, folder, child.length())
            }
        }
    }

    fun stage(token: String, root: File, copy: (Uri, File, Long) -> Unit): Map<String, Any?> {
        val uri = Uri.parse(token)
        val display = name(uri)
        val target = File(root, display.replace(Regex("[\\\\/:*?\"<>|]"), "_"))
        try {
            copy(uri, target, BookArchiveImport.limit(display))
            return mapOf("name" to display, "path" to target.path)
        } catch (error: Exception) {
            target.delete()
            throw error
        }
    }

    fun link(token: String, links: BookTextLinks, @Suppress("UNUSED_PARAMETER") root: File,
             @Suppress("UNUSED_PARAMETER") copy: (Uri, File, Long) -> Unit): Map<String, Any?> {
        val uri = Uri.parse(token)
        return mapOf("name" to name(uri), "reference" to links.remember(uri))
    }

    fun markImported(token: String) {
        imported += token
    }

    fun finish() {
        // 保留已导入标记，避免同一轮扫描重复提示；断开目录时清空。
    }

    private fun name(uri: Uri): String {
        var display = uri.lastPathSegment ?: "书籍"
        try {
            activity.contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) display = it.getString(0) ?: display }
        } catch (_: Exception) { }
        return display.replace('\\', '/').substringAfterLast('/').ifBlank { "书籍" }
    }
}
