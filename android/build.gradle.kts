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

configure<org.gradle.api.initialization.dsl.ScriptHandler> {
    // Apply flutter-gradle-plugin to android_file_picker (from pub cache)
    // after android plugin is applied, so it can access AndroidComponentsExtension
    if (rootProject.name == "android_file_picker") {
        rootProject.plugins.withId("com.android.library") {
            rootProject.plugins.apply("dev.flutter.flutter-gradle-plugin")
        }
    }
}

// Configure subprojects using modern API
projects.forEach { project ->
    if (project == rootProject) return@forEach

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

    project.tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
        options.compilerArgs.add("-Xlint:-options")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
