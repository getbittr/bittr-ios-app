package com.bittr.android.feature.academy

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ArticlesTest {

    /** The bundled copy of iOS's `BittrArticles.json`, read from the module's resources. */
    private val articles = BittrArticles.parse(File("src/main/res/raw/bittr_articles.json").readText())

    @Test
    fun `the signup cards' articles are bundled, with titles and images`() {
        listOf(BittrArticles.WHAT_IS_BITTR, BittrArticles.SUPPORTED_COUNTRIES).forEach { slug ->
            val article = articles[slug]
            assertNotNull(slug, article)
            assertTrue(slug, article!!.title.isNotBlank())
            assertTrue(slug, article.blocks.isNotEmpty())
            assertNotNull(slug, BittrArticles.imageRes(slug))
        }
        assertEquals("What countries are supported?", articles.getValue(BittrArticles.SUPPORTED_COUNTRIES).title)
    }

    @Test
    fun `markers become styled runs, strong is dropped, br and entities are decoded`() {
        val html = "<p><strong>&lt;title&gt;Bittr &amp; you</strong></p><p>&lt;subtitle&gt;By Ruben<br><br>&nbsp;</p>" +
            "<p>&nbsp;</p><p>&lt;intro&gt;Hello \"there\"</p><p>&lt;header&gt;Head&lt;normal&gt;Body</p>"
        val paragraphs = ArticleMarkup.paragraphs(html)
        assertEquals(
            listOf(
                listOf(ArticleRun(ArticleStyle.Title, "Bittr & you")),
                listOf(ArticleRun(ArticleStyle.Subtitle, "By Ruben\n\n ")),
                listOf(ArticleRun(ArticleStyle.Intro, "Hello \"there\"")),
                listOf(ArticleRun(ArticleStyle.Header, "Head"), ArticleRun(ArticleStyle.Normal, "Body")),
            ),
            paragraphs,
        )
    }

    @Test
    fun `only an faq's blocks are sorted by order`() {
        val blocks = listOf(ArticleBlock("b", 2), ArticleBlock("a", 1))
        assertEquals(listOf("a", "b"), Article("x", "t", "faq", blocks).displayBlocks.map { it.html })
        assertEquals(listOf("b", "a"), Article("x", "t", "General", blocks).displayBlocks.map { it.html })
    }
}
