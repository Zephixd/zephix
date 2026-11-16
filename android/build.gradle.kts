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
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// permission_handler_android 14.x declares compileSdk = 37. AGP 9.1 resolves that to the
// "android-37" hash, but the SDK ships API 37 as "android-37.0". Point any module that
// asks for 37 at the installed platform. Registered before evaluationDependsOn below so
// the hook is in place before any subproject is evaluated.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") as? com.android.build.api.dsl.CommonExtension
        if (android != null && android.compileSdk == 37) {
            android.compileSdkVersion("android-37.0")
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
