package com.example.svgx_example

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterShellArgs

/**
 * MainActivity that dynamically disables Impeller on WSA (Windows Subsystem for
 * Android) and common Android emulators, where the Impeller backend is known to
 * cause a black-screen bug under `Scaffold(appBar: ...)`. Real devices keep the
 * default (Impeller enabled).
 *
 * This overrides [getFlutterShellArgs], which FlutterActivity uses to build the
 * FlutterEngine's shell args. These take precedence over both the AndroidManifest
 * `EnableImpeller` meta-data AND any hardcoded default, per
 * `FlutterLoader.ensureInitializationComplete` (manifest metadata is applied first,
 * then command-line/shell args from here override it). Verified against Flutter
 * engine source: `FlutterLoader.java` (metadata parsed ~line 299-405, args override
 * ~line 407-443) and `FlutterActivity.java#getFlutterShellArgs` (default impl
 * returns `FlutterShellArgs.fromIntent(getIntent())`).
 */
class MainActivity : FlutterActivity() {
    override fun getFlutterShellArgs(): FlutterShellArgs {
        val baseArgs = super.getFlutterShellArgs().toArray().toMutableList()
        if (isProbablyWsaOrEmulator()) {
            baseArgs.add("--enable-impeller=false")
        }
        return FlutterShellArgs(baseArgs)
    }

    /**
     * Best-effort WSA / emulator detection based on `Build` fields. Deliberately
     * conservative: only matches well-known WSA/emulator fingerprints so a real
     * device is never misclassified. If any signal here looks unreliable it should
     * be removed rather than risk a false positive on real hardware.
     */
    private fun isProbablyWsaOrEmulator(): Boolean {
        val fingerprint = Build.FINGERPRINT ?: ""
        val model = Build.MODEL ?: ""
        val product = Build.PRODUCT ?: ""
        val manufacturer = Build.MANUFACTURER ?: ""
        val brand = Build.BRAND ?: ""
        val device = Build.DEVICE ?: ""
        val hardware = Build.HARDWARE ?: ""

        // WSA-specific fingerprints (Windows Subsystem for Android).
        val isWsa = fingerprint.contains("Subsystem_for_Android", ignoreCase = true) ||
            product.contains("windows_x86_64", ignoreCase = true) ||
            model.contains("Subsystem for Android", ignoreCase = true)

        // Standard Android emulator / Genymotion / generic-build fingerprints
        // (industry-standard isEmulator() heuristic, e.g. used by common
        // "DeviceUtil.isEmulator()" implementations).
        val isGenericEmulator = fingerprint.startsWith("generic") ||
            fingerprint.startsWith("unknown") ||
            fingerprint.contains("test-keys") && (
                model.contains("google_sdk", ignoreCase = true) ||
                    model.contains("Emulator", ignoreCase = true) ||
                    model.contains("Android SDK built for", ignoreCase = true)
                ) ||
            manufacturer.contains("Genymotion", ignoreCase = true) ||
            (brand.startsWith("generic") && device.startsWith("generic")) ||
            product == "google_sdk" ||
            hardware.contains("goldfish", ignoreCase = true) ||
            hardware.contains("ranchu", ignoreCase = true) ||
            product.contains("sdk_gphone", ignoreCase = true)

        return isWsa || isGenericEmulator
    }
}
