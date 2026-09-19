package me.ethicnology.prompt

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.content.Intent

class MainActivity : FlutterActivity() {
    private var attachmentPicker: MemoryAttachmentPicker? = null
    private var pairingCodeScanner: PairingCodeScanner? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        attachmentPicker = MemoryAttachmentPicker(this, flutterEngine.dartExecutor.binaryMessenger)
        pairingCodeScanner = PairingCodeScanner(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (pairingCodeScanner?.onActivityResult(requestCode, resultCode, data) != true &&
            attachmentPicker?.onActivityResult(requestCode, resultCode, data) != true
        ) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        attachmentPicker?.dispose()
        attachmentPicker = null
        pairingCodeScanner?.dispose()
        pairingCodeScanner = null
        super.onDestroy()
    }
}
