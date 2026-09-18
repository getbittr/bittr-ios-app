package com.bittr.android.feature.academy

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.bittrMarkup
import com.bittr.android.core.designsystem.rememberFillIcon
import com.bittr.android.core.designsystem.rememberStrokeIcon

/**
 * One lesson, a page at a time.
 *
 * Ported from `OneLessonViewController` plus `Button.swift`. Three behaviours carry
 * across because the Maestro flow depends on each of them:
 *
 * 1. **The page is hidden while it loads, and the buttons do not exist yet.**
 *    `loadPage` clears the content, sets `centerView.alpha = 0` and starts
 *    `centerSpinner`; `addButton` runs only after the last component is laid out. So
 *    `academy.nextPageButton` is genuinely absent mid-load rather than present and
 *    covered — which is what makes `academy.yaml`'s "wait for the spinner, then tap"
 *    ordering safe rather than lucky.
 * 2. **Back exists from page 2 on.** `firstPage` collapses the back stack to zero
 *    width (`Button.swift:45`), so page 1 has no `academy.backPageButton` and the
 *    flow asserts its absence after paging back.
 * 3. **Next and Complete are the same button.** One control, relabelled on the last
 *    page, carrying `academy.completeButton` there and `academy.nextPageButton`
 *    everywhere else (`Button.swift:151`).
 */
@Composable
internal fun OneLessonScreen(
    lesson: Lesson,
    onCompleted: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    imageLoader: LessonImageLoader? = null,
) {
    val loader = remember(imageLoader) { imageLoader ?: HttpLessonImageLoader() }
    var state by remember(lesson.id) { mutableStateOf(LessonUiState(lesson)) }
    var images by remember(lesson.id) { mutableStateOf<Map<String, ImageBitmap?>>(emptyMap()) }

    // One effect per page, keyed on the page index — the Android equivalent of
    // `loadPage` being called from `viewDidLoad`, `previousPage` and `nextPage`
    // alike. Images are fetched in order, as `addNextComponent` does, and a failure
    // resolves to a null entry rather than propagating: the page still finishes
    // loading and the spinner still stops.
    LaunchedEffect(lesson.id, state.pageIndex) {
        val urls = state.page.components.filterIsInstance<Component.Image>().map { it.url }
        for (url in urls) {
            images = images + (url to loader.load(url))
        }
        state = state.pageLoaded()
    }

    BittrCanvas(modifier = modifier, onBack = onClose) {
        AcademyHeading(
            text = lesson.title,
            modifier = Modifier.padding(
                start = AcademyLayout.contentPadding,
                end = AcademyLayout.contentPadding,
                top = AcademyLayout.contentPadding,
            ),
        )

        BoxWithConstraints(modifier = Modifier.weight(1f).fillMaxWidth()) {
            if (state.isLoadingPage) {
                CircularProgressIndicator(
                    color = BittrTheme.colors.onCanvas,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .testTag(TestID.Academy.lessonSpinner),
                )
            } else {
                // Centred in the space between the heading and the buttons, and still
                // scrollable when a page outgrows it: the column is at least as tall as
                // the viewport, so the centring has room to work, and grows past it
                // rather than clipping.
                Column(
                    verticalArrangement = Arrangement.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .heightIn(min = maxHeight)
                        .padding(horizontal = AcademyLayout.contentPadding),
                ) {
                    LessonCard(components = state.page.components, images = images)
                }
            }
        }

        if (state.showsButtons) {
            CanvasSpacer(BittrTokens.Spacing.md)
            LessonButtons(
                state = state,
                onBack = { state = state.previousPage() },
                onNext = { state = state.nextPage() },
                onComplete = onCompleted,
            )
        }
        CanvasSpacer(AcademyLayout.contentPadding)
    }
}

/**
 * A page's components on the review's white card.
 *
 * `chartSurface` rather than a white literal: it is the designsystem's fixed white
 * with ink on it in both schemes, and ink-on-white is the only pairing that reads on
 * either canvas — the reasoning is on `BittrColors.chartSurface`. iOS draws the page's
 * text straight on the canvas and only its images on white cards (`Image.swift:17`);
 * the review moves the whole page onto one card.
 */
@Composable
private fun LessonCard(components: List<Component>, images: Map<String, ImageBitmap?>) {
    val colors = BittrTheme.colors
    Column(
        verticalArrangement = Arrangement.spacedBy(LessonParagraphGap),
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.chartSurface, LessonCardShape)
            .padding(LessonCardPadding),
    ) {
        components.forEach { component ->
            when (component) {
                is Component.Text -> Text(
                    text = bittrMarkup(component.text),
                    style = AcademyType.lessonBody,
                    color = colors.onChartSurface,
                    textAlign = TextAlign.Start,
                    modifier = Modifier.fillMaxWidth(),
                )

                is Component.Image -> LessonImage(images[component.url])
            }
        }
    }
}

/**
 * A downloaded image, or the gap iOS leaves when the download failed.
 *
 * `addImage` gives the empty card a fixed 30pt height and carries on
 * (`Image.swift:72-78`); the same 30 dp here is what keeps a dead URL from reading
 * as a missing component.
 */
@Composable
private fun LessonImage(bitmap: ImageBitmap?) {
    if (bitmap == null) {
        Box(Modifier.fillMaxWidth().height(30.dp))
        return
    }
    Image(
        bitmap = bitmap,
        contentDescription = null,
        contentScale = ContentScale.FillWidth,
        modifier = Modifier
            .fillMaxWidth()
            .clip(BittrCanvasShapes.wordRow),
    )
}

/**
 * Next (or Complete) as a content-width ink pill, with Back beside it from page 2 on;
 * the pair is centred. Back is a rounded square rather than a circle because iOS draws
 * it as one (`Button.swift:54-56`) and the review kept that shape at 56 dp.
 */
@Composable
private fun LessonButtons(
    state: LessonUiState,
    onBack: () -> Unit,
    onNext: () -> Unit,
    onComplete: () -> Unit,
) {
    val colors = BittrTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = AcademyLayout.contentPadding),
    ) {
        if (!state.isFirstPage) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(LessonButtonHeight)
                    .clip(BittrCanvasShapes.field)
                    .background(colors.actionFill)
                    .clickable(role = Role.Button, onClick = onBack)
                    .testTag(TestID.Academy.backPageButton),
            ) {
                Image(
                    imageVector = rememberFillIcon(BittrIconPaths.BACK, colors.onActionFill),
                    contentDescription = "Back",
                    modifier = Modifier.size(20.dp),
                )
            }
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
            modifier = Modifier
                .height(LessonButtonHeight)
                .widthIn(min = 160.dp)
                .clip(BittrCanvasShapes.pill)
                .background(colors.actionFill)
                .clickable(role = Role.Button) {
                    if (state.isLastPage) onComplete() else onNext()
                }
                .testTag(
                    if (state.isLastPage) {
                        TestID.Academy.completeButton
                    } else {
                        TestID.Academy.nextPageButton
                    },
                )
                .padding(horizontal = 28.dp),
        ) {
            Text(
                text = if (state.isLastPage) AcademyCopy.COMPLETE else AcademyCopy.NEXT,
                style = MaterialTheme.typography.labelLarge,
                color = colors.onActionFill,
            )
            // The forward chevron is hidden on the last page, where the label reads
            // "Complete" and there is nothing to go forward to (`Button.swift:141`).
            if (!state.isLastPage) {
                Image(
                    imageVector = rememberStrokeIcon(BittrIconPaths.ARROW_FORWARD, colors.onActionFill),
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
            }
        }
    }
}

private val LessonButtonHeight = 56.dp
private val LessonCardShape = RoundedCornerShape(20.dp)
private val LessonCardPadding = 20.dp
private val LessonParagraphGap = 16.dp

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun OneLessonScreenPreview() {
    BittrTheme {
        OneLessonScreen(
            lesson = AcademyContent.levels.first().lessons.first(),
            onCompleted = {},
            onClose = {},
            imageLoader = object : LessonImageLoader {
                override suspend fun load(url: String): ImageBitmap? = null
            },
        )
    }
}
