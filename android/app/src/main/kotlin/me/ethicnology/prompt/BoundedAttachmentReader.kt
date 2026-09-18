package me.ethicnology.prompt

import java.io.InputStream

internal class AttachmentReadFailure(val code: String) : Exception()

/** Owns and closes the supplied stream, returning only a bounded independent copy. */
internal class BoundedAttachmentReader(
    private val allocate: (Int) -> ByteArray = { ByteArray(it) },
) {
    fun read(stream: InputStream, limit: Int, checkCancelled: () -> Unit): ByteArray {
        var storage: ByteArray? = null
        var transfer: ByteArray? = null
        try {
            var length = 0
            stream.use {
                if (limit !in 0..10_485_760) throw AttachmentReadFailure("invalid_arguments")
                checkCancelled()
                // Fixed capacity avoids leaving old copies behind during growth.
                val bytes = allocate(limit).also { storage = it }
                val buffer = allocate(8192).also { transfer = it }
                while (true) {
                    checkCancelled()
                    val requested = minOf(buffer.size, limit - length + 1)
                    val count = it.read(buffer, 0, requested)
                    if (count < 0) break
                    if (count == 0 || count > requested) {
                        throw AttachmentReadFailure("attachment_read_failed")
                    }
                    if (count > limit - length) {
                        throw AttachmentReadFailure("attachment_too_large")
                    }
                    buffer.copyInto(bytes, length, 0, count)
                    length += count
                }
            }
            // Close and cancellation failures occur before allocating the result.
            checkCancelled()
            return storage!!.copyOf(length)
        } catch (failure: AttachmentReadFailure) {
            // A failing close may attach a provider exception as suppressed.
            throw AttachmentReadFailure(failure.code)
        } catch (_: Exception) {
            // Provider exceptions may contain document identifiers or paths.
            throw AttachmentReadFailure("attachment_read_failed")
        } finally {
            transfer?.fill(0)
            storage?.fill(0)
        }
    }
}
