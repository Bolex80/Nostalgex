import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "es.benthem.bolextv"
    compileSdk = 34

    defaultConfig {
        applicationId = "es.benthem.bolextv"
        // Mi Box reports SDK 34; 23 keeps older boxes and phones installable.
        minSdk = 23
        targetSdk = 34
        versionCode = 3
        versionName = "1.1.0"

        // Build-time constant so re-pointing at another tuner host needs no code change,
        // and no address is ever read from a user-editable file in the field.
        buildConfigField(
            "String",
            "TUNER_URL",
            "\"http://192.168.2.93:8080/plex-tuner.html\""
        )
    }

    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = false
            // Signed with alex's release key when keystore.properties is present (never in the
            // repo); without it the build stays unsigned so anyone can still build locally.
            val signingProps = rootProject.file("keystore.properties")
            if (signingProps.exists()) {
                val props = Properties().apply { signingProps.inputStream().use { load(it) } }
                signingConfig = signingConfigs.create("release") {
                    storeFile = file(props.getProperty("storeFile"))
                    storePassword = props.getProperty("storePassword")
                    keyAlias = props.getProperty("keyAlias")
                    keyPassword = props.getProperty("keyPassword")
                }
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    lint {
        abortOnError = false
    }
}

// Deliberately no external dependencies: a framework Activity and a WebView need nothing else,
// which keeps the first build fast and immune to dependency-resolution failures.
dependencies {
}
