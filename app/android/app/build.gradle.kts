plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val repositoryRoot = rootProject.projectDir.parentFile.parentFile
val fipsNativeOutput = file("src/main/jniLibs")

val buildFipsRustArm64 by tasks.registering(Exec::class) {
    group = "build"
    description = "Build the pinned FIPS v0.5.0 JNI library for Android arm64"
    workingDir(repositoryRoot)
    inputs.file(file("../../../Cargo.toml"))
    inputs.file(file("../../../Cargo.lock"))
    inputs.file(file("../../../crates/wmapp-fips-android/Cargo.toml"))
    inputs.dir(file("../../../crates/wmapp-fips-android/src"))
    outputs.file(file("src/main/jniLibs/arm64-v8a/libwmapp_fips_android.so"))
    doFirst {
        fipsNativeOutput.mkdirs()
    }
    val cargoHomeBin = File(System.getProperty("user.home"), ".cargo/bin")
    val homebrewRustupBin = File("/opt/homebrew/opt/rustup/bin")
    val nativeToolPath = listOf(cargoHomeBin, homebrewRustupBin)
        .filter(File::isDirectory)
        .joinToString(File.pathSeparator) { it.absolutePath }
    environment(
        "PATH",
        listOf(nativeToolPath, System.getenv("PATH").orEmpty())
            .filter(String::isNotBlank)
            .joinToString(File.pathSeparator),
    )
    commandLine(
        "cargo", "ndk", "-t", "arm64-v8a", "-o", fipsNativeOutput.absolutePath,
        "build", "--locked", "--release", "-p", "wmapp-fips-android",
    )
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
        ndk.abiFilters += listOf("arm64-v8a")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
    packaging {
        jniLibs.excludes += setOf(
            "lib/armeabi-v7a/**",
            "lib/x86/**",
            "lib/x86_64/**",
        )
    }
}

tasks.named("preBuild").configure {
    dependsOn(buildFipsRustArm64)
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
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
