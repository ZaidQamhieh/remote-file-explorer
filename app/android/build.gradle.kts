allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// receive_sharing_intent (1.8.1) doesn't pin a Kotlin jvmTarget, so the Kotlin
// Gradle plugin defaults it to the running JDK's version while its own Java
// compile task resolves independently — Gradle then fails with "Inconsistent
// JVM-target compatibility" whenever the two disagree. Pin just this plugin's
// Kotlin compile tasks to match its own Java compile task's target (11 as of
// AGP 9.0.1/Kotlin 2.3.20/Gradle 9.1.0 — was 1.8 under AGP 8.7.0/Kotlin 2.1.0/
// Gradle 8.10.2; re-check this value if either toolchain moves again) so it
// builds cleanly without patching its sources. Scoped to this one subproject
// so other plugins' (already consistent) Java/Kotlin targets are untouched.
subprojects {
    if (project.name == "receive_sharing_intent") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }
}

// file_picker (11.0.2) skips applying the Kotlin Android plugin to itself
// whenever it detects AGP >= 9 (`isAgp9OrAbove`), assuming AGP 9's built-in
// Kotlin support will compile its sources instead. That assumption only
// holds with `android.builtInKotlin=true`; this repo runs AGP 9 with it
// left `false` (required — ~12 other plugins, incl. receive_sharing_intent
// above, still apply the old-style Kotlin Gradle Plugin themselves and
// fail to configure at all under builtInKotlin=true). With neither AGP's
// built-in support nor file_picker's own (skipped) plugin application
// compiling it, `:file_picker:compileDebugKotlin` never runs and
// `FilePickerPlugin` never lands in its output jar, so the app's generated
// plugin registrant fails with "cannot find symbol". Force-apply the
// plugin ourselves for just this subproject — same shape as the
// receive_sharing_intent workaround above.
subprojects {
    if (project.name == "file_picker") {
        pluginManager.apply("org.jetbrains.kotlin.android")
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
