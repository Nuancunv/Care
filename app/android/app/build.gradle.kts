// Adapted from ccch1mneyyy/dsh-Go (AGPL-3.0); see root THIRD_PARTY_NOTICES.md.
// Pruned for Care M1: ARM64-only all-in-one offline APK, zero sherpa_onnx / onnxruntime / mlkit / webrtc.
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProps = Properties().apply {
    rootProject.file("key.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}

val hasWholeReleaseKey = listOf("storeFile", "keyAlias").all { !keyProps.getProperty(it).isNullOrBlank() } &&
    listOf("storePassword", "keyPassword").all { !keyProps.getProperty(it).isNullOrEmpty() } &&
    file(keyProps.getProperty("storeFile")).exists()

// Per-ABI offline runtime assets & PRoot binaries produced by runtime/build-runtime.sh (ADR-003).
val runtimeOut = rootProject.file("../../runtime/out")

android {
    namespace = "io.github.care_agent.app"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.care_agent.app"
        manifestPlaceholders["appLabel"] = "Care"
        // java.nio.file symlinks during rootfs extraction require API 26+.
        minSdk = 26
        // Deliberately target API 28 (like Termux & dsh-Go) so Android 10+ W^X
        // restrictions do not block executing PRoot/Node inside app-private storage.
        targetSdk = 28
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "abi"
    productFlavors {
        create("arm64") {
            dimension = "abi"
            ndk { abiFilters += "arm64-v8a" }
        }
    }

    sourceSets {
        getByName("arm64") {
            assets.srcDir(File(runtimeOut, "arm64-v8a/assets"))
            jniLibs.srcDir(File(runtimeOut, "arm64-v8a/jniLibs"))
        }
    }

    packaging {
        jniLibs {
            // PRoot & helper binaries ship as lib*.so and must be extracted to nativeLibraryDir.
            useLegacyPackaging = true
            keepDebugSymbols += listOf(
                "**/libproot.so",
                "**/libproot-loader.so",
                "**/libtalloc.so",
                "**/libandroid-shmem.so",
            )
        }
    }

    lint {
        // targetSdk 28 is intentional for local PRoot execution (non-Play sideload distribution).
        disable += "ExpiredTargetSdkVersion"
    }

    androidResources {
        noCompress += listOf("gz", "xz", "zst", "tar")
    }

    signingConfigs {
        if (hasWholeReleaseKey) {
            create("release") {
                storeFile = keyProps.getProperty("storeFile")?.let { file(it) }
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
                // V1+V2+V3 schemes for full Chinese ROM compatibility (ColorOS / OPPO Find X8s+).
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        debug {
            if (hasWholeReleaseKey) signingConfig = signingConfigs.getByName("release")
        }
        release {
            signingConfig = signingConfigs.getByName(if (hasWholeReleaseKey) "release" else "debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Offline .tar.xz rootfs extraction for the all-in-one APK (ADR-003).
    implementation("org.tukaani:xz:1.10")
    // Low-power hybrid background scheduler for morning/evening briefings & reminders (M2).
    implementation("androidx.work:work-runtime-ktx:2.10.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
