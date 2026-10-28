import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "uy.miriouy.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Lo necesita flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // No cambiar después del primer APK repartido: Android lo trataría como otra app.
        applicationId = "uy.miriouy.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Clave de firma propia: app/android/key.properties (fuera de git) apunta al .jks.
    // Sin ese archivo el build de release FALLA: antes se firmaba con la clave de
    // depuración y un APK así podía terminar repartido por error (hallazgo B-4).
    // Para compilar de prueba sin clave (CI, verificación local) hay que pedirlo
    // a propósito con la propiedad firmaDebugPrueba=true:
    //   FIRMA_DEBUG_PRUEBA=true flutter build apk --release
    //   (o -PfirmaDebugPrueba=true si se llama a gradlew directo)
    // Ese APK queda firmado con la clave de depuración: no repartirlo.
    val propiedadesFirma = Properties()
    val archivoFirma = rootProject.file("key.properties")
    if (archivoFirma.exists()) {
        archivoFirma.inputStream().use { propiedadesFirma.load(it) }
    }
    val firmaDebugPrueba = project.findProperty("firmaDebugPrueba")?.toString() == "true" ||
        System.getenv("FIRMA_DEBUG_PRUEBA") == "true"

    signingConfigs {
        if (archivoFirma.exists()) {
            create("release") {
                storeFile = file(propiedadesFirma.getProperty("storeFile"))
                storePassword = propiedadesFirma.getProperty("storePassword")
                keyAlias = propiedadesFirma.getProperty("keyAlias")
                keyPassword = propiedadesFirma.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                archivoFirma.exists() -> signingConfigs.getByName("release")
                firmaDebugPrueba -> {
                    logger.warn("AVISO: firmaDebugPrueba=true y no hay key.properties; el APK se firma con la clave de depuración. No repartirlo.")
                    signingConfigs.getByName("debug")
                }
                else -> null
            }
        }
    }

    // El debug sigue compilando sin clave; solo se corta cuando se arma un release.
    gradle.taskGraph.whenReady {
        val armaRelease = allTasks.any { t ->
            t.project == project &&
                Regex("^(assemble|bundle|package)Release$").matches(t.name)
        }
        if (armaRelease && !archivoFirma.exists() && !firmaDebugPrueba) {
            throw GradleException(
                "Falta app/android/key.properties: el release no se firma con la clave de depuración. " +
                    "Creá key.properties con la clave de firma, o para una compilación de prueba (que no se reparte) " +
                    "pasá la propiedad firmaDebugPrueba=true (o la variable de entorno FIRMA_DEBUG_PRUEBA=true)."
            )
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
