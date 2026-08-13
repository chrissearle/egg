package net.chrissearle.egg.domain.scores

import arrow.core.raise.either
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.collections.shouldContainExactly
import io.kotest.matchers.shouldBe
import io.kotest.matchers.types.shouldBeInstanceOf
import net.chrissearle.egg.plugins.api.ApiError
import net.chrissearle.egg.plugins.api.ScoreLevelOutOfRange
import net.chrissearle.egg.plugins.api.ScoreNameNotPrintable
import net.chrissearle.egg.plugins.api.ScoreNameRequired
import net.chrissearle.egg.plugins.api.ScoreNameTooLong
import net.chrissearle.egg.plugins.api.ScoreNotAMultipleOfTen
import net.chrissearle.egg.plugins.api.ScoreOutOfRange
import java.io.File
import kotlin.time.Clock
import kotlin.time.Duration
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.hours
import kotlin.time.Instant

private val NOW = Instant.parse("2026-08-13T12:00:00Z")

private class FixedClock(
    private val at: Instant
) : Clock {
    override fun now() = at
}

private fun tempStore(): Pair<ScoreStore, File> {
    val file = File.createTempFile("scores", ".jsonl").also { it.delete() }
    return ScoreStore(file) to file
}

private fun service(store: ScoreStore) = ScoresService(store, FixedClock(NOW))

private fun aged(
    age: Duration,
    score: Int,
    name: String
) = Score(ts = (NOW - age).toString(), name = name, score = score, level = 1)

class ScoresServiceTest :
    StringSpec({
        "records a valid submission with the server's timestamp" {
            val (store, file) = tempStore()

            val result = either { service(store).record(ScoreSubmission("CHRIS", 7200, 4)) }

            result.getOrNull()?.ts shouldBe NOW.toString()
            // The client never supplies the time, so it cannot forge one.
            file.readLines().single().contains("\"ts\":\"$NOW\"") shouldBe true
            file.delete()
        }

        "writes exactly one line per score, so the file stays vi-editable" {
            val (store, file) = tempStore()
            val svc = service(store)

            either { svc.record(ScoreSubmission("A", 100, 1)) }
            either { svc.record(ScoreSubmission("B", 200, 2)) }

            file.readLines().size shouldBe 2
            file.delete()
        }

        "rejects a blank name" {
            val (store, _) = tempStore()
            either { service(store).record(ScoreSubmission("   ", 100, 1)) }
                .leftOrNull() shouldBe ScoreNameRequired
        }

        "rejects a name longer than the game's own buffer" {
            val (store, _) = tempStore()
            either { service(store).record(ScoreSubmission("TOOMANYCHARS", 100, 1)) }
                .leftOrNull()
                .shouldBeInstanceOf<ScoreNameTooLong>()
        }

        "rejects a name the game's font cannot draw" {
            val (store, _) = tempStore()
            either { service(store).record(ScoreSubmission("CHRISé", 100, 1)) }
                .leftOrNull()
                .shouldBeInstanceOf<ScoreNameNotPrintable>()
        }

        "rejects a score that is not a multiple of ten" {
            val (store, _) = tempStore()
            either { service(store).record(ScoreSubmission("CHRIS", 105, 1)) }
                .leftOrNull()
                .shouldBeInstanceOf<ScoreNotAMultipleOfTen>()
        }

        "rejects an impossible score" {
            val (store, _) = tempStore()
            either { service(store).record(ScoreSubmission("CHRIS", MAX_SCORE + 10, 1)) }
                .leftOrNull()
                .shouldBeInstanceOf<ScoreOutOfRange>()
        }

        "rejects an implausible level" {
            val (store, _) = tempStore()
            either { service(store).record(ScoreSubmission("CHRIS", 100, 0)) }
                .leftOrNull()
                .shouldBeInstanceOf<ScoreLevelOutOfRange>()
        }

        "nothing reaches the store when validation fails" {
            val (store, file) = tempStore()
            either { service(store).record(ScoreSubmission("", 105, 0)) }
            file.exists() shouldBe false
        }

        "buckets entries into the four windows" {
            val (store, file) = tempStore()
            store.append(aged(2.hours, 100, "TODAY"))
            store.append(aged(3.days, 200, "WEEK"))
            store.append(aged(10.days, 300, "MONTH"))
            store.append(aged(400.days, 400, "ANCIENT"))

            val board = service(store).leaderboard()

            board.last24h.map { it.name } shouldContainExactly listOf("TODAY")
            board.last7d.map { it.name } shouldContainExactly listOf("WEEK", "TODAY")
            board.last30d.map { it.name } shouldContainExactly listOf("MONTH", "WEEK", "TODAY")
            board.allTime.map { it.name } shouldContainExactly listOf("ANCIENT", "MONTH", "WEEK", "TODAY")
            file.delete()
        }

        "orders by score and caps each window at the board size" {
            val (store, file) = tempStore()
            repeat(BOARD_SIZE + 5) { store.append(aged(1.hours, (it + 1) * 10, "P$it")) }

            val board = service(store).leaderboard()

            board.allTime.size shouldBe BOARD_SIZE
            board.allTime.first().score shouldBe (BOARD_SIZE + 5) * 10
            file.delete()
        }

        "a malformed line costs one entry, not the whole board" {
            val (store, file) = tempStore()
            store.append(aged(1.hours, 100, "GOOD"))
            file.appendText("{ this is what a slip in vi looks like\n")
            store.append(aged(1.hours, 200, "ALSOGOOD"))

            val board = service(store).leaderboard()

            board.allTime.map { it.name } shouldContainExactly listOf("ALSOGOOD", "GOOD")
            file.delete()
        }

        "an unparseable timestamp still counts for all time" {
            val (store, file) = tempStore()
            file.writeText("""{"ts":"not-a-date","name":"ODD","score":500,"level":1}""" + "\n")

            val board = service(store).leaderboard()

            board.allTime.map { it.name } shouldContainExactly listOf("ODD")
            board.last24h.shouldBeInstanceOf<List<Score>>().size shouldBe 0
            file.delete()
        }

        "an edit made outside the process is picked up" {
            val (store, file) = tempStore()
            store.append(aged(1.hours, 100, "RUDE"))
            store.all().single().name shouldBe "RUDE"

            // What `vi` does: rewrite the file behind the running server. "NICE"
            // is the same length as "RUDE" on purpose, so the file's size is
            // unchanged and only the modification time can betray the edit —
            // which is the half of the cache key actually under test.
            file.writeText(storeLine("NICE"))
            file.setLastModified(file.lastModified() + TOUCH_GAP_MS)

            store.all().single().name shouldBe "NICE"
            file.delete()
        }

        "a missing store reads as an empty board" {
            val (store, _) = tempStore()
            store.all() shouldContainExactly emptyList()
        }

        "an error carries a 4xx for a client mistake" {
            val (store, _) = tempStore()
            val error: ApiError? = either { service(store).record(ScoreSubmission("", 100, 1)) }.leftOrNull()
            error?.response?.status?.value shouldBe 400
        }
    })

/**
 * Pushed far enough forward to clear any filesystem timestamp granularity —
 * set explicitly rather than slept for, so the test stays instant.
 */
private const val TOUCH_GAP_MS = 2000L

private fun storeLine(name: String) = """{"ts":"$NOW","name":"$name","score":100,"level":1}""" + "\n"
