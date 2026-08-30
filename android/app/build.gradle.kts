plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.ason_space"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.ason_space"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// `flutter build apk --release`가 완료될 때 Galaxy Tab 배포용 APK를
// SPACE_SHIFT_V1_MASTER_TAB_E2E_vc{versionCode}.apk 규칙으로 함께 생성해,
// 이번 WorkOrder(MASTER UI 정합성 통합) 설치본을 다른 빌드와 명확히 구분한다.
afterEvaluate {
    tasks.named("assembleRelease").configure {
        doLast {
            val sourceApk = layout.buildDirectory.file(
                "outputs/flutter-apk/app-release.apk",
            ).get().asFile
            val versionCode = android.defaultConfig.versionCode
            val outputName = "SPACE_SHIFT_V1_MASTER_TAB_E2E_vc${versionCode}.apk"

            copy {
                from(sourceApk)
                into(sourceApk.parentFile)
                rename { outputName }
            }
        }
    }
}
