plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// -PjmChannel=beta 构建可与正式版并存的 beta 版本：
// 独立 applicationId、独立桌面名称、独立下载目录。
val jmChannel: String = providers.gradleProperty("jmChannel").orNull ?: ""
val jmBeta: Boolean = jmChannel == "beta"

android {
    namespace = "app.jmpic.jm_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = if (jmBeta) "app.jmpic.jm_mobile.beta" else "app.jmpic.jm_mobile"
        manifestPlaceholders["appLabel"] = if (jmBeta) "kamico Beta" else "kamico"
        ndk {
            // Optional filter for a single-architecture local test package.
            providers.gradleProperty("jmAbi").orNull?.let {
                abiFilters.clear()
                abiFilters += it
            }
        }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                // aicolor.c 是纯 C，不依赖 C++ 运行时；ONNX Runtime 自带静态链接。
                arguments += listOf("-DANDROID_STL=none")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        configureEach {
            if (name == "debug" || name == "profile") {
                applicationIdSuffix = ".debug"
                manifestPlaceholders["appLabel"] =
                    if (jmBeta) "kamico Beta Debug" else "kamico Debug"
            }
        }
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
