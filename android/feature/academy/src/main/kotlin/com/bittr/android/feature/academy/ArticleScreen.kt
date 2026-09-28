package com.bittr.android.feature.academy

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.background
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.iosShadow
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.R as DesignR
import com.bittr.android.core.designsystem.BittrTokens

/**
 * `ArticleViewController`, which iOS presents as a page sheet — see `BittrSheet`, which the nav host
 * wraps this in. One scrolling list, as iOS's table is: the article's image full width and 280 pt
 * tall, with `downarrow32` over its top left (`article.downButton`), then the text blocks. No app
 * bar and no piggy; white in light mode, blue1 in dark. Decision 56.
 *
 * The spacing is iOS's HTML rendering of the blocks, measured on a screenshot: each block is a cell
 * with its text 20 in from the sides and 20 below the cell above; lines are 1.2 × their size;
 * paragraphs are 12 apart; an empty `<p>&nbsp;</p>` is a line about 13.8 tall (UIKit's default
 * 12 pt HTML font); and each block ends with another 12 and a trailing empty line.
 */
@Composable
fun ArticleScreen(slug: String, onDown: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val article = remember(slug) { BittrArticles.article(context, slug) }
    val colors = BittrTheme.colors
    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .background(colors.articleSurface)
            .dismissOnPullDown(onDown)
            .testTag(TestID.Article.tableView),
    ) {
        item {
            Box(Modifier.fillMaxWidth().height(280.dp)) {
                BittrArticles.imageRes(slug)?.let { image ->
                    Image(
                        painter = painterResource(image),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                // The 20 pt chevron 20 in and 15 down, inside a 40 pt button around it.
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .padding(start = 10.dp, top = 5.dp)
                        .size(40.dp)
                        .clickable(role = Role.Button, onClick = onDown)
                        .testTag(TestID.Article.downButton),
                ) {
                    Image(
                        painter = painterResource(DesignR.drawable.bittr_down_chevron),
                        contentDescription = "Close",
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
        }
        items(article?.displayBlocks.orEmpty()) { block ->
            Column(modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 20.dp)) {
                ArticleMarkup.paragraphs(block.html, keepBlank = true).forEachIndexed { index, runs ->
                    if (index > 0) Spacer(Modifier.height(ParagraphGap))
                    if (runs.isEmpty()) {
                        Spacer(Modifier.height(EmptyLine))
                    } else {
                        val size = runs.maxOf { it.style.fontSize.value }
                        Text(
                            text = styled(runs),
                            style = MaterialTheme.typography.bodyLarge.copy(lineHeight = (size * 1.2f).sp),
                            color = colors.onArticleSurface,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
                Spacer(Modifier.height(ParagraphGap + EmptyLine))
            }
        }
    }
}

/** iOS's gap between two `<p>`s in one block. */
private val ParagraphGap = 12.dp

/** An empty `<p>` on iOS: one line of UIKit's default 12 pt HTML font. */
private val EmptyLine = 13.8.dp

/**
 * A signup page's article card — the image and title iOS's `setSignupArticle` fills in, tapping
 * through to the article. Nothing is drawn when the article isn't bundled, as iOS leaves the card
 * spinning.
 */
@Composable
fun ArticleCard(slug: String, onOpen: (String) -> Unit, modifier: Modifier = Modifier, testTag: String? = null) {
    val context = LocalContext.current
    val article = remember(slug) { BittrArticles.article(context, slug) } ?: return
    val colors = BittrTheme.colors
    // iOS's article card (`cardView` on Signup1, and the same on every signup screen that shows
    // one): a cream plate 45 pt high with 8 pt corners and `setShadow()`, the artwork 45 pt wide
    // flush on its left, the title in Gilroy Bold 15 60 pt from the plate's edge and 20 pt from
    // its right, 7 above and 3 below. The plate is as wide as that content, capped by the slot
    // it is given, and centred in it.
    Box(contentAlignment = Alignment.Center, modifier = modifier.fillMaxWidth()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .height(45.dp)
                .iosShadow(ArticleChipShape)
                .clip(ArticleChipShape)
                .background(colors.tonalFill)
                .clickable { onOpen(slug) }
                .then(if (testTag != null) Modifier.testTag(testTag) else Modifier),
        ) {
            BittrArticles.imageRes(slug)?.let { image ->
                Image(
                    painter = painterResource(image),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .width(45.dp)
                        .fillMaxHeight(),
                )
            }
            Text(
                text = article.title,
                style = MaterialTheme.typography.titleMedium.copy(fontSize = 15.sp, lineHeight = 17.sp),
                color = colors.onTonalFill,
                textAlign = TextAlign.Start,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(start = 15.dp, end = 20.dp, top = 7.dp, bottom = 3.dp),
            )
        }
    }
}

private val ArticleChipShape = RoundedCornerShape(8.dp)

/** The `<title>` … `<normal>` spans of `OneArticleTableViewCell.setText`, at iOS's sizes, in the body face. */
private fun styled(runs: List<ArticleRun>): AnnotatedString = buildAnnotatedString {
    runs.forEach { run ->
        val weight = if (run.style == ArticleStyle.Normal) FontWeight.Normal else FontWeight.Bold
        withStyle(SpanStyle(fontSize = run.style.fontSize, fontWeight = weight, letterSpacing = 0.em)) { append(run.text) }
    }
}

/** `OneArticleTableViewCell.setText`'s sizes. */
private val ArticleStyle.fontSize
    get() = when (this) {
        ArticleStyle.Title -> 26.sp
        ArticleStyle.Subtitle -> 12.sp
        ArticleStyle.Intro -> 18.sp
        ArticleStyle.Header -> 20.sp
        ArticleStyle.Normal -> 18.sp
    }
