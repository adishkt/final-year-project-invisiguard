// Top-level build file where you can add configuration options common to all sub-projects/modules.

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.0")
        classpath("com.google.gms:google-services:4.4.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
    
    // Fix build directory location
    val newBuildDir = rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
    rootProject.layout.buildDirectory.set(newBuildDir)
    
    // Apply to subprojects
    subprojects {
        val newSubprojectBuildDir = newBuildDir.dir(project.name)
        project.layout.buildDirectory.set(newSubprojectBuildDir)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// This should be outside any block, at root level
plugins {
    id("com.google.gms.google-services") version "4.4.4" apply false
}