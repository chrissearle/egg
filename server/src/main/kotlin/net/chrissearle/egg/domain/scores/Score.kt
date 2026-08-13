package net.chrissearle.egg.domain.scores

import kotlinx.serialization.Serializable

/**
 * The game's own name buffer is eight characters (HighScores.NAME_LENGTH), and
 * its font covers 0x20-0x7e, so those are the limits a real submission obeys.
 */
const val MAX_NAME_LENGTH = 8
const val FIRST_PRINTABLE = ' '
const val LAST_PRINTABLE = '~'

/**
 * Eight BCD digits is the game's score representation, and every award is a
 * multiple of ten, so this is the largest value it can legitimately hold.
 */
const val MAX_SCORE = 99_999_990

/**
 * Levels are 0-indexed internally and displayed one higher. Nobody is getting
 * near this, but it keeps a junk value out of the store.
 */
const val MAX_LEVEL = 256

/**
 * What a client sends. The timestamp is deliberately absent: the client has no
 * clock the leaderboard can trust, and the game does not record one at all.
 */
@Serializable
data class ScoreSubmission(
    val name: String,
    val score: Int,
    val level: Int
)

/**
 * What is stored, one per line of the JSONL file. `ts` is server-assigned.
 */
@Serializable
data class Score(
    val ts: String,
    val name: String,
    val score: Int,
    val level: Int
)

/**
 * The four windows the page shows, newest-relative first.
 */
@Serializable
data class Leaderboard(
    val last24h: List<Score>,
    val last7d: List<Score>,
    val last30d: List<Score>,
    val allTime: List<Score>
)
