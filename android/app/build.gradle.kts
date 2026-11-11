plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.tinder_universitario"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.tinder_universitario"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Demo con identidad y configuración nativas separadas; nunca instalar el
    // APK standard para pruebas con emuladores.
    flavorDimensions += "environment"
    productFlavors {
        create("development") {
            dimension = "environment"
            applicationIdSuffix = ".development"
        }
        create("production") { dimension = "environment" }
        create("standard") { dimension = "environment" }
        create("ligostaging") {
            dimension = "environment"
            applicationIdSuffix = ".ligostaging"
        }
        create("demo") {
            dimension = "environment"
            applicationIdSuffix = ".demo"
        }
    }

    signingConfigs {
        val storePath = System.getenv("TINDER_KEYSTORE_FILE")
        val storePasswordValue = System.getenv("TINDER_KEYSTORE_PASSWORD")
        val aliasValue = System.getenv("TINDER_KEY_ALIAS")
        val keyPasswordValue = System.getenv("TINDER_KEY_PASSWORD")
        if (!storePath.isNullOrBlank() && !storePasswordValue.isNullOrBlank() &&
            !aliasValue.isNullOrBlank() && !keyPasswordValue.isNullOrBlank()) {
            create("distribution") {
                storeFile = file(storePath)
                storePassword = storePasswordValue
                keyAlias = aliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            // Nunca distribuir un APK release firmado con la clave debug.
            signingConfig = signingConfigs.findByName("distribution")
        }
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

// No publicar una variante que haya heredado silenciosamente google-services.json.
tasks.configureEach {
    for (flavor in listOf("Production", "Development")) {
        if (name == "process${flavor}DebugGoogleServices" || name == "process${flavor}ReleaseGoogleServices") {
            doFirst {
                require(file("src/${flavor.lowercase()}/google-services.json").isFile) {
                    "Falta la configuración Firebase propia del flavor $flavor."
                }
            }
        }
    }
    if (name.startsWith("pre") && name.endsWith("ReleaseBuild")) {
        doFirst {
            require(android.signingConfigs.findByName("distribution") != null) {
                "Configura TINDER_KEYSTORE_FILE, TINDER_KEYSTORE_PASSWORD, TINDER_KEY_ALIAS y TINDER_KEY_PASSWORD fuera del repositorio."
            }
        }
    }
}
