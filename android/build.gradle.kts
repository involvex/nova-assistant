allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    if (project == rootProject) return@subprojects

    val projectPath = project.projectDir.absolutePath
    val skipRedirect = projectPath.contains(".pub-cache") ||
                       projectPath.contains("Pub\\Cache") ||
                       projectPath.contains("Pub/Cache") ||
                       projectPath.contains("Pub") ||
                       projectPath.contains(".dart_tool")

    if (!skipRedirect) {
        val newSubprojectBuildDir = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }

    tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
        options.compilerArgs.add("-Xlint:-options")
    }

    // Provide minimal flutter extension to android_file_picker
    // so its build.gradle.kts can access flutter.targetSdkVersion, etc.
    if (project.name == "android_file_picker") {
        open class FlutterExtension {
            var compileSdkVersion: Int = 37
            var targetSdkVersion: Int = 37
            var versionCode: Int = 1
            var versionName: String = "1.0.0"
        }
        // Only create if flutter extension doesn't already exist
        if (project.extensions.findByName("flutter") == null) {
            project.extensions.create("flutter", FlutterExtension::class.java)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
