package net.chrissearle.egg.plugins.site

import net.chrissearle.egg.domain.scores.Score
import java.util.Locale

/** Width of the score column, matching the game's eight BCD digits. */
private const val SCORE_WIDTH = 8

/** Width of the name column — HighScores.NAME_LENGTH. */
private const val NAME_WIDTH = 8

/**
 * One leaderboard row, laid out as the game's own table does it.
 *
 * `HighScores.row_text` writes a two-character rank, the score right-aligned in
 * its column, a space, then the name. Because the font is fixed pitch, padding
 * with spaces is what aligns the columns — the same reason the game builds one
 * run of characters rather than positioning three separate ones, which is what
 * made an early attempt at the in-game table overlap.
 *
 * Locale.ROOT because the padding is a layout measurement, not a number to be
 * presented: a locale that groups digits would push the columns out of line.
 */
fun scoreRow(
    rank: Int,
    entry: Score
): String =
    String.format(
        Locale.ROOT,
        "%2d %s %s",
        rank,
        entry.score.toString().padStart(SCORE_WIDTH),
        entry.name.padEnd(NAME_WIDTH)
    )
