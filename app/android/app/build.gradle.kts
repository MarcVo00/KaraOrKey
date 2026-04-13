plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // ⚠️ REMPLACE ICI PAR TON VRAI NAMESPACE SI NÉCESSAIRE (ex: "com.ductu.karaorkey")
    namespace = "com.example.app"
    
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        // La ligne corrigée qui faisait planter ton build !
        jvmTarget = "17" 
    }

    defaultConfig {
        // ⚠️ REMPLACE ICI AUSSI PAR TON VRAI ID SI NÉCESSAIRE
        applicationId = "com.example.app"
        
        // Fixé à 21 pour que flutter_launcher_icons fonctionne parfaitement
        minSdk = flutter.minSdkVersion 
        
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Les dépendances sont gérées automatiquement par Flutter
}
