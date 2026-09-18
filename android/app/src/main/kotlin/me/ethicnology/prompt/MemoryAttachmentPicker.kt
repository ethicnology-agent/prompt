package me.ethicnology.prompt

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.Future

/** Reads user-selected content without creating a plaintext application cache. */
internal class MemoryAttachmentPicker(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "me.ethicnology.prompt/attachments")
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: Selection? = null
    private var disposed = false

    private class Selection(
        val result: MethodChannel.Result,
        val maxCount: Int,
        val maxBytesPerFile: Int,
        val maxTotalBytes: Int,
    ) {
        val cancellation = CancellationSignal()
        var work: Future<*>? = null
        var reading = false
    }

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "pick") pick(call, result) else result.notImplemented()
        }
    }

    private fun pick(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.success(null)
            return
        }
        if (pending != null) {
            result.error("picker_busy", "An attachment selection is already open.", null)
            return
        }
        val args = call.arguments as? Map<*, *>
        val imagesOnly = args?.get("imagesOnly") as? Boolean
        val maxCount = args?.get("maxCount") as? Int
        val perFile = args?.get("maxBytesPerFile") as? Int
        val total = args?.get("maxTotalBytes") as? Int
        if (imagesOnly == null || maxCount == null || maxCount !in 1..5 ||
            perFile == null || perFile !in 1..10_485_760 ||
            total == null || total !in 1..26_214_400
        ) {
            result.error("invalid_arguments", "Invalid attachment selection limits.", null)
            return
        }
        val selection = Selection(result, maxCount, perFile, total)
        pending = selection
        try {
            val intent = if (imagesOnly && Build.VERSION.SDK_INT >= 33) {
                Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                    type = "image/*"
                    if (maxCount > 1) {
                        putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX,
                            minOf(maxCount, MediaStore.getPickImagesMaxLimit()))
                    }
                }
            } else {
                Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = if (imagesOnly) "image/*" else "*/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, maxCount > 1)
                }
            }
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (_: ActivityNotFoundException) {
            finish(selection, null, "picker_unavailable")
        } catch (_: SecurityException) {
            finish(selection, null, "picker_unavailable")
        } catch (_: IllegalArgumentException) {
            finish(selection, null, "picker_unavailable")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val selection = pending ?: return true
        if (selection.reading) return true
        if (resultCode != Activity.RESULT_OK || data == null) {
            finish(selection, null, null)
            return true
        }
        val clip = data.clipData
        if (clip != null && clip.itemCount > selection.maxCount) {
            finish(selection, null, "too_many_attachments")
            return true
        }
        val uris = if (clip != null) {
            (0 until clip.itemCount).map { clip.getItemAt(it).uri }
        } else listOfNotNull(data.data)
        if (uris.isEmpty()) {
            finish(selection, null, null)
            return true
        }
        if (uris.any { it == null || it.scheme != "content" }) {
            finish(selection, null, "attachment_read_failed")
            return true
        }
        selection.reading = true
        selection.work = executor.submit {
            val attachments = mutableListOf<Map<String, Any>>()
            var failure: String? = null
            try {
                var remaining = selection.maxTotalBytes
                for (uri in uris) {
                    selection.cancellation.throwIfCanceled()
                    val name = readName(uri, selection.cancellation)
                    val bytes = readBytes(uri, minOf(selection.maxBytesPerFile, remaining),
                        selection.cancellation)
                    attachments.add(mapOf("name" to name, "bytes" to bytes))
                    remaining -= bytes.size
                }
            } catch (error: AttachmentReadFailure) {
                failure = error.code
            } catch (_: Exception) {
                failure = "attachment_read_failed"
            }
            val errorCode = failure
            main.post {
                try {
                    finish(selection, if (errorCode == null) attachments else null, errorCode)
                } finally {
                    // StandardMethodCodec serializes synchronously before success returns.
                    attachments.forEach { (it["bytes"] as ByteArray).fill(0) }
                    attachments.clear()
                }
            }
        }
        return true
    }

    private fun readName(uri: Uri, cancellation: CancellationSignal): String {
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME),
            null, null, null, cancellation)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && !cursor.isNull(index)) {
                    val name = cursor.getString(index).take(255)
                        .substringAfterLast('/').substringAfterLast('\\')
                        .filter { !it.isISOControl() }
                    if (name.isNotBlank()) return name
                }
            }
        }
        return "attachment"
    }

    private fun readBytes(uri: Uri, limit: Int, cancellation: CancellationSignal): ByteArray {
        val descriptor = activity.contentResolver.openAssetFileDescriptor(uri, "r", cancellation)
            ?: throw AttachmentReadFailure("attachment_read_failed")
        descriptor.use {
            if (it.length > limit) throw AttachmentReadFailure("attachment_too_large")
            return BoundedAttachmentReader().read(it.createInputStream(), limit) {
                cancellation.throwIfCanceled()
            }
        }
    }

    private fun finish(selection: Selection, value: Any?, error: String?) {
        if (disposed || pending !== selection) return
        pending = null
        if (error == null) selection.result.success(value)
        else selection.result.error(error, "The attachment selection could not be read.", null)
    }

    fun dispose() {
        if (disposed) return
        val selection = pending
        // Complete the old engine's call before destruction, never after it.
        if (selection != null) finish(selection, null, null)
        disposed = true
        channel.setMethodCallHandler(null)
        selection?.cancellation?.cancel()
        selection?.work?.cancel(true)
        executor.shutdownNow()
    }

    companion object {
        private const val REQUEST_CODE = 0x5041
    }
}
