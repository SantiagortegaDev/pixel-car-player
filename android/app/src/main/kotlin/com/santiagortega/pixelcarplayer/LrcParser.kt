package com.santiagortega.pixelcarplayer

/** One lyric line: start time in ms and text. */
data class LyricLine(val ms: Long, val text: String)

/** Pure-Kotlin LRC parser (no Android deps so it is unit-testable on the JVM). */
object LrcParser {
    // [mm:ss], [mm:ss.x], [mm:ss.xx], [mm:ss.xxx], [mm:ss:xx]
    private val timeTag = Regex("""\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?]""")
    private val offsetTag = Regex("""\[offset:\s*([+-]?\d+)\s*]""", RegexOption.IGNORE_CASE)

    fun parse(lrc: String): List<LyricLine> {
        val offset = offsetTag.find(lrc)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
        val out = ArrayList<LyricLine>()
        for (raw in lrc.lineSequence()) {
            val line = raw.trim()
            var pos = 0
            val times = ArrayList<Long>(1)
            while (true) {
                val m = timeTag.matchExactlyAt(line, pos) ?: break
                val min = m.groupValues[1].toLong()
                val sec = m.groupValues[2].toLong()
                val frac = m.groupValues[3]
                val fracMs = when (frac.length) {
                    0 -> 0L
                    1 -> frac.toLong() * 100
                    2 -> frac.toLong() * 10
                    else -> frac.toLong()
                }
                times += min * 60_000 + sec * 1000 + fracMs
                pos = m.range.last + 1
                // tolerate spaces between consecutive tags
                while (pos < line.length && line[pos] == ' ' && line.startsWith("[", pos + 1)) pos++
            }
            if (times.isEmpty()) continue // metadata tags ([ar:], [ti:], ...) or junk
            val text = line.substring(pos).trim()
            for (t in times) out += LyricLine((t - offset).coerceAtLeast(0), text)
        }
        out.sortBy { it.ms } // stable: keeps original order for equal timestamps
        return out
    }

    /** Plain (unsynced) lyrics: one line per text line, ms = 0. */
    fun plain(text: String): List<LyricLine> =
        text.lineSequence().map { LyricLine(0, it.trimEnd('\r')) }.toList()
            .dropLastWhile { it.text.isBlank() }

    private fun Regex.matchExactlyAt(input: String, index: Int): MatchResult? {
        if (index >= input.length) return null
        val m = find(input, index) ?: return null
        return if (m.range.first == index) m else null
    }
}
