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

    // Apply flutter-gradle-plugin to android_file_picker (from pub cache)
    // after android plugin is applied, so it can access AndroidComponentsExtension
    if (project.name == "android_file_picker") {
        project.plugins.withId("com.android.library") {
            project.plugins.apply("dev.flutter.flutter-gradle-plugin")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
