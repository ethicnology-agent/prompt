plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningEnvironment = mapOf(
    "PROMPT_RELEASE_STORE_FILE" to System.getenv("PROMPT_RELEASE_STORE_FILE"),
    "PROMPT_RELEASE_STORE_PASSWORD" to System.getenv("PROMPT_RELEASE_STORE_PASSWORD"),
    "PROMPT_RELEASE_KEY_ALIAS" to System.getenv("PROMPT_RELEASE_KEY_ALIAS"),
    "PROMPT_RELEASE_KEY_PASSWORD" to System.getenv("PROMPT_RELEASE_KEY_PASSWORD"),
)
val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

android {
    namespace = "me.ethicnology.prompt"
    compileSdk = flutter.compileSdkVersion
    // whisper_ggml is built against NDK 29; newer NDKs remain backward
    // compatible with the application's other native dependencies.
    ndkVersion = "29.0.13113456"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "me.ethicnology.prompt"
        // A separate sandbox on test devices: never replace the user's app,
        // credentials, voice packs, or encrypted queue during UI validation.
        if (providers.gradleProperty("promptPreview").orNull == "true") {
            applicationIdSuffix = ".preview"
        }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release signing is intentionally supplied by the build environment.
            // Never fall back to the debug keystore for a distributable artifact.
            if (releaseBuildRequested) {
                require(releaseSigningEnvironment.all { it.value?.isNotBlank() == true }) {
                    "Release signing requires PROMPT_RELEASE_STORE_FILE, " +
                        "PROMPT_RELEASE_STORE_PASSWORD, PROMPT_RELEASE_KEY_ALIAS, and " +
                        "PROMPT_RELEASE_KEY_PASSWORD environment variables"
                }
                signingConfig = signingConfigs.create("release") {
                    storeFile = file(releaseSigningEnvironment.getValue("PROMPT_RELEASE_STORE_FILE"))
                    storePassword = releaseSigningEnvironment.getValue("PROMPT_RELEASE_STORE_PASSWORD")
                    keyAlias = releaseSigningEnvironment.getValue("PROMPT_RELEASE_KEY_ALIAS")
                    keyPassword = releaseSigningEnvironment.getValue("PROMPT_RELEASE_KEY_PASSWORD")
                }
            }
        }
    }
}

dependencies {
    // Required by flutter_local_notifications for its Android scheduling APIs.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // Prefer the permissionless system QR surface when Play services exists.
    // GrapheneOS and other Google-free devices fall back to a local decoder,
    // with camera access requested only after the user's explicit scan action.
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    implementation("com.journeyapps:zxing-android-embedded:4.3.0") {
        isTransitive = false
    }
    implementation("com.google.zxing:core:3.5.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
