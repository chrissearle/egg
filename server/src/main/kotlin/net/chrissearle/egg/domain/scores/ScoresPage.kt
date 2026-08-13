package net.chrissearle.egg.domain.scores

import io.ktor.server.application.Application
import io.ktor.server.html.respondHtml
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import kotlinx.html.FlowContent
import kotlinx.html.div
import kotlinx.html.h1
import kotlinx.html.h2
import kotlinx.html.section
import net.chrissearle.egg.plugins.site.Ink
import net.chrissearle.egg.plugins.site.buttonLink
import net.chrissearle.egg.plugins.site.logo
import net.chrissearle.egg.plugins.site.page
import net.chrissearle.egg.plugins.site.pixelText
import net.chrissearle.egg.plugins.site.scoreRow

private fun FlowContent.board(
    heading: String,
    entries: List<Score>
) {
    section {
        h2 { pixelText(heading, Ink.MAGENTA, half = true) }

        if (entries.isEmpty()) {
            div("empty") { +"Nothing yet — be the first." }
            return@section
        }

        div("board") {
            entries.forEachIndexed { index, entry ->
                div("row") { pixelText(scoreRow(index + 1, entry), Ink.GREEN, half = true) }
            }
        }
    }
}

/**
 * The leaderboard, rendered live from the store on every request.
 *
 * There is no cron and no generated file: the page reads what is on disk now,
 * so an admin who edits a name in `scores.jsonl` sees it here on the next
 * refresh with nothing to re-run. `ScoreStore` caches on (mtime, length), so a
 * burst of requests still only parses once.
 */
fun Application.configureScoresPage(service: ScoresService) {
    routing {
        get("/scores") {
            val leaderboard = service.leaderboard()

            call.respondHtml {
                page("High Scores — Chuckie Egg") {
                    logo()
                    h1 { pixelText("HIGH SCORES", Ink.YELLOW) }

                    board("LAST 24 HOURS", leaderboard.last24h)
                    board("LAST 7 DAYS", leaderboard.last7d)
                    board("LAST 30 DAYS", leaderboard.last30d)
                    board("ALL TIME", leaderboard.allTime)

                    div("actions") {
                        buttonLink("/play/", "Play", primary = true)
                        buttonLink("/", "Home")
                    }
                }
            }
        }
    }
}
