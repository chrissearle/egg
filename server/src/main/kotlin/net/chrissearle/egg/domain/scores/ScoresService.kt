package net.chrissearle.egg.domain.scores

import arrow.core.raise.Raise
import arrow.core.raise.catch
import arrow.core.raise.context.ensure
import arrow.core.raise.context.raise
import arrow.core.raise.context.withError
import net.chrissearle.egg.plugins.api.ApiError
import net.chrissearle.egg.plugins.api.ScoreLevelOutOfRange
import net.chrissearle.egg.plugins.api.ScoreNameNotPrintable
import net.chrissearle.egg.plugins.api.ScoreNameRequired
import net.chrissearle.egg.plugins.api.ScoreNameTooLong
import net.chrissearle.egg.plugins.api.ScoreNotAMultipleOfTen
import net.chrissearle.egg.plugins.api.ScoreOutOfRange
import net.chrissearle.egg.plugins.api.ScoreStoreUnwritable
import kotlin.time.Clock
import kotlin.time.Duration.Companion.days
import kotlin.time.Instant

/**
 * How many entries each window shows. Ten, to match the game's own table.
 */
const val BOARD_SIZE = 10

private const val SCORE_STEP = 10

class ScoresService(
    private val store: ScoreStore,
    private val clock: Clock = Clock.System
) {
    /**
     * Validates and records a submission, stamping it with the server's clock.
     *
     * Rejects rather than sanitises: a bad submission is a client error, and
     * quietly trimming it would put a value in the store that nobody sent.
     *
     * The timestamp is the server's because the client has none worth trusting
     * — the game records no time at all, and a supplied one would be forgeable.
     */
    context(_: Raise<ApiError>)
    fun record(submission: ScoreSubmission): Score {
        val name = submission.name.trim()

        ensure(name.isNotEmpty()) { ScoreNameRequired }
        ensure(name.length <= MAX_NAME_LENGTH) { ScoreNameTooLong(name) }
        ensure(name.all { it in FIRST_PRINTABLE..LAST_PRINTABLE }) { ScoreNameNotPrintable(name) }
        ensure(submission.score in 0..MAX_SCORE) { ScoreOutOfRange(submission.score) }
        ensure(submission.score % SCORE_STEP == 0) { ScoreNotAMultipleOfTen(submission.score) }
        ensure(submission.level in 1..MAX_LEVEL) { ScoreLevelOutOfRange(submission.level) }

        val score =
            Score(
                ts = clock.now().toString(),
                name = name,
                score = submission.score,
                level = submission.level
            )

        withError(::ScoreStoreUnwritable) {
            catch({ store.append(score) }) { raise(it) }
        }

        return score
    }

    /**
     * The four windows, from a single read of the store.
     */
    fun leaderboard(): Leaderboard {
        val all = store.all()
        val now = clock.now()

        return Leaderboard(
            last24h = all.since(now - 1.days).top(),
            last7d = all.since(now - 7.days).top(),
            last30d = all.since(now - 30.days).top(),
            allTime = all.top()
        )
    }

    /**
     * An entry whose timestamp will not parse falls out of every dated window
     * but still counts for all time — the same "a bad edit costs one line, not
     * the board" rule the store itself follows.
     */
    private fun List<Score>.since(cutoff: Instant): List<Score> =
        filter { entry -> entry.instantOrNull()?.let { it >= cutoff } == true }

    private fun List<Score>.top(): List<Score> =
        sortedWith(compareByDescending<Score> { it.score }.thenBy { it.ts })
            .take(BOARD_SIZE)
}

private fun Score.instantOrNull(): Instant? = runCatching { Instant.parse(ts) }.getOrNull()

fun scoresService(store: ScoreStore) = ScoresService(store)
