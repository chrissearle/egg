plugins {
    alias(libs.plugins.kotlin)
    alias(libs.plugins.ktor)
    alias(libs.plugins.kotlinter)
    alias(libs.plugins.detekt)
    alias(libs.plugins.versions)
    alias(libs.plugins.serialization)
    alias(libs.plugins.dependency.analysis)
    jacoco
}

group = "net.chrissearle"
version = "0.0.1"

application {
    mainClass.set("net.chrissearle.egg.ApplicationKt")
    applicationName = "egg"
}

base {
    archivesName = "egg"
}

kotlin {
    jvmToolchain(25)

    compilerOptions {
        freeCompilerArgs = listOf("-Xconsistent-data-class-copy-visibility")
    }
}

repositories {
    mavenCentral()
}

dependencies {
    implementation(libs.bundles.ktor.server)
    implementation(libs.bundles.serialization)
    implementation(libs.bundles.monitoring)
    implementation(libs.arrow.core)
    runtimeOnly(libs.logback.classic)

    testImplementation(libs.bundles.test)
    testRuntimeOnly(libs.kotlin.test.junit)
}

jacoco {
    toolVersion = libs.versions.jacoco.get()
}

tasks.check {
    dependsOn(tasks.detektMain, tasks.detektTest)
}

listOf("distTar", "distZip", "shadowJar", "startShadowScripts", "shadowDistTar", "shadowDistZip").forEach { name ->
    tasks.named(name) { enabled = false }
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
}

tasks.test {
    finalizedBy(tasks.jacocoTestReport)
}

tasks.jacocoTestReport {
    dependsOn(tasks.test)
}
