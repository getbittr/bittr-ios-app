package com.bittr.android.feature.academy

import android.content.Context
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull

/** One text block of an article — an entry of iOS's `Article.text`. [html] is the block's markup. */
data class ArticleBlock(val html: String, val order: Int)

/** iOS's `Article`: the bundled articles the signup pages link to. */
data class Article(
    val id: String,
    val title: String,
    val category: String,
    val blocks: List<ArticleBlock>,
) {
    /** `ArticleViewController.viewDidLoad`: only an FAQ's blocks are sorted by their order. */
    val displayBlocks: List<ArticleBlock>
        get() = if (category == "faq") blocks.sortedBy { it.order } else blocks
}

/**
 * The bundled articles — iOS's `BittrArticles.json`, copied verbatim to `res/raw/bittr_articles.json`
 * — parsed once, as `getLocalArticle` caches them on the core view controller.
 */
object BittrArticles {

    /** Transfer1's article card. */
    const val SUPPORTED_COUNTRIES = "supported-countries"

    /** Signup7's article card. */
    const val WHAT_IS_BITTR = "what-is-bittr"

    @Volatile
    private var cached: Map<String, Article>? = null

    fun article(context: Context, slug: String): Article? = all(context)[slug]

    fun all(context: Context): Map<String, Article> = cached ?: synchronized(this) {
        cached ?: runCatching {
            val json = context.applicationContext.resources.openRawResource(R.raw.bittr_articles)
                .bufferedReader().use { it.readText() }
            parse(json)
        }.getOrDefault(emptyMap()).also { cached = it }
    }

    /** `parseArticles(articles:)`. */
    fun parse(json: String): Map<String, Article> {
        val root = runCatching { Json.parseToJsonElement(json) as? JsonObject }.getOrNull() ?: return emptyMap()
        val articles = root["articles"] as? JsonObject ?: return emptyMap()
        return articles.mapNotNull { (id, value) ->
            val data = value as? JsonObject ?: return@mapNotNull null
            id to Article(
                id = id,
                title = data.string("title").orEmpty(),
                category = data.string("category").orEmpty(),
                blocks = (data["text"] as? JsonArray).orEmpty().mapNotNull { item ->
                    val block = item as? JsonObject ?: return@mapNotNull null
                    ArticleBlock(
                        html = block.string("text").orEmpty(),
                        order = (block["order"] as? JsonPrimitive)?.intOrNull ?: 0,
                    )
                },
            )
        }.toMap()
    }

    private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.contentOrNull

    /** The header image iOS takes from the asset catalogue by slug; null when none is bundled. */
    fun imageRes(slug: String): Int? = when (slug) {
        SUPPORTED_COUNTRIES -> R.drawable.article_supported_countries
        WHAT_IS_BITTR -> R.drawable.article_what_is_bittr
        else -> null
    }
}

/** A styled run of an article paragraph. */
enum class ArticleStyle { Title, Subtitle, Intro, Header, Normal }

data class ArticleRun(val style: ArticleStyle, val text: String)

/**
 * `OneArticleTableViewCell.setText`: iOS drops `<strong>`, turns the escaped `<title>`, `<subtitle>`,
 * `<intro>`, `<header>` and `<normal>` markers into font spans, and lets HTML lay out `<p>` and `<br>`.
 * Here each paragraph becomes a list of runs, a marker starting a new run in its style.
 */
object ArticleMarkup {

    private val PARAGRAPH = Regex("<p>(.*?)</p>", RegexOption.DOT_MATCHES_ALL)
    private val MARKER = Regex("&lt;(title|subtitle|intro|header|normal)&gt;")
    private val TAG = Regex("<[^>]+>")

    fun paragraphs(html: String): List<List<ArticleRun>> {
        val bodies = PARAGRAPH.findAll(html).map { it.groupValues[1] }.toList().ifEmpty { listOf(html) }
        return bodies.map { body ->
            val runs = mutableListOf<ArticleRun>()
            var style = ArticleStyle.Normal
            var cursor = 0
            MARKER.findAll(body).forEach { match ->
                addRun(runs, style, body.substring(cursor, match.range.first))
                style = ArticleStyle.valueOf(match.groupValues[1].replaceFirstChar { it.uppercase() })
                cursor = match.range.last + 1
            }
            addRun(runs, style, body.substring(cursor))
            runs
        }.filter { runs -> runs.any { it.text.isNotBlank() } }
    }

    private fun addRun(runs: MutableList<ArticleRun>, style: ArticleStyle, fragment: String) {
        val text = decode(fragment.replace(Regex("<br\\s*/?>"), "\n").replace(TAG, ""))
        if (text.isNotEmpty()) runs += ArticleRun(style, text)
    }

    private fun decode(text: String): String = text
        .replace("&nbsp;", " ")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&amp;", "&")
}
