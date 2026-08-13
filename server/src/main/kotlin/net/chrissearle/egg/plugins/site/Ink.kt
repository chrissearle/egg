package net.chrissearle.egg.plugins.site

/**
 * The palette, as CSS class names. These are the real BBC MODE 2 hardware
 * colours and are fixed — see CLAUDE.md, which forbids softening or retinting
 * them. Named for what the game uses them for rather than for the colour.
 */
enum class Ink(
    val css: String
) {
    /** Harry, eggs, the cage, the lift, the mother duck. */
    YELLOW("ink-yellow"),

    /** The hens. Also the game's own highlight for a key you press. */
    CYAN("ink-cyan"),

    /** Ladders, corn, the HUD labels. */
    MAGENTA("ink-magenta"),

    /** Platforms, and the high score entries in the game's own table. */
    GREEN("ink-green")
}
