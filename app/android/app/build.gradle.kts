plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningEnvironment = mapOf(
    "WMAPP_ANDROID_KEYSTORE" to providers.environmentVariable("WMAPP_ANDROID_KEYSTORE").orNull,
    "WMAPP_ANDROID_STORE_PASSWORD" to providers.environmentVariable("WMAPP_ANDROID_STORE_PASSWORD").orNull,
    "WMAPP_ANDROID_KEY_ALIAS" to providers.environmentVariable("WMAPP_ANDROID_KEY_ALIAS").orNull,
    "WMAPP_ANDROID_KEY_PASSWORD" to providers.environmentVariable("WMAPP_ANDROID_KEY_PASSWORD").orNull,
)
val missingReleaseSigningEnvironment = releaseSigningEnvironment
    .filterValues { it.isNullOrBlank() }
    .keys

if (missingReleaseSigningEnvironment.isEmpty()) {
    android.signingConfigs.create("release") {
        storeFile = file(releaseSigningEnvironment.getValue("WMAPP_ANDROID_KEYSTORE")!!)
        storePassword = releaseSigningEnvironment.getValue("WMAPP_ANDROID_STORE_PASSWORD")
        keyAlias = releaseSigningEnvironment.getValue("WMAPP_ANDROID_KEY_ALIAS")
        keyPassword = releaseSigningEnvironment.getValue("WMAPP_ANDROID_KEY_PASSWORD")
    }
}

android {
    namespace = "com.wingmanbefree.wingman_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wingmanbefree.wingman_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    val requestsReleaseArtifact = allTasks.any { task ->
        task.name.contains("release", ignoreCase = true)
    }
    if (requestsReleaseArtifact && missingReleaseSigningEnvironment.isNotEmpty()) {
        throw GradleException(
            "WMAPP release signing is not configured. Missing: " +
                missingReleaseSigningEnvironment.sorted().joinToString(", ") +
                ". Use build_android_release.sh or provide the documented environment variables.",
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
