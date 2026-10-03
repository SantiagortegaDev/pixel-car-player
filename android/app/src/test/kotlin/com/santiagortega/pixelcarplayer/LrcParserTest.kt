package com.santiagortega.pixelcarplayer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LrcParserTest {

    @Test
    fun parsesBasicLines() {
        val lines = LrcParser.parse("[00:01.50]Hola\n[00:03.25] Mundo \n")
        assertEquals(listOf(LyricLine(1500, "Hola"), LyricLine(3250, "Mundo")), lines)
    }

    @Test
    fun handlesMultipleTagsAndSorts() {
        val lines = LrcParser.parse("[00:10.00][00:02.00]Coro\n[00:05.00]Verso")
        assertEquals(
            listOf(LyricLine(2000, "Coro"), LyricLine(5000, "Verso"), LyricLine(10000, "Coro")),
            lines,
        )
    }

    @Test
    fun handlesFractionsMetadataAndOffset() {
        val lrc = """
            [ar:Artista]
            [ti:Título]
            [offset:+500]
            [01:02.3]a
            [01:02.345]b
            [01:02]c
            [00:00.00]
            texto sin tiempo
        """.trimIndent()
        val lines = LrcParser.parse(lrc)
        assertEquals(
            listOf(
                LyricLine(0, ""),
                LyricLine(61800, "a"),
                LyricLine(61845, "b"),
                LyricLine(61500, "c"),
            ).sortedBy { it.ms },
            lines,
        )
    }

    @Test
    fun plainLyricsHaveZeroTimestamps() {
        val lines = LrcParser.plain("uno\r\ndos\n")
        assertEquals(listOf(LyricLine(0, "uno"), LyricLine(0, "dos")), lines)
        assertTrue(LrcParser.parse("sin etiquetas").isEmpty())
    }

    @Test
    fun cleansTitles() {
        assertEquals("Song", LyricsFetcher.cleanTitle("Song - Remastered 2011"))
        assertEquals("Song", LyricsFetcher.cleanTitle("Song (feat. Someone)"))
    }
}
