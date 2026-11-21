allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// 说明：原模板里的 subprojects { project.evaluationDependsOn(":app") }
// 与 AGP 8.11+ 的 Kotlin DSL 不兼容（getDefaultConfig() 解析失败），已移除。
// 新版 Flutter 模板也不再需要这段。
