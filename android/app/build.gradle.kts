plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

import com.android.build.api.artifact.ArtifactTransformationRequest
import com.android.build.api.artifact.SingleArtifact
import com.android.build.api.variant.BuiltArtifact
import java.io.File
import java.util.Properties
import javax.inject.Inject
import org.gradle.api.file.Directory
import org.gradle.workers.WorkAction
import org.gradle.workers.WorkParameters
import org.gradle.workers.WorkerExecutor

val localBuildConfig = Properties()
val localBuildConfigFile = rootProject.projectDir.parentFile.resolve("config/local.env")
if (localBuildConfigFile.exists()) {
    localBuildConfigFile.inputStream().use { localBuildConfig.load(it) }
}

val googleMapsApiKey: String =
    System.getenv("GOOGLE_MAPS_API_KEY")
        ?: localBuildConfig.getProperty("GOOGLE_MAPS_API_KEY")
        ?: ""
val backendAuthTokenConfigured =
    (System.getenv("TC_BACKEND_AUTH_TOKEN")
        ?: localBuildConfig.getProperty("TC_BACKEND_AUTH_TOKEN")
        ?: "").isNotBlank()
val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

android {
    namespace = "com.example.astro_journal"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        resValues = true
    }

    defaultConfig {
        applicationId = "com.example.astro_journal"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        if (googleMapsApiKey.isNotEmpty()) {
            resValue("string", "google_maps_api_key", googleMapsApiKey)
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// 출력 APK를 기본 파일명(app-debug.apk 등) 대신 앱 이름 기준 파일명으로 복사한다.
// AGP 9의 새 Variant API는 SingleArtifact.APK가 ContainsMany이므로
// toTransformMany + Worker API로 각 APK 파일을 복사/재명명해야 한다.
// (Android Studio/Flutter 배포 호환을 위해 build/app/outputs/flutter-apk/의
// app-debug.apk는 그대로 유지되고, build/app/outputs/apk/<variant>/ 아래에
// "AstroJournal-<variant>-<version>.apk" 이름의 복사본이 추가로 생성된다.)
interface CopyApkParameters : WorkParameters {
    val inputApkFile: RegularFileProperty
    val outputApkFile: RegularFileProperty
}

abstract class CopyApkWorkAction : WorkAction<CopyApkParameters> {
    override fun execute() {
        val outputFile = parameters.outputApkFile.get().asFile
        outputFile.delete()
        parameters.inputApkFile.get().asFile.copyTo(outputFile)
    }
}

abstract class RenameApksTask : DefaultTask() {
    @get:InputFiles
    abstract val apkFolder: DirectoryProperty

    @get:OutputDirectory
    abstract val outFolder: DirectoryProperty

    @get:Input
    abstract val newFileName: Property<String>

    @get:Internal
    abstract val transformationRequest: Property<ArtifactTransformationRequest<RenameApksTask>>

    @get:Inject
    abstract val workers: WorkerExecutor

    @TaskAction
    fun taskAction() {
        transformationRequest.get().submit(
            this,
            workers.noIsolation(),
            CopyApkWorkAction::class.java,
        ) { builtArtifact: BuiltArtifact, outputLocation: Directory, params: CopyApkParameters ->
            val inputFile = File(builtArtifact.outputFile)
            params.inputApkFile.set(inputFile)
            val outFile = File(outputLocation.asFile, newFileName.get())
            params.outputApkFile.set(outFile)
            outFile
        }
    }
}

androidComponents {
    beforeVariants(selector().withBuildType("release")) {
        if (!releaseBuildRequested) return@beforeVariants
        if (googleMapsApiKey.isBlank()) {
            throw GradleException(
                "Release configuration is missing GOOGLE_MAPS_API_KEY. " +
                    "Use scripts/build_release.ps1.",
            )
        }
        if (!backendAuthTokenConfigured) {
            throw GradleException(
                "Release configuration is missing TC_BACKEND_AUTH_TOKEN. " +
                    "Use scripts/build_release.ps1.",
            )
        }
    }
    onVariants { variant ->
        val newFileName = "AstroJournal-${variant.buildType}-${flutter.versionName}.apk"
        val renameApksTask = tasks.register(
            "rename${variant.name.replaceFirstChar { it.uppercase() }}Apks",
            RenameApksTask::class.java,
        )
        val transformationRequest = variant.artifacts.use(renameApksTask)
            .wiredWithDirectories(RenameApksTask::apkFolder, RenameApksTask::outFolder)
            .toTransformMany(SingleArtifact.APK)
        renameApksTask.configure {
            this.newFileName.set(newFileName)
            this.transformationRequest.set(transformationRequest)
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
    implementation("com.google.android.gms:play-services-maps:20.0.0")
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("androidx.activity:activity-ktx:1.9.3")
}
