package net.chrissearle.egg.domain.scores

import io.github.oshai.kotlinlogging.KotlinLogging
import net.chrissearle.egg.plugins.serialization.storeJson
import java.io.File
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

private val logger = KotlinLogging.logger {}

/**
 * The score store: one JSON object per line, appended to and never rewritten.
 *
 * The format is chosen for the admin path rather than for the code. A name that
 * turns out to be rude is fixed by opening this file in vi and changing it, so
 * it has to stay one-record-per-line and human-readable. That rules out SQLite
 * and rules out pretty-printed JSON, which is why `storeJson` disables it.
 *
 * Because a human edits it, **a malformed line is skipped, not fatal**. A stray
 * keystroke in vi must cost one entry, not take the whole leaderboard down.
 */
class ScoreStore(
    private val file: File
) {
    private val lock = ReentrantLock()

    /**
     * Parsed contents, with the file's modification time and length they were
     * parsed from. A burst of requests re-reads nothing; an edit in vi changes
     * both, so the next request picks it up with no cache to invalidate by hand.
     */
    private var cached: List<Score> = emptyList()
    private var cachedStamp: Pair<Long, Long>? = null

    fun append(score: Score) {
        lock.withLock {
            file.parentFile?.mkdirs()
            file.appendText(storeJson.encodeToString(score) + "\n")
            // Drop the stamp rather than the list: the next read re-parses.
            cachedStamp = null
        }
    }

    fun all(): List<Score> =
        lock.withLock {
            if (!file.exists()) return@withLock emptyList()

            val stamp = file.lastModified() to file.length()
            if (stamp == cachedStamp) return@withLock cached

            cached = parse()
            cachedStamp = stamp
            cached
        }

    private fun parse(): List<Score> =
        file
            .readLines()
            .withIndex()
            .mapNotNull { (index, line) ->
                if (line.isBlank()) {
                    null
                } else {
                    runCatching { storeJson.decodeFromString<Score>(line) }
                        .onFailure {
                            logger.warn { "Skipping unreadable line ${index + 1} of ${file.path}: ${it.message}" }
                        }.getOrNull()
                }
            }
}
