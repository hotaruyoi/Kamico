package app.jmpic.jm_mobile

import android.app.Activity
import android.graphics.fonts.SystemFonts
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class SystemFontBridge(private val activity: Activity) {
    private val executor = Executors.newSingleThreadExecutor()
    private var catalog = mapOf<String, File>()
    private fun discover(): Map<String, File> {
        val files = if (Build.VERSION.SDK_INT >= 29) SystemFonts.getAvailableFonts().mapNotNull { it.file }
            else listOf("/system/fonts", "/product/fonts", "/vendor/fonts").flatMap { File(it).listFiles()?.toList() ?: emptyList() }
        return files.filter { it.canRead() && it.isFile && it.extension.lowercase() in listOf("ttf", "otf", "ttc") }
            .distinctBy { it.canonicalPath }.sortedBy { it.name.lowercase() }.associateBy {
                MessageDigest.getInstance("SHA-256").digest(it.canonicalPath.toByteArray()).joinToString("") { b -> "%02x".format(b) }
            }
    }
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method !in listOf("systemFonts", "fontBytes")) return false
        executor.execute {
            try {
                if (catalog.isEmpty() || call.method == "systemFonts") catalog = discover()
                val value = if (call.method == "systemFonts") catalog.map { (id, file) -> mapOf("id" to id, "name" to file.nameWithoutExtension) }
                    else (catalog[call.argument<String>("id")] ?: error("该字体已不可用，请重新选择")).readBytes()
                activity.runOnUiThread { result.success(value) }
            } catch (e: Exception) { activity.runOnUiThread { result.error("font_error", e.localizedMessage, null) } }
        }
        return true
    }
    fun close() { executor.shutdown() }
}
