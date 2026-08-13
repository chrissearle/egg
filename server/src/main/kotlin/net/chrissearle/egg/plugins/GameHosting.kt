package net.chrissearle.egg.plugins

import io.github.oshai.kotlinlogging.KotlinLogging
import io.ktor.server.application.Application
import io.ktor.server.http.content.staticFiles
import io.ktor.server.http.content.staticResources
import io.ktor.server.response.respondRedirect
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import java.io.File

private val logger = KotlinLogging.logger {}

/** Where the exported game lives, below the site root. */
const val PLAY_PATH = "/play"

/**
 * Serves the exported game, the site's stylesheet, and the generated art the
 * pages are built from.
 *
 * The game sits at [PLAY_PATH] rather than the root so that `/` can be a
 * landing page carrying the controls, the credits and — not optional — the
 * offer of source that GPL-3.0 requires when the WebAssembly build is handed to
 * a visitor.
 *
 * `/play` is a path, not a second origin, so nobody's locally stored high
 * scores or key bindings were disturbed by the move.
 *
 * Everything is same-origin — game, API, pages and assets — which is why there
 * is no CORS configuration anywhere in this project.
 */
fun Application.configureGameHosting(
    webDir: File,
    assetsDir: File
) {
    routing {
        // The export's index.html asks for index.js and index.wasm by relative
        // path, so those have to resolve against /play/ — without the trailing
        // slash they would resolve against the site root and 404.
        get(PLAY_PATH) {
            call.respondRedirect("$PLAY_PATH/", permanent = true)
        }

        staticResources("/static", "static")

        if (assetsDir.isDirectory) {
            staticFiles("/assets", assetsDir)
        } else {
            logger.warn { "No generated assets at ${assetsDir.absolutePath} — the pages will be unstyled" }
        }

        if (webDir.isDirectory) {
            logger.info { "Serving the game from ${webDir.absolutePath}" }
            staticFiles(PLAY_PATH, webDir) {
                default("index.html")
            }
        } else {
            // Not fatal: the landing page, the leaderboard and the API are all
            // still worth serving, and a missing export should look like a 404
            // rather than a crashlooping pod.
            logger.warn { "No game export at ${webDir.absolutePath} — $PLAY_PATH will 404" }
        }
    }
}
