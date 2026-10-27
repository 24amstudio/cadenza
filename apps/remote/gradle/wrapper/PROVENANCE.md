# Gradle wrapper

The Gradle 9.6.0 wrapper JAR is from the [official Gradle repository](https://github.com/gradle/gradle/blob/v9.6.0/gradle/wrapper/gradle-wrapper.jar). It is development tooling and is not included in either application.

Its SHA-256 is `497c8c2a7e5031f6aa847f88104aa80a93532ec32ee17bdb8d1d2f67a194a9c7`, verified against [Gradle's published checksum](https://services.gradle.org/distributions/gradle-9.6.0-wrapper.jar.sha256). The Gradle distribution checksum is pinned in `gradle-wrapper.properties`. Both artifacts are verified before use.

Gradle's Apache 2.0 license is preserved alongside this file. The small launcher scripts use Java and keep the distribution cache and temporary files inside the repository's `.cache` directory.
