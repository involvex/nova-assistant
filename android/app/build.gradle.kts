plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.nova.assistant"
    compileSdk = 37
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "dev.nova.assistant"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.addAll(listOf("arm64-v8a"))
        }

        multiDexEnabled = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    signingConfigs {
        create("release") {
            storeFile = file("keystore/release.jks")
            storePassword = "android"
            keyAlias = "release"
            keyPassword = "android"
        }
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
        }
        getByName("release") {
            isMinifyEnabled = true
            val releaseKeystore = file("keystore/release.jks")
            signingConfig = if (releaseKeystore.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        resources {
            excludes += listOf(
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.android.material:material:1.11.0")
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
    implementation("androidx.window:window:1.1.0")
    implementation("androidx.window:window-java:1.1.0")

    // LiteRT replaces org.tensorflow:tensorflow-lite — shipping both causes
    // checkReleaseDuplicateClasses (same org.tensorflow.lite.* in both AARs).
    // Z-Image uses CompiledModel + GPU FP32; FLUX stub still uses Interpreter
    // from this same artifact (package org.tensorflow.lite stays).
    implementation("com.google.ai.edge.litert:litert:2.3.0")
    implementation("com.google.ai.edge.litert:litert-gpu:2.3.0")

    // JVM unit tests for the Z-Image Turbo host-loop math (no Android runtime).
    testImplementation("junit:junit:4.13.2")
}
