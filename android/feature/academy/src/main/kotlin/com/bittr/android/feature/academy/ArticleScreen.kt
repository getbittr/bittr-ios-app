package com.bittr.android.feature.academy

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.shadow
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
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens

/**
 * `ArticleViewController`: the article's image, then its text blocks, with `article.downButton` and
 * `article.tableView`.
 */
@Composable
fun ArticleScreen(slug: String, onDown: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val article = remember(slug) { BittrArticles.article(context, slug) }
    BittrCanvas(modifier = modifier.dismissOnPullDown(onDown), appBar = false) {
        BittrModalHeader(
            title = "",
            onDown = onDown,
            downTestTag = TestID.Article.downButton,
        )
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.md),
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .testTag(TestID.Article.tableView),
        ) {
            BittrArticles.imageRes(slug)?.let { image ->
                item {
                    Image(
                        painter = painterResource(image),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .fillMaxWidth()
                            .aspectRatio(16f / 9f),
                    )
                }
            }
            items(article?.displayBlocks.orEmpty()) { block ->
                Column(
                    verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
                    modifier = Modifier.padding(horizontal = 20.dp),
                ) {
                    ArticleMarkup.paragraphs(block.html).forEach { runs ->
                        Text(text = styled(runs), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.fillMaxWidth())
                    }
                }
            }
        }
    }
}

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
    // The proposal's article chip (review S6): a cream 54 dp plate with the artwork as a
    // flush 84 dp strip on its left, clipped by the plate, and the title centred in the rest.
    // It was a bare rounded thumbnail with the title floating on the canvas beside it.
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .height(54.dp)
            .shadow(
                elevation = 4.dp,
                shape = ArticleChipShape,
                ambientColor = ArticleChipShadow,
                spotColor = ArticleChipShadow,
            )
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
                    .width(84.dp)
                    .fillMaxHeight(),
            )
        }
        Text(
            text = article.title,
            style = MaterialTheme.typography.titleMedium.copy(fontSize = 15.5.sp, lineHeight = 20.sp),
            color = colors.onTonalFill,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = BittrTokens.Spacing.sm),
        )
    }
}

private val ArticleChipShape = RoundedCornerShape(14.dp)

/** The proposal's `rgba(120, 80, 0, 0.12)` — a warm shadow, not Material's grey one. */
private val ArticleChipShadow = Color(red = 120, green = 80, blue = 0, alpha = 31)

/** The `<title>` … `<normal>` spans of `OneArticleTableViewCell.setText`, at iOS's sizes, in the body face. */
private fun styled(runs: List<ArticleRun>): AnnotatedString = buildAnnotatedString {
    runs.forEach { run ->
        val span = when (run.style) {
            ArticleStyle.Title -> SpanStyle(fontSize = 26.sp, fontWeight = FontWeight.Bold)
            ArticleStyle.Subtitle -> SpanStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold)
            ArticleStyle.Intro -> SpanStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold)
            ArticleStyle.Header -> SpanStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold)
            ArticleStyle.Normal -> SpanStyle(fontSize = 18.sp, fontWeight = FontWeight.Normal)
        }
        withStyle(span.copy(letterSpacing = 0.em)) { append(run.text) }
    }
}
