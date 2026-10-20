package app.jmpic.jm_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class DocumentBridge(private val activity: Activity) {
    private val executor = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var importRoot: File? = null
    data class Entry(val id: String, val name: String, val mime: String)

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "openWeb" -> {
                val uri = Uri.parse(call.argument<String>("url") ?: "")
                require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null) { "Only HTTPS websites may be opened" }
                activity.startActivity(Intent(Intent.ACTION_VIEW, uri))
                result.success(true)
                return true
            }
            "pickDirectory", "importDirectory" -> {
                if (pending != null) { result.error("busy", "A directory picker is open", null); return true }
                importRoot = if (call.method == "importDirectory") managed(call.argument<String>("root") ?: "") else null
                pending = result
                activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                }, if (call.method == "importDirectory") 8202 else 8201)
                return true
            }
        }
        return false
    }
    fun onResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != 8201 && request != 8202) return false
        val result = pending ?: return true
        val destination = importRoot
        pending = null
        importRoot = null
        val tree = data?.data
        if (code != Activity.RESULT_OK || tree == null) { result.success(null); return true }
        try {
            val grants = ((data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
            activity.contentResolver.takePersistableUriPermission(tree, grants)
            if (request == 8201) { result.success(tree.toString()); return true }
            executor.execute {
                val created = mutableListOf<File>()
                try {
                    val root = destination ?: throw IllegalArgumentException("Missing import root")
                    root.mkdirs()
                    val parentId = DocumentsContract.getTreeDocumentId(tree)
                    val rootUri = DocumentsContract.buildDocumentUriUsingTree(tree, parentId)
                    val title = activity.contentResolver.query(rootUri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
                        if (it.moveToFirst()) it.getString(0) else "本地漫画"
                    } ?: "本地漫画"
                    val bookId = "local_${UUID.randomUUID()}"
                    val entries = mutableListOf<Map<String, Any>>()
                    val visited = mutableSetOf<String>()
                    fun visit(parent: String, chapterTitle: String) {
                        if (!visited.add(parent)) return
                        val children = children(tree, parent)
                        val images = children.filter { it.mime.startsWith("image/") || Regex("\\.(jpg|jpeg|png|webp|gif)$", RegexOption.IGNORE_CASE).containsMatchIn(it.name) }
                            .sortedBy { Regex("\\d+").replace(it.name.lowercase()) { n -> n.value.padStart(12, '0') } }
                        if (images.isNotEmpty()) {
                            val chapterId = "${bookId}_${entries.size}"
                            val folder = File(root, "import_$chapterId").apply { mkdirs() }
                            created.add(folder)
                            images.forEachIndexed { index, image ->
                                activity.contentResolver.openInputStream(DocumentsContract.buildDocumentUriUsingTree(tree, image.id))?.use { input ->
                                    File(folder, "$index.img").outputStream().use { input.copyTo(it) }
                                } ?: throw IllegalStateException("Cannot read ${image.name}")
                            }
                            entries.add(mapOf("comic" to mapOf("id" to bookId, "name" to title, "author" to emptyList<String>()),
                                "id" to chapterId, "title" to chapterTitle, "folder" to folder.path, "count" to images.size))
                        }
                        children.filter { it.mime == DocumentsContract.Document.MIME_TYPE_DIR }.forEach { visit(it.id, it.name) }
                    }
                    visit(parentId, title)
                    activity.runOnUiThread { result.success(entries) }
                } catch (e: Exception) {
                    created.forEach { it.deleteRecursively() }
                    activity.runOnUiThread { result.error("import_error", e.localizedMessage, null) }
                }
            }
        } catch (e: Exception) { result.error("directory_error", e.localizedMessage, null) }
        return true
    }
    private fun managed(path: String): File {
        val file = File(path).canonicalFile
        val root = File(activity.applicationInfo.dataDir).canonicalFile
        require(file.path.startsWith(root.path + File.separator)) { "File is outside application storage" }
        return file
    }
    private fun children(tree: Uri, parent: String): List<Entry> {
        val result = mutableListOf<Entry>()
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
        activity.contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use {
            while (it.moveToNext()) result.add(Entry(it.getString(0), it.getString(1), it.getString(2)))
        } ?: throw IllegalStateException("Cannot read selected directory")
        return result
    }
    fun close() { executor.shutdown() }
}
