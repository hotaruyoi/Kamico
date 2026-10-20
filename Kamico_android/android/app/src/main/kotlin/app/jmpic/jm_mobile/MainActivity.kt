package app.jmpic.jm_mobile

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.view.WindowManager
import android.os.StatFs
import android.os.Build
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    private lateinit var documents: DocumentBridge
    private lateinit var pdfDownloads: PdfDownloads
    private lateinit var fonts: SystemFontBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The default cutout policy letterboxes the surface when bars are hidden.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                else WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        documents = DocumentBridge(this)
        pdfDownloads = PdfDownloads(this)
        fonts = SystemFontBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.jmpic/files").setMethodCallHandler { call, result ->
            try {
                val bytes = call.argument<ByteArray>("bytes")
                val mime = call.argument<String>("mime") ?: "application/octet-stream"
                val name = (call.argument<String>("name") ?: "image").replace(Regex("[^a-zA-Z0-9_-]"), "_")
                when (call.method) {
                    "privacy" -> {
                        if (call.argument<Boolean>("enabled") == true) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "keepAwake" -> {
                        if (call.argument<Boolean>("enabled") == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    "readerSystemBars" -> {
                        // Keep the Flutter surface fixed while the bars overlay it.
                        WindowCompat.setDecorFitsSystemWindows(window, false)
                        val controller = WindowCompat.getInsetsController(window, window.decorView)
                        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                        val bars = WindowInsetsCompat.Type.systemBars()
                        if (call.argument<Boolean>("visible") == true) controller.show(bars)
                        else controller.hide(bars)
                        result.success(null)
                    }
                    "storageInfo" -> {
                        val storage = StatFs(filesDir.absolutePath)
                        result.success(mapOf("available" to storage.availableBytes, "total" to storage.totalBytes))
                    }
                    "saveImage" -> {
                        if (pendingResult != null) { result.error("busy", "Another file picker is open", null); return@setMethodCallHandler }
                        if (bytes == null) { result.error("empty", "No image", null); return@setMethodCallHandler }
                        pendingBytes = bytes
                        pendingResult = result
                        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mime
                            putExtra(Intent.EXTRA_TITLE, "$name.${extension(mime)}")
                        }, 8101)
                    }
                    "shareImage", "copyImage" -> {
                        if (bytes == null) { result.error("empty", "No image", null); return@setMethodCallHandler }
                        val directory = File(cacheDir, "shared_images").apply { mkdirs() }
                        // Keep shared files briefly for receiving apps, and prune old copies.
                        directory.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86400000 }?.forEach { it.delete() }
                        val file = File(directory, "${System.nanoTime()}_$name.${extension(mime)}").apply { writeBytes(bytes) }
                        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                        if (call.method == "copyImage") {
                            (getSystemService(CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newUri(contentResolver, name, uri))
                        } else {
                            startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                                type = mime
                                putExtra(Intent.EXTRA_STREAM, uri)
                                clipData = ClipData.newUri(contentResolver, name, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }, "分享图片"))
                        }
                        result.success(true)
                    }
                    else -> if (!pdfDownloads.handle(call, result) && !fonts.handle(call, result) && !documents.handle(call, result)) result.notImplemented()
                }
            } catch (e: Exception) {
                pendingResult = null
                pendingBytes = null
                result.error("file_error", e.localizedMessage ?: "File operation failed", null)
            }
        }
    }
    private fun extension(mime: String) = when (mime) {
        "image/jpeg" -> "jpg"
        "image/png" -> "png"
        "image/webp" -> "webp"
        "image/gif" -> "gif"
        else -> "bin"
    }
    @Deprecated("Activity result API is retained for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (::documents.isInitialized && documents.onResult(requestCode, resultCode, data)) return
        if (requestCode != 8101) return
        val callback = pendingResult ?: return
        val bytes = pendingBytes
        pendingResult = null
        pendingBytes = null
        try {
            if (resultCode != Activity.RESULT_OK || data?.data == null || bytes == null) { callback.success(false); return }
            contentResolver.openOutputStream(data.data!!)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Cannot write selected file")
            callback.success(true)
        } catch (e: Exception) { callback.error("file_error", e.localizedMessage, null) }
    }
    override fun onDestroy() {
        if (::documents.isInitialized) documents.close()
        if (::pdfDownloads.isInitialized) pdfDownloads.close()
        if (::fonts.isInitialized) fonts.close()
        super.onDestroy()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (::pdfDownloads.isInitialized) pdfDownloads.onPermissionsResult(requestCode, grantResults)
    }
}
