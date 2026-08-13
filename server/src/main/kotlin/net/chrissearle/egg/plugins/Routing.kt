package net.chrissearle.egg.plugins

import arrow.core.raise.either
import io.github.oshai.kotlinlogging.KotlinLogging
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.compression.Compression
import io.ktor.server.plugins.compression.gzip
import io.ktor.server.plugins.compression.minimumSize
import io.ktor.server.plugins.forwardedheaders.XForwardedHeaders
import io.ktor.server.plugins.ratelimit.RateLimit
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.request.uri
import io.ktor.server.response.respond
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import net.chrissearle.egg.domain.scores.SUBMIT_LIMIT
import net.chrissearle.egg.plugins.api.ErrorResponse
import net.chrissearle.egg.plugins.api.respondPlainText
import kotlin.time.Duration.Companion.minutes

private val logger = KotlinLogging.logger {}

private const val SUBMITS_PER_MINUTE = 20
private const val COMPRESS_FROM_BYTES = 1024L

fun Application.configureRouting() {
    // Traefik terminates TLS and proxies, so the socket's peer is the ingress,
    // not the player. Without this every submission shares one rate-limit key.
    install(XForwardedHeaders)

    // The wasm is ~38MB uncompressed and compresses to roughly a quarter of it.
    install(Compression) {
        gzip {
            minimumSize(COMPRESS_FROM_BYTES)
        }
    }

    install(RateLimit) {
        register(SUBMIT_LIMIT) {
            rateLimiter(limit = SUBMITS_PER_MINUTE, refillPeriod = 1.minutes)
            requestKey { call -> call.request.local.remoteHost }
        }
    }

    install(StatusPages) {
        exception<Throwable> { call, cause ->
            logger.error(cause) { "Unhandled exception for ${call.request.uri}" }

            call.respond(
                HttpStatusCode.InternalServerError,
                mapOf(
                    "error" to
                        ErrorResponse(
                            status = HttpStatusCode.InternalServerError,
                            message = "Internal server error"
                        )
                )
            )
        }
    }

    routing {
        get("/health") {
            call.respondText("status: \"UP\"")
        }

        get("/version") {
            either {
                BuildInfo.imageTag()
            }.respondPlainText()
        }
    }
}
