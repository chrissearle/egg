package net.chrissearle.egg.domain.analytics

import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.response.respond
import io.ktor.server.routing.get
import io.ktor.server.routing.routing

/**
 * Hands the settings to `/static/analytics.js`, which every page and the game
 * load. A route rather than markup baked into each page: the game's HTML is a
 * Godot export that cannot be templated, and both read the same answer here.
 * No content when nothing is configured, and the script then loads nothing.
 */
fun Application.configureAnalytics(settings: AnalyticsSettings?) {
    routing {
        get("/api/analytics") {
            if (settings == null) {
                call.respond(HttpStatusCode.NoContent)
            } else {
                call.respond(settings)
            }
        }
    }
}
