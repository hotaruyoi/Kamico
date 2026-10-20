package app.jmpic.jm_mobile

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Publishes completed PDFs; temporary images never enter shared storage. */
class PdfDownloads(private val activity: Activity) {
    private val downloadsFolder = if (activity.packageName.endsWith(".debug")) "kamico-debug" else "kamico"
    private val executor = Executors.newSingleThreadExecutor()
    private val waiting = mutableListOf<Pair<MethodCall, MethodChannel.Result>>()
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != "publishPdf") return false
        if (Build.VERSION.SDK_INT < 29 && call.argument<String>("tree") == null &&
            activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            waiting.add(call to result)
            if (waiting.size == 1) activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 8301)
        } else publish(call, result)
        return true
    }
    fun onPermissionsResult(request: Int, grants: IntArray): Boolean {
        if (request != 8301) return false
        val requests = waiting.toList(); waiting.clear()
        requests.forEach { (call, result) ->
            if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) publish(call, result)
            else result.error("permission_denied", "保存到系统下载目录需要存储权限；请允许后重试", null)
        }
        return true
    }
    private fun publish(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            try {
                val file = File(call.argument<String>("path") ?: "").canonicalFile
                val root = File(activity.applicationInfo.dataDir).canonicalFile
                require(file.path.startsWith(root.path + File.separator) && file.isFile) { "PDF is outside application storage" }
                require(file.inputStream().use { input -> val header = ByteArray(5); input.read(header); String(header) == "%PDF-" }) { "Invalid PDF" }
                val book = safeName(call.argument<String>("book") ?: "Comic")
                val name = safeName(call.argument<String>("chapter") ?: "Chapter") + ".pdf"
                val sourceName = if (call.argument<String>("source") == "PIC") "PIC" else "JM"
                val tree = call.argument<String>("tree")
                val uri = if (tree != null) exportTree(Uri.parse(tree), sourceName, book, name, file)
                    else if (Build.VERSION.SDK_INT >= 29) publishMedia(sourceName, book, name, file)
                    else publishLegacy(sourceName, book, name, file)
                activity.runOnUiThread { result.success(uri.toString()) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("pdf_publish_error", e.localizedMessage, null) }
            }
        }
    }
    @android.annotation.TargetApi(29)
    private fun publishMedia(sourceName: String, book: String, name: String, source: File): Uri {
        val resolver = activity.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val path = "${Environment.DIRECTORY_DOWNLOADS}/$downloadsFolder/$sourceName/$book/"
        val old = mutableListOf<Uri>()
        resolver.query(collection, arrayOf(MediaStore.Downloads._ID, MediaStore.MediaColumns.OWNER_PACKAGE_NAME),
            "${MediaStore.Downloads.RELATIVE_PATH}=? AND ${MediaStore.Downloads.DISPLAY_NAME}=?", arrayOf(path, name), null)?.use {
            while (it.moveToNext()) if (it.getString(1) == activity.packageName)
                old.add(Uri.withAppendedPath(collection, it.getLong(0).toString()))
        }
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, ".${UUID.randomUUID()}.pdf")
            put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
            put(MediaStore.Downloads.RELATIVE_PATH, path)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: error("Cannot create PDF in Downloads")
        try {
            resolver.openOutputStream(uri, "w")?.use { out -> source.inputStream().use { it.copyTo(out) } }
                ?: error("Cannot write PDF")
            // Keep any previous completed PDF until the new copy is fully written.
            old.forEach { resolver.delete(it, null, null) }
            resolver.update(uri, ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.IS_PENDING, 0)
            }, null, null)
            return uri
        } catch (e: Exception) { resolver.delete(uri, null, null); throw e }
    }
    @Suppress("DEPRECATION")
    private fun publishLegacy(sourceName: String, book: String, name: String, source: File): Uri {
        val root = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), downloadsFolder).canonicalFile
        val folder = File(File(root, sourceName), book).canonicalFile
        require(folder.path.startsWith(root.path + File.separator))
        check(folder.isDirectory || folder.mkdirs()) { "Cannot create Downloads folder" }
        val target = File(folder, name).canonicalFile
        require(target.parentFile == folder)
        val pending = File(folder, ".${UUID.randomUUID()}.part")
        try {
            source.inputStream().use { input -> pending.outputStream().use { input.copyTo(it) } }
            check(pending.renameTo(target)) { "Cannot publish PDF" }
        } finally { pending.delete() }
        MediaScannerConnection.scanFile(activity, arrayOf(target.path), arrayOf("application/pdf"), null)
        return Uri.fromFile(target)
    }
    private fun exportTree(tree: Uri, sourceName: String, book: String, name: String, source: File): Uri {
        val resolver = activity.contentResolver
        val originalId = DocumentsContract.getTreeDocumentId(tree)
        val sourceChildren = DocumentsContract.buildChildDocumentsUriUsingTree(tree, originalId)
        var sourceId: String? = null
        resolver.query(sourceChildren, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use {
            while (it.moveToNext()) if (it.getString(1) == sourceName && it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) sourceId = it.getString(0)
        }
        val sourceFolder = if (sourceId != null) DocumentsContract.buildDocumentUriUsingTree(tree, sourceId)
            else DocumentsContract.createDocument(resolver, DocumentsContract.buildDocumentUriUsingTree(tree, originalId), DocumentsContract.Document.MIME_TYPE_DIR, sourceName)
                ?: error("Cannot create source export directory")
        val rootId = DocumentsContract.getDocumentId(sourceFolder)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, rootId)
        var folderId: String? = null
        resolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use {
            while (it.moveToNext()) if (it.getString(1) == book && it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) folderId = it.getString(0)
        }
        val folder = if (folderId != null) DocumentsContract.buildDocumentUriUsingTree(tree, folderId)
            else DocumentsContract.createDocument(resolver, DocumentsContract.buildDocumentUriUsingTree(tree, rootId), DocumentsContract.Document.MIME_TYPE_DIR, book)
                ?: error("Cannot create export directory")
        // The provider chooses a non-conflicting filename. Existing user files are retained.
        val uri = DocumentsContract.createDocument(resolver, folder, "application/pdf", name) ?: error("Cannot create export PDF")
        try {
            resolver.openOutputStream(uri, "w")?.use { out -> source.inputStream().use { it.copyTo(out) } } ?: error("Cannot write export PDF")
            return uri
        } catch (e: Exception) { DocumentsContract.deleteDocument(resolver, uri); throw e }
    }
    private fun safeName(name: String): String {
        val clean = name.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_").trim().trim('.').ifBlank { "Comic" }
        // Preserve trailing IDs so long titles cannot collapse different chapters
        // or books onto the same shared filename.
        return if (clean.length <= 80) clean else clean.take(52) + "_" + clean.takeLast(27)
    }
    fun close() {
        waiting.forEach { it.second.error("interrupted", "文件保存已中断，请重试", null) }; waiting.clear()
        executor.shutdown()
    }
}
