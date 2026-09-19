package me.ethicnology.prompt

import android.app.Activity
import android.content.Intent
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.moduleinstall.InstallStatusListener
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallClient
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScanner
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.google.zxing.client.android.Intents
import com.google.zxing.integration.android.IntentIntegrator
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Opens a QR-only system surface, with an explicit-action local fallback. */
internal class PairingCodeScanner(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "me.ethicnology.prompt/pairing")
    private var pending: MethodChannel.Result? = null
    private var installClient: ModuleInstallClient? = null
    private var installListener: InstallStatusListener? = null
    private var fallbackOpen = false
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "scan") scan(result) else result.notImplemented()
        }
    }

    private fun scan(result: MethodChannel.Result) {
        if (disposed) {
            result.success(null)
            return
        }
        if (pending != null) {
            result.error("scanner_busy", "A pairing scan is already open.", null)
            return
        }
        pending = result
        if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(activity) !=
            ConnectionResult.SUCCESS
        ) {
            startFallback()
            return
        }
        try {
            // QR-only and no auto-zoom: the latter avoids optional zoom telemetry.
            val options = GmsBarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .build()
            ensureModuleAndScan(GmsBarcodeScanning.getClient(activity, options))
        } catch (_: Exception) {
            startFallback()
        }
    }

    private fun ensureModuleAndScan(scanner: GmsBarcodeScanner) {
        val client = ModuleInstall.getClient(activity)
        var settled = false
        lateinit var listener: InstallStatusListener
        fun openScanner() {
            if (settled) return
            settled = true
            cleanupInstall()
            if (pending == null || disposed) return
            startScanner(scanner)
        }
        fun fail() {
            if (settled) return
            settled = true
            cleanupInstall()
            startFallback()
        }
        listener = InstallStatusListener { update ->
            when (update.installState) {
                ModuleInstallStatusUpdate.InstallState.STATE_COMPLETED -> openScanner()
                ModuleInstallStatusUpdate.InstallState.STATE_CANCELED,
                ModuleInstallStatusUpdate.InstallState.STATE_FAILED -> fail()
            }
        }
        installClient = client
        installListener = listener
        val request = ModuleInstallRequest.newBuilder()
            .addApi(scanner)
            .setListener(listener)
            .build()
        client.installModules(request)
            .addOnSuccessListener { response ->
                if (response.areModulesAlreadyInstalled()) openScanner()
            }
            .addOnFailureListener { fail() }
    }

    private fun startScanner(scanner: GmsBarcodeScanner) {
        try {
            scanner.startScan()
                .addOnSuccessListener { barcode ->
                    val value = barcode.rawValue
                    if (value == null || value.isEmpty() || value.length > MAX_PAYLOAD_LENGTH) {
                        finish(null, "invalid_result")
                    } else {
                        finish(value, null)
                    }
                }
                .addOnCanceledListener { finish(null, null) }
                .addOnFailureListener { startFallback() }
        } catch (_: Exception) {
            startFallback()
        }
    }

    private fun startFallback() {
        if (pending == null || disposed || fallbackOpen) return
        cleanupInstall()
        try {
            fallbackOpen = true
            IntentIntegrator(activity)
                .setCaptureActivity(PairingCaptureActivity::class.java)
                .setDesiredBarcodeFormats(IntentIntegrator.QR_CODE)
                .setPrompt("Scan pairing code")
                .setBeepEnabled(false)
                .setOrientationLocked(true)
                .addExtra(Intents.Scan.SHOW_MISSING_CAMERA_PERMISSION_DIALOG, false)
                .initiateScan()
        } catch (_: Exception) {
            fallbackOpen = false
            finish(null, "scanner_unavailable")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != IntentIntegrator.REQUEST_CODE || !fallbackOpen) return false
        fallbackOpen = false
        if (data?.getBooleanExtra(Intents.Scan.MISSING_CAMERA_PERMISSION, false) == true) {
            finish(null, "camera_permission_denied")
            return true
        }
        val scan = IntentIntegrator.parseActivityResult(requestCode, resultCode, data)
        val value = scan?.contents
        when {
            value == null -> finish(null, null)
            value.isEmpty() || value.length > MAX_PAYLOAD_LENGTH ->
                finish(null, "invalid_result")
            else -> finish(value, null)
        }
        return true
    }

    private fun finish(value: String?, error: String?) {
        val result = pending ?: return
        pending = null
        fallbackOpen = false
        if (disposed) return
        if (error == null) result.success(value)
        else result.error(error, "The pairing code could not be scanned.", null)
    }

    private fun cleanupInstall() {
        val listener = installListener
        if (listener != null) installClient?.unregisterListener(listener)
        installListener = null
        installClient = null
    }

    fun dispose() {
        if (disposed) return
        pending?.success(null)
        pending = null
        fallbackOpen = false
        cleanupInstall()
        disposed = true
        channel.setMethodCallHandler(null)
    }

    companion object {
        private const val MAX_PAYLOAD_LENGTH = 2048
    }
}
