import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

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
// SPACE_SHIFT_V버전_YYYYMMDD.apk 규칙으로 함께 생성한다.
afterEvaluate {
    tasks.named("assembleRelease").configure {
        doLast {
            val sourceApk = layout.buildDirectory.file(
                "outputs/flutter-apk/app-release.apk",
            ).get().asFile
            val releaseVersion = android.defaultConfig.versionName
                ?.split(".")
                ?.take(2)
                ?.joinToString(".")
                ?: "1.0"
            val buildDate = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date())
            val outputName = "SPACE_SHIFT_v${releaseVersion}_${buildDate}.apk"

            copy {
                from(sourceApk)
                into(sourceApk.parentFile)
                rename { outputName }
            }

            // Galaxy Tab FINAL UI E2E 검증용 고정 파일명. versionCode가 바뀔
            // 때마다 WorkOrder에서 지정하는 이름이므로, 위 자동 명명 규칙과는
            // 별도로 versionCode를 직접 붙여 함께 생성한다.
            val e2eOutputName =
                "SPACE_SHIFT_V1_FINAL_UI_E2E_vc${android.defaultConfig.versionCode}.apk"
            copy {
                from(sourceApk)
                into(sourceApk.parentFile)
                rename { e2eOutputName }
            }
        }
    }
}
