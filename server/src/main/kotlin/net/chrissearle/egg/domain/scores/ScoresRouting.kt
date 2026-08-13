package net.chrissearle.egg.domain.scores

import arrow.core.raise.either
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.plugins.ratelimit.RateLimitName
import io.ktor.server.plugins.ratelimit.rateLimit
import io.ktor.server.request.receive
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.routing
import net.chrissearle.egg.plugins.api.ApiError
import net.chrissearle.egg.plugins.api.respond

/**
 * The limiter submissions go through. Reading the board is not limited — it is
 * a cached file read, and the page itself needs it.
 */
val SUBMIT_LIMIT = RateLimitName("submit")

fun Application.configureScoresRouting(service: ScoresService) {
    routing {
        get("/api/scores") {
            // Explicit type: reading the board cannot fail, so there is no raise
            // for the error type to be inferred from.
            either<ApiError, Leaderboard> { service.leaderboard() }.respond()
        }

        rateLimit(SUBMIT_LIMIT) {
            post("/api/scores") {
                either { service.record(call.receive<ScoreSubmission>()) }
                    .respond(HttpStatusCode.Created)
            }
        }
    }
}
