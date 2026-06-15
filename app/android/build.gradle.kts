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
// Gradle plugin defaults it to the running JDK's version (21) while its Java
// sources still compile at 1.8 — Gradle then fails with "Inconsistent
// JVM-target compatibility". Pin just this plugin's Kotlin compile tasks down
// to 1.8 (matching its own Java target) so it builds cleanly without patching
// its sources. Scoped to this one subproject so other plugins' (already
// consistent) Java/Kotlin targets are left untouched.
subprojects {
    if (project.name == "receive_sharing_intent") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
