package com.bittr.android.feature.academy

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrSheetHeader
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.IosCardShape
import com.bittr.android.core.designsystem.R as DesignR
import com.bittr.android.core.designsystem.bittrMarkup
import com.bittr.android.core.designsystem.iosShadow

/**
 * One lesson, a page at a time — the content of the page sheet the Academy opens it in, as iOS
 * presents `OneLessonViewController` over the Academy.
 *
 * Ported from `OneLessonViewController` plus `Label.swift`, `Image.swift` and `Button.swift`: the
 * page's paragraphs straight on the sheet, centred, and its images on white cards, the whole page
 * with its buttons centred vertically. Three behaviours carry
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

    val colors = BittrTheme.colors
    // `yelloworblue2`, under `addHeader`'s academy icon and the lesson's title.
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.levelCard)
            .navigationBarsPadding(),
    ) {
        BittrSheetHeader(
            icon = painterResource(R.drawable.academy_level_icon),
            title = lesson.title,
            onDown = onClose,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )

        // `centerView`, centred in what is left: the page's components one under the other and
        // the buttons under them, scrolling when a page is taller than the sheet.
        BoxWithConstraints(modifier = Modifier.weight(1f).fillMaxWidth()) {
            if (state.isLoadingPage) {
                CircularProgressIndicator(
                    color = colors.onCanvas,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .testTag(TestID.Academy.lessonSpinner),
                )
            } else {
                Column(
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .heightIn(min = maxHeight)
                        .padding(vertical = 30.dp),
                ) {
                    var previous: Component? = null
                    state.page.components.forEach { component ->
                        CanvasSpacer(gapBefore(component, previous))
                        when (component) {
                            is Component.Text -> Text(
                                text = bittrMarkup(component.text),
                                style = LessonText,
                                color = colors.onCanvas,
                                textAlign = TextAlign.Center,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 35.dp),
                            )

                            is Component.Image -> LessonImage(images[component.url])
                        }
                        previous = component
                    }
                    if (state.showsButtons) {
                        CanvasSpacer(if (previous is Component.Image) 40.dp else 20.dp + TrailingLine)
                        LessonButtons(
                            state = state,
                            onBack = { state = state.previousPage() },
                            onNext = { state = state.nextPage() },
                            onComplete = onCompleted,
                        )
                    }
                }
            }
        }
    }
}

/**
 * The gap above a component, as `addLabel` and `addImage` space them: none above the first, 8
 * between two paragraphs, 20 from a paragraph down to an image and 30 below an image. A paragraph
 * also carries [TrailingLine] under it.
 */
private fun gapBefore(component: Component, previous: Component?) = when {
    previous == null -> 0.dp
    previous is Component.Image -> 30.dp
    component is Component.Text -> 8.dp + TrailingLine
    else -> 20.dp + TrailingLine
}

/**
 * The empty line under every paragraph on iOS: `addLabel` wraps the text in `<center>`, a block
 * that ends in a line break, so each label is one line of its 18 pt at 1.2 taller than its text.
 */
private val TrailingLine = 21.6.dp

/** `addLabel`'s HTML: Gilroy Regular 18 at a line height of 1.2, bold where marked. */
private val LessonText: TextStyle
    @Composable get() = MaterialTheme.typography.bodyLarge.copy(fontSize = 18.sp, lineHeight = 21.6.sp)

/**
 * `addImage`: a white card 30 from the sides with 13 pt corners and `setShadow()`, the image
 * filling its width. A failed download leaves the card 30 tall and the page carries on, as iOS's
 * does.
 */
@Composable
private fun LessonImage(bitmap: ImageBitmap?) {
    Box(
        modifier = Modifier
            .padding(horizontal = 30.dp)
            .fillMaxWidth()
            .iosShadow(IosCardShape)
            .clip(IosCardShape)
            .background(Color.White),
    ) {
        if (bitmap == null) {
            Box(Modifier.fillMaxWidth().height(30.dp))
        } else {
            Image(
                bitmap = bitmap,
                contentDescription = null,
                contentScale = ContentScale.FillWidth,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

/**
 * `addButton`: 40 tall with 8 pt corners, as the app's other buttons are. Next (or Complete) sized
 * to its label — 17, the label in Gilroy Bold 14, 10, the 11 pt arrow, 17 — and from page 2 on the
 * square Back 7 before it; the pair centred.
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
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        if (!state.isFirstPage) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(LessonButtonHeight)
                    .clip(LessonButtonShape)
                    .background(colors.actionFill)
                    .clickable(role = Role.Button, onClick = onBack)
                    .testTag(TestID.Academy.backPageButton),
            ) {
                // `arrowleftwhite`: the forward arrow, turned round.
                Image(
                    painter = painterResource(DesignR.drawable.bittr_arrow_right),
                    contentDescription = "Back",
                    colorFilter = ColorFilter.tint(colors.onActionFill),
                    modifier = Modifier
                        .size(11.dp)
                        .rotate(180f),
                )
            }
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier
                .height(LessonButtonHeight)
                .clip(LessonButtonShape)
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
                .padding(horizontal = 17.dp),
        ) {
            Text(
                text = if (state.isLastPage) AcademyCopy.COMPLETE else AcademyCopy.NEXT,
                style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.sp, lineHeight = 14.sp),
                color = colors.onActionFill,
                // iOS centres the label 1 pt below the plate's centre.
                modifier = Modifier.offset(y = 1.dp),
            )
            // The forward arrow is hidden on the last page, where the label reads
            // "Complete" and there is nothing to go forward to (`Button.swift:141`).
            if (!state.isLastPage) {
                Image(
                    painter = painterResource(DesignR.drawable.bittr_arrow_right),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(colors.onActionFill),
                    modifier = Modifier.size(11.dp),
                )
            }
        }
    }
}

private val LessonButtonHeight = 40.dp
private val LessonButtonShape = RoundedCornerShape(8.dp)

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
