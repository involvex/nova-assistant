pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("com.android.application") version "8.13.0" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    id("dev.flutter.flutter-gradle-plugin") version "1.0.0" apply false
}

include(":app")

// Include android_file_picker from pub cache and apply flutter-gradle-plugin
val androidFilePickerVersion = "1.1.1"
val pubCachePathUnix = "${System.getProperty("user.home")}/.pub-cache/hosted/pub.dev/android_file_picker-${androidFilePickerVersion}/android"
val pubCachePathWindows = "${System.getenv("LOCALAPPDATA")}/Pub/Cache/hosted/pub.dev/android_file_picker-${androidFilePickerVersion}/android"
val androidFilePickerDirUnix = file(pubCachePathUnix)
val androidFilePickerDirWindows = file(pubCachePathWindows)
if (androidFilePickerDirUnix.exists()) {
    include(":android_file_picker")
    project(":android_file_picker").projectDir = androidFilePickerDirUnix
} else if (androidFilePickerDirWindows.exists()) {
    include(":android_file_picker")
    project(":android_file_picker").projectDir = androidFilePickerDirWindows
}







