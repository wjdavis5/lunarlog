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
// home_widget 0.8.1 (issue #141) pins its own plugin subproject to
// `kotlinOptions { jvmTarget = "1.8" }` while pulling work-runtime-ktx /
// coroutines resolved to JVM 11 bytecode, whose inline functions then fail
// to compile ("Cannot inline bytecode built with JVM target 11 into
// bytecode that is being built with JVM target 1.8"). The app module's own
// `jvmTarget = JVM_17` does not govern plugin subprojects, so raise both
// the Kotlin and (to keep AGP's JVM-target consistency check happy) the
// Java compile targets of every Kotlin plugin subproject to 17 — matching
// :app. afterEvaluate so this lands after each plugin's own evaluation;
// this block must stay ABOVE the evaluationDependsOn(":app") block below,
// which force-evaluates :app during the root build script itself (an
// afterEvaluate registered after that point throws "already evaluated").
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("org.jetbrains.kotlin.android")) {
            val androidExtension = extensions.findByName("android")
            if (androidExtension is com.android.build.api.dsl.LibraryExtension) {
                androidExtension.compileOptions.sourceCompatibility =
                    JavaVersion.VERSION_17
                androidExtension.compileOptions.targetCompatibility =
                    JavaVersion.VERSION_17
                // home_widget 0.8.1 pins compileSdk 35, but its own dynamic
                // `androidx.glance:glance-appwidget:1.+` dependency resolves
                // to a release whose AAR metadata demands compileSdk >= 37
                // (checkDebugAarMetadata fails below 37). 37 is this repo's
                // established ceiling — :app pins it for the same reason
                // (flutter_secure_storage v11). Only raise, never lower.
                val currentCompileSdk: Int? = androidExtension.compileSdk
                if (currentCompileSdk == null || currentCompileSdk < 37) {
                    androidExtension.compileSdk = 37
                }
            }
            val kotlinExtension =
                extensions.findByName("kotlin")
                    as? org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension
            kotlinExtension?.compilerOptions {
                jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
