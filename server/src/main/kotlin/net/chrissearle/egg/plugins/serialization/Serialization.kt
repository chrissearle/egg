package net.chrissearle.egg.plugins.serialization

import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import kotlinx.serialization.json.Json

/**
 * The store is JSON Lines, so its encoder must never pretty-print: one entry
 * has to be exactly one line for the file to stay hand-editable in vi.
 */
val storeJson =
    Json {
        prettyPrint = false
        ignoreUnknownKeys = true
        explicitNulls = false
    }

fun Application.configureSerialization() {
    install(ContentNegotiation) {
        json(
            Json {
                prettyPrint = true
                isLenient = true
                ignoreUnknownKeys = true
                explicitNulls = false
            }
        )
    }
}
