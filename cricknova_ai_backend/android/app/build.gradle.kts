import java.util.Properties
import java.io.FileInputStream
import com.android.build.gradle.LibraryExtension

// Keystore properties load karne ke liye logic
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

configurations.all {
    resolutionStrategy {
        force("com.razorpay:checkout:1.6.38")
    }
}

android {
    namespace = "com.cricknova.ai"
    
    // 2026 Play Store requirement: API 35 (Android 15)
    compileSdk = 35 
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    // Signing configuration for Release
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    defaultConfig {
        applicationId = "com.cricknova.ai"
        minSdk = 21
        targetSdk = 35 // Force target API 35 for Play Store approval
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Ab app debug key se nahi, aapki real key se sign hogi
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true // App size chota karne ke liye
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.7.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.razorpay:checkout:1.6.38")
}

flutter {
    source = "../.."
}

