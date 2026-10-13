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
subprojects {
    project.evaluationDependsOn(":app")
}

// ─── camera_android_camerax compile fix ───────────────────────────────────────
//
// camera_android_camerax 0.7.2 compiles against androidx.camera:camera-core
// 1.6.0, whose signatures reference
// androidx.concurrent.futures.CallbackToFutureAdapter — but the plugin never
// declares androidx.concurrent:concurrent-futures itself. camera-core pulls it
// in as `implementation`, so it reaches the RUNTIME classpath but not the
// COMPILE one, and javac cannot complete the symbol:
//
//   :camera_android_camerax:compileDebugJavaWithJavac FAILED
//   class file for androidx.concurrent.futures.CallbackToFutureAdapter not found
//
// This fails EVERY Android build, debug and release alike, so no Play Store
// bundle could be produced at all. Putting the class on that one module's
// compile classpath is enough. `compileOnly` on purpose: the runtime classpath
// already has it via camera-core, so nothing extra ships in the APK/AAB.
//
// Drop this block once the upstream plugin declares the dependency itself
// (check after any `camera` package upgrade).
subprojects {
    if (name == "camera_android_camerax") {
        plugins.withId("com.android.library") {
            // 1.1.0 is exactly the version camera-core already resolves at
            // runtime, so this adds a compile-time view of what is shipping
            // anyway rather than introducing a second version.
            dependencies.add(
                "compileOnly",
                "androidx.concurrent:concurrent-futures:1.1.0",
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
