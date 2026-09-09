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
        // SS CAD TEST(공식) — Floorplan CAD 검증 전용 독립 앱. 기존 SPACE
        // SHIFT 본체(com.example.ason_space)와 별도 applicationId를 써서
        // 같은 Galaxy Tab에 동시 설치되고, 서로의 설치본을 덮어쓰지 않는다.
        // com.example.ason_space.sscadtest는 초기 조사 중 만든 구버전
        // 디버그 앱 id였고(현재 기기에서 이미 제거됨), 이 id와는 별개다 —
        // 동일한 것으로 취급하지 않는다.
        applicationId = "com.ason.sscadtest"
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
// SS_CAD_TEST_vc{versionCode}.apk 규칙으로 함께 생성해, SPACE SHIFT 본체
// 배포 빌드와 이 독립 CAD 검증 빌드를 파일명만으로도 명확히 구분한다.
afterEvaluate {
    tasks.named("assembleRelease").configure {
        doLast {
            val sourceApk = layout.buildDirectory.file(
                "outputs/flutter-apk/app-release.apk",
            ).get().asFile
            val versionCode = android.defaultConfig.versionCode
            val outputName = "SS_CAD_TEST_vc${versionCode}.apk"

            copy {
                from(sourceApk)
                into(sourceApk.parentFile)
                rename { outputName }
            }
        }
    }
}
