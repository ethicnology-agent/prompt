package me.ethicnology.prompt

import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream

/** Dependency-free JVM checks; also callable by a future native test runner. */
object BoundedAttachmentReaderTest {
    @JvmStatic
    fun main(args: Array<String>) {
        testExactLimitAndWiping()
        testBelowLimit()
        testOverLimit()
        testEmptyAtZeroLimit()
        testNonEmptyAtZeroLimit()
        testZeroProgress()
        testCancelledBeforeReading()
        testCancelledDuringReading()
        testCancelledAfterClosing()
        testProviderFailure()
        testCloseFailure()
        testOverLimitAndCloseFailure()
        testInvalidLimits()
        println("13 bounded attachment reader tests passed")
    }

    private class Fixture {
        val buffers = mutableListOf<ByteArray>()
        val reader = BoundedAttachmentReader { size -> ByteArray(size).also { buffers.add(it) } }
        fun assertWiped() = check(buffers.all { bytes -> bytes.all { it == 0.toByte() } })
    }

    private class TrackedStream(
        bytes: ByteArray,
        private val chunkSize: Int = Int.MAX_VALUE,
        private val failRead: Boolean = false,
        private val failClose: Boolean = false,
        private val zeroProgress: Boolean = false,
    ) : InputStream() {
        private val delegate = ByteArrayInputStream(bytes)
        var closed = false
        var calls = 0
        var bytesRead = 0
        override fun read(): Int = error("Bulk reads required")
        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            calls++
            if (failRead) throw IOException("private/provider/document")
            if (zeroProgress) return 0
            val count = delegate.read(buffer, offset, minOf(length, chunkSize))
            if (count > 0) bytesRead += count
            return count
        }
        override fun close() {
            closed = true
            if (failClose) throw IOException("private/provider/document")
        }
    }

    private fun failure(code: String, action: () -> Unit) {
        try {
            action()
            error("Expected failure")
        } catch (error: AttachmentReadFailure) {
            check(error.code == code)
            check(error.message == null)
            check(error.cause == null)
            check(error.suppressed.isEmpty())
        }
    }

    private fun testExactLimitAndWiping() {
        val fixture = Fixture()
        val stream = TrackedStream(byteArrayOf(1, 2, 3), chunkSize = 1)
        val result = fixture.reader.read(stream, 3) {}
        check(result.contentEquals(byteArrayOf(1, 2, 3)))
        check(stream.closed && stream.bytesRead == 3)
        check(fixture.buffers.map { it.size } == listOf(3, 8192))
        fixture.assertWiped()
        check(fixture.buffers.none { it === result })
    }

    private fun testBelowLimit() {
        val fixture = Fixture()
        val stream = TrackedStream(byteArrayOf(4, 5))
        check(fixture.reader.read(stream, 100) {}.contentEquals(byteArrayOf(4, 5)))
        check(stream.closed)
        fixture.assertWiped()
    }

    private fun testOverLimit() {
        val fixture = Fixture()
        val stream = TrackedStream(ByteArray(100) { 7 })
        failure("attachment_too_large") { fixture.reader.read(stream, 3) {} }
        check(stream.closed && stream.bytesRead == 4)
        fixture.assertWiped()
    }

    private fun testEmptyAtZeroLimit() {
        val fixture = Fixture()
        val stream = TrackedStream(byteArrayOf())
        check(fixture.reader.read(stream, 0) {}.isEmpty())
        check(stream.closed)
        fixture.assertWiped()
    }

    private fun testNonEmptyAtZeroLimit() {
        val fixture = Fixture()
        val stream = TrackedStream(byteArrayOf(8))
        failure("attachment_too_large") { fixture.reader.read(stream, 0) {} }
        check(stream.closed && stream.bytesRead == 1)
        fixture.assertWiped()
    }

    private fun testZeroProgress() {
        val fixture = Fixture()
        val stream = TrackedStream(byteArrayOf(9), zeroProgress = true)
        failure("attachment_read_failed") { fixture.reader.read(stream, 4) {} }
        check(stream.closed && stream.calls == 1)
        fixture.assertWiped()
    }

    private fun testCancelledBeforeReading() {
        val fixture = Fixture()
        val stream = TrackedStream(byteArrayOf(9))
        failure("attachment_read_failed") {
            fixture.reader.read(stream, 4) { throw IllegalStateException("private cancellation") }
        }
        check(stream.closed && stream.calls == 0 && fixture.buffers.isEmpty())
    }

    private fun testCancelledDuringReading() {
        val fixture = Fixture()
        val stream = TrackedStream(byteArrayOf(9, 8, 7), chunkSize = 1)
        failure("attachment_read_failed") {
            fixture.reader.read(stream, 4) {
                if (stream.bytesRead > 0) throw IllegalStateException("private cancellation")
            }
        }
        check(stream.closed && stream.bytesRead == 1)
        fixture.assertWiped()
    }

    private fun testCancelledAfterClosing() {
        val fixture = Fixture()
        val stream = TrackedStream(byteArrayOf(9))
        failure("attachment_read_failed") {
            fixture.reader.read(stream, 4) {
                if (stream.closed) throw IllegalStateException("private cancellation")
            }
        }
        fixture.assertWiped()
    }

    private fun testProviderFailure() {
        val fixture = Fixture()
        val stream = TrackedStream(byteArrayOf(9), failRead = true)
        failure("attachment_read_failed") { fixture.reader.read(stream, 4) {} }
        check(stream.closed)
        fixture.assertWiped()
    }

    private fun testCloseFailure() {
        val fixture = Fixture()
        val stream = TrackedStream(byteArrayOf(9), failClose = true)
        failure("attachment_read_failed") { fixture.reader.read(stream, 4) {} }
        check(stream.closed)
        fixture.assertWiped()
    }

    private fun testInvalidLimits() {
        for (limit in listOf(-1, 10_485_761, Int.MAX_VALUE)) {
            val fixture = Fixture()
            val stream = TrackedStream(byteArrayOf(9))
            failure("invalid_arguments") { fixture.reader.read(stream, limit) {} }
            check(stream.closed && stream.calls == 0 && fixture.buffers.isEmpty())
        }
    }

    private fun testOverLimitAndCloseFailure() {
        val fixture = Fixture()
        val stream = TrackedStream(byteArrayOf(9, 8), failClose = true)
        failure("attachment_too_large") { fixture.reader.read(stream, 1) {} }
        check(stream.closed)
        fixture.assertWiped()
    }
}
