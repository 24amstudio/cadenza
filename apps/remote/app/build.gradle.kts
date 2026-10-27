import com.android.build.api.variant.HostTestBuilder
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.FileSystemOperations
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Properties
import javax.inject.Inject

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jlleitschuh.gradle.ktlint")
}

val cadenzaVersion =
    Properties().apply {
        rootProject.file("../../shared/version.properties").inputStream().use(::load)
    }
val buildInstant = providers.environmentVariable("SOURCE_DATE_EPOCH").orNull?.let { Instant.ofEpochSecond(it.toLong()) } ?: Instant.now()
val buildTimestamp = DateTimeFormatter.ofPattern("yyyyMMdd.HHmmss").withZone(ZoneOffset.UTC).format(buildInstant)
val releaseStore = providers.environmentVariable("CADENZA_KEYSTORE_PATH").orNull
val releaseStorePassword = providers.environmentVariable("CADENZA_KEYSTORE_PASSWORD").orNull
val releaseAlias = providers.environmentVariable("CADENZA_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("CADENZA_KEY_PASSWORD").orNull
val releaseSigningAvailable =
    listOf(releaseStore, releaseStorePassword, releaseAlias, releaseKeyPassword).all { !it.isNullOrBlank() }
val buildProfile = providers.gradleProperty("cadenza.profile").getOrElse("development")
check(buildProfile in listOf("development", "ci", "production")) { "Unknown Cadenza build profile." }
check(buildProfile != "production" || providers.environmentVariable("CI").orNull != "true") {
    "Checking and Build CI must not enable Production updates."
}
val sourceIdentity =
    providers
        .exec {
            workingDir(rootProject.file("../.."))
            commandLine("node", "tools/build-info.mjs")
        }.standardOutput.asText
        .map { it.trim().also { value -> check(value.matches(Regex("([0-9a-f]{40}|source-[0-9a-f]{64})"))) } }

android {
    namespace = "app.cadenza.remote"
    compileSdk = 37
    buildToolsVersion = "36.0.0"

    defaultConfig {
        applicationId = "app.cadence.remote"
        minSdk = 26
        targetSdk = 37
        versionCode = cadenzaVersion.getProperty("VERSION_CODE").toInt()
        versionName = cadenzaVersion.getProperty("VERSION_NAME")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        manifestPlaceholders["cadenzaBuildProfile"] = "development"
        buildConfigField("String", "BUILD_ID", "\"${sourceIdentity.get()}\"")
        buildConfigField("String", "BUILD_TIMESTAMP", "\"$buildTimestamp\"")
    }

    signingConfigs {
        getByName("debug") {
            storeFile = rootProject.file("../../.cache/android-user/debug.keystore")
        }
        if (releaseSigningAvailable) {
            create("release") {
                storeFile = file(requireNotNull(releaseStore))
                storePassword = releaseStorePassword
                keyAlias = releaseAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-dev"
            buildConfigField("String", "BUILD_PROFILE", "\"development\"")
            buildConfigField("boolean", "AUTOMATIC_UPDATES", "false")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (releaseSigningAvailable) signingConfig = signingConfigs.getByName("release")
            buildConfigField("String", "BUILD_PROFILE", "\"$buildProfile\"")
            manifestPlaceholders["cadenzaBuildProfile"] = buildProfile
            buildConfigField("boolean", "AUTOMATIC_UPDATES", (buildProfile == "production").toString())
            if (buildProfile == "ci") {
                applicationIdSuffix = ".ci"
                versionNameSuffix = "-ci"
                signingConfig = signingConfigs.getByName("debug")
            }
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all {
            val testUserHome = rootProject.file("../../.cache/test-user")
            it.systemProperty("user.home", testUserHome.absolutePath)
            it.doFirst { check(testUserHome.mkdirs() || testUserHome.isDirectory) }
            it.systemProperty("maven.repo.local", rootProject.file("../../.cache/robolectric-m2").absolutePath)
            it.systemProperty("cadenza.evidence.directory", rootProject.file("../../dist/evidence").absolutePath)
            it.jvmArgs(
                "--add-opens=java.base/java.lang=ALL-UNNAMED",
                "--add-opens=java.base/java.util=ALL-UNNAMED",
                "--add-opens=java.base/java.io=ALL-UNNAMED",
                "--add-opens=java.base/java.net=ALL-UNNAMED",
                "--add-opens=java.base/java.security=ALL-UNNAMED",
                "--add-opens=java.base/java.text=ALL-UNNAMED",
                "--add-opens=java.base/jdk.internal.access=ALL-UNNAMED",
                "--add-opens=java.desktop/java.awt.font=ALL-UNNAMED",
                "--add-opens=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED",
            )
        }
    }
    lint {
        abortOnError = true
        warningsAsErrors = true
        checkDependencies = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        allWarningsAsErrors.set(true)
    }
}

ktlint {
    version.set("1.7.1")
    ignoreFailures.set(false)
}

abstract class GenerateCadenzaAssets
    @Inject
    constructor(
        private val fileSystem: FileSystemOperations,
    ) : DefaultTask() {
        @get:InputDirectory
        @get:PathSensitive(PathSensitivity.RELATIVE)
        abstract val schemas: DirectoryProperty

        @get:InputFile
        @get:PathSensitive(PathSensitivity.NONE)
        abstract val releaseConfiguration: RegularFileProperty

        @get:InputFile
        @get:PathSensitive(PathSensitivity.NONE)
        abstract val changelog: RegularFileProperty

        @get:Input
        abstract val buildIdentity: Property<String>

        @get:OutputDirectory
        abstract val outputDirectory: DirectoryProperty

        @TaskAction
        fun generate() {
            fileSystem.sync {
                from(schemas) {
                    include("*.sql")
                    into("storage")
                }
                from(releaseConfiguration)
                from(changelog)
                into(outputDirectory)
            }
            outputDirectory
                .file("build-identity.txt")
                .get()
                .asFile
                .writeText(buildIdentity.get() + "\n")
        }
    }

val generateCadenzaAssets =
    tasks.register<GenerateCadenzaAssets>("generateCadenzaAssets") {
        schemas.set(rootProject.layout.projectDirectory.dir("storage"))
        releaseConfiguration.set(rootProject.layout.projectDirectory.file("../../shared/release-config.json"))
        changelog.set(rootProject.layout.projectDirectory.file("../../shared/changelog.json"))
        buildIdentity.set(sourceIdentity)
        outputDirectory.set(layout.buildDirectory.dir("generated/cadenzaAssets"))
    }

androidComponents.beforeVariants(androidComponents.selector().withBuildType("release")) { variant ->
    variant.hostTests.getValue(HostTestBuilder.UNIT_TEST_TYPE).enable = true
}

androidComponents.onVariants { variant ->
    variant.sources.assets?.addGeneratedSourceDirectory(generateCadenzaAssets, GenerateCadenzaAssets::outputDirectory)
}
tasks.matching { it.name == "packageRelease" }.configureEach {
    doFirst {
        check(buildProfile == "ci" || releaseSigningAvailable) {
            "Set CADENZA_KEYSTORE_PATH, CADENZA_KEYSTORE_PASSWORD, CADENZA_KEY_ALIAS, and CADENZA_KEY_PASSWORD for a signed release."
        }
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core-ktx:1.19.1")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.11.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3:1.5.0-beta02")
    implementation("androidx.compose.material3.adaptive:adaptive:1.3.0")
    implementation("androidx.compose.material3.adaptive:adaptive-layout:1.3.0")
    implementation("androidx.compose.material3.adaptive:adaptive-navigation:1.3.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("com.squareup.okhttp3:okhttp:5.5.1")
    implementation("com.google.zxing:core:3.5.4")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20260814")
    testImplementation("org.robolectric:robolectric:4.17")
    testImplementation("androidx.compose.ui:ui-test-junit4")
}
