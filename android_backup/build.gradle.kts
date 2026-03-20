allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 📦 Establece el nuevo directorio de compilación raíz
val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

// 📦 Aplica nuevo buildDir a todos los subproyectos
subprojects {
    layout.buildDirectory.set(newBuildDir.dir(name))
    evaluationDependsOn(":app")
}

// 🧹 Tarea clean
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
