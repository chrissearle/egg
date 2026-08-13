package net.chrissearle.egg.plugins.site

import io.ktor.server.application.Application
import io.ktor.server.html.respondHtml
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import kotlinx.html.FlowContent
import kotlinx.html.TBODY
import kotlinx.html.TD
import kotlinx.html.a
import kotlinx.html.div
import kotlinx.html.footer
import kotlinx.html.h1
import kotlinx.html.h2
import kotlinx.html.kbd
import kotlinx.html.li
import kotlinx.html.p
import kotlinx.html.section
import kotlinx.html.table
import kotlinx.html.tbody
import kotlinx.html.td
import kotlinx.html.th
import kotlinx.html.tr
import kotlinx.html.ul
import net.chrissearle.egg.domain.scores.Score
import net.chrissearle.egg.domain.scores.ScoresService

/** How many all-time entries the front page teases before linking to the rest. */
private const val TEASER_SIZE = 5

/**
 * The controls.
 *
 * Labelled as **defaults** on purpose. Movement and jump are rebindable from
 * the game's own KEYS screen and those bindings live per-browser, so for anyone
 * who has changed them this table would otherwise be quietly wrong. The game
 * shows the real bindings on that screen; this only promises what a fresh
 * browser starts with.
 */
private fun FlowContent.controls() {
    section {
        h2 { pixelText("CONTROLS", Ink.MAGENTA, half = true) }

        table("controls") {
            tbody {
                controlRow("Move") {
                    kbd { +"←" }
                    +" "
                    kbd { +"→" }
                    +" "
                    kbd { +"↑" }
                    +" "
                    kbd { +"↓" }
                    +" — or a gamepad d-pad / left stick"
                }
                controlRow("Jump") {
                    kbd { +"Space" }
                    +" — or "
                    kbd { +"A" }
                    +" on a gamepad"
                }
                controlRow("Start") {
                    kbd { +"S" }
                    +" — or "
                    kbd { +"A" }
                    +" / "
                    kbd { +"Start" }
                }
                controlRow("Players") {
                    kbd { +"1" }
                    +"–"
                    kbd { +"4" }
                    +" — or pick with the d-pad and confirm"
                }
                controlRow("Change keys") {
                    kbd { +"K" }
                    +" at the title screen"
                }
                controlRow("Hold") { kbd { +"H" } }
                controlRow("Quit to title") {
                    kbd { +"Escape" }
                    +" + "
                    kbd { +"H" }
                }
            }
        }

        controlsNote()
    }
}

/**
 * Why the table above says "defaults" and means it.
 *
 * A player who has rebound their keys has those bindings stored in this
 * browser, where the page cannot see them without reaching into Godot's
 * IndexedDB store. Rather than risk showing someone else's controls as if they
 * were theirs, the page promises only what a fresh browser starts with and
 * points at the screen that knows the truth.
 */
private fun FlowContent.controlsNote() {
    p("prose") {
        +"Movement and jump are defaults — press "
        kbd { +"K" }
        +" at the title screen to rebind them, and that screen also shows whatever you are "
        +"currently using. "
        kbd { +"H" }
        +" and "
        kbd { +"Escape" }
        +" are the only keys that cannot be reassigned, because the game reads them while "
        +"you are playing."
    }
}

private fun TBODY.controlRow(
    label: String,
    value: TD.() -> Unit
) {
    tr {
        th { +label }
        td { value() }
    }
}

/**
 * Attribution and licence.
 *
 * This is not decoration. Serving the WebAssembly build hands the visitor a
 * copy of a GPL-3.0 program, which is conveying it rather than the "network use
 * is not distribution" case — so the offer of source has to be here, in front
 * of the person receiving the binary.
 */
private fun FlowContent.credits() {
    footer {
        div("prose") {
            h2 { +"About" }
            p {
                +"A faithful recreation of the 1983 BBC Micro 32K game "
                +"Chuckie Egg"
                +", written by Doug Anderson and published by A&F Software. The original's "
                +"integer movement arithmetic, tile layouts, colours and timing are reproduced "
                +"as they were rather than re-tuned."
            }

            h2 { +"Credits" }
            ul {
                li {
                    +"The original game — "
                    +"Chuckie Egg, A&F Software, 1983. BBC Micro version by Doug Anderson; "
                    +"the ZX Spectrum original by Nigel Alderton."
                }
                li {
                    a(href = "https://github.com/pbrook/Chuckie-Egg") { +"pbrook/Chuckie-Egg" }
                    +" by Paul Brook — the C/SDL reference implementation this is ported from."
                }
                li {
                    a(href = "https://github.com/mungre/chuckie") { +"mungre/chuckie" }
                    +" — an annotated disassembly of the BBC release, the source of the tunes "
                    +"and the front-end screens."
                }
                li {
                    a(href = "https://github.com/robhagemans/hoard-of-bitfonts") {
                        +"robhagemans/hoard-of-bitfonts"
                    }
                    +" — the BBC OS font, which is the lettering on this page."
                }
            }

            h2 { +"Licence" }
            p {
                +"Licensed under the GNU General Public License v3.0. This is a derivative "
                +"work of pbrook/Chuckie-Egg, so GPL-3.0 is a requirement here rather than a "
                +"preference. The complete source is at "
                a(href = SOURCE_URL) { +"github.com/chrissearle/ChuckieEgg" }
                +"."
            }
            p {
                +"Chuckie Egg and any associated trade marks remain the property of their "
                +"respective owners. This is a non-commercial fan recreation, made out of "
                +"respect for the original, and is not affiliated with or endorsed by A&F "
                +"Software."
            }
        }
    }
}

private fun FlowContent.teaser(entries: List<Score>) {
    section {
        h2 { pixelText("HIGH SCORES", Ink.MAGENTA, half = true) }

        if (entries.isEmpty()) {
            div("empty") { +"Nothing yet — be the first." }
        } else {
            div("board") {
                entries.take(TEASER_SIZE).forEachIndexed { index, entry ->
                    div("row") { pixelText(scoreRow(index + 1, entry), Ink.GREEN, half = true) }
                }
            }
        }

        div("actions") { buttonLink("/scores", "All high scores") }
    }
}

fun Application.configureLandingPage(service: ScoresService) {
    routing {
        get("/") {
            val leaderboard = service.leaderboard()

            call.respondHtml {
                page("Chuckie Egg") {
                    logo()
                    h1 {
                        pixelText("Hen House Harry rides again", Ink.YELLOW, half = true, wrap = true)
                    }

                    div("actions") {
                        buttonLink("/play/", "Play", primary = true)
                        buttonLink("/scores", "High scores")
                        buttonLink(SOURCE_URL, "Source")
                    }

                    teaser(leaderboard.allTime)
                    controls()
                    credits()
                }
            }
        }
    }
}
