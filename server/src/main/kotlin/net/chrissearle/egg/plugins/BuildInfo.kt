package net.chrissearle.egg.plugins

import arrow.core.raise.Raise
import arrow.core.raise.catch
import arrow.core.raise.context.raise
import arrow.core.raise.context.withError
import net.chrissearle.egg.plugins.api.ApiError
import net.chrissearle.egg.plugins.api.VersionNotReadable

object BuildInfo {
    context(_: Raise<ApiError>)
    fun imageTag(): String =
        withError(::VersionNotReadable) {
            catch({
                BuildInfo::class.java
                    .getResourceAsStream("/image-tag.txt")
                    ?.use { it.readBytes().decodeToString().trim() }
                    ?: "development"
            }) { raise(it) }
        }
}
