// NixOS: AGP would otherwise download a generic-Linux aapt2 from Maven that
// can't dynamically link on NixOS (no /lib64/ld-linux at standard paths).
// Point it at the nix-patched aapt2 from the build-tools SDK component
// declared in flake.nix. Picks the highest installed build-tools version, so
// bumps to the flake's build-tools entry don't require touching this file.
System.getenv("ANDROID_HOME")?.let { androidHome ->
    val aapt2 = java.io.File(androidHome, "build-tools").listFiles()
        ?.sortedByDescending { it.name }
        ?.firstNotNullOfOrNull { dir ->
            java.io.File(dir, "aapt2").takeIf { it.exists() && it.canExecute() }
        }
    if (aapt2 != null) {
        gradle.startParameter.projectProperties +=
            "android.aapt2FromMavenOverride" to aapt2.absolutePath
    }
}

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
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
