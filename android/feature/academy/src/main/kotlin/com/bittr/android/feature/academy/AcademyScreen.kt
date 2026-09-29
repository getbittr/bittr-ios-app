package com.bittr.android.feature.academy

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.AppBarContentInset
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.IosCardShape
import com.bittr.android.core.designsystem.iosShadow

/**
 * The Academy — the lesson list and, over it, the open lesson.
 *
 * **One destination, not two.** On iOS `OneLessonViewController` is presented
 * modally over `AcademyViewController` and dismisses itself on Complete
 * (`OneLessonViewController.swift:104`), and `academy.yaml` walks straight back onto
 * `academy.headerLabel` afterwards without a navigation step. Modelling that as a
 * second route would mean routing a `Lesson` — 22 of them, each with its pages —
 * through a navigation argument to reach a screen the user never deep-links into.
 * The open lesson is state, so it is held as state.
 *
 * @param progressStore injected so a preview and the unit tests can supply a wallet
 *   part-way through the Academy. In the app it is the SharedPreferences one.
 */
@Composable
fun AcademyScreen(
    // Null where Academy is a page beside Wallet under the menu bar, as on iOS, with no back arrow.
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    progressStore: LessonProgressStore? = null,
    /** Room left at the end of the list for a menu bar drawn over it by the host. */
    contentBottomPadding: Dp = 0.dp,
) {
    val context = LocalContext.current
    val store = remember(progressStore) {
        progressStore ?: SharedPreferencesLessonProgressStore(context)
    }

    var state by remember { mutableStateOf(AcademyUiState(completedLessonIds = store.completedLessonIds())) }
    var openLesson by remember { mutableStateOf<Lesson?>(null) }

    val lesson = openLesson
    if (lesson != null) {
        OneLessonScreen(
            lesson = lesson,
            onCompleted = {
                store.markCompleted(lesson.id)
                state = state.completing(lesson.id)
                openLesson = null
            },
            onClose = { openLesson = null },
            modifier = modifier,
        )
        return
    }

    AcademyList(
        state = state,
        onOpenLesson = { openLesson = it },
        onBack = onBack,
        modifier = modifier,
        contentBottomPadding = contentBottomPadding,
    )
}

@Composable
internal fun AcademyList(
    state: AcademyUiState,
    onOpenLesson: (Lesson) -> Unit,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    contentBottomPadding: Dp = 0.dp,
) {
    // `AcademyViewController`, as its scene is: no title, the intro 30 below the top bar in Gilroy
    // Regular 16, 30 from the sides with 30 under it, then the level cards 13.5 apart — iOS's cell
    // is the card's height plus 13.5 (`cellHeight = collection + 100` against a card of
    // collection + 86.5).
    //
    // The list runs up under the translucent top bar, as iOS's table does (`contentInset.top`
    // under CoreViewController's top bar), and starts below it.
    val underBar = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + AppBarContentInset
    BittrCanvas(modifier = modifier, onBack = onBack, scrollsUnderAppBar = true) {
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(13.5.dp),
            contentPadding = PaddingValues(
                top = underBar + 30.dp,
                bottom = BittrTokens.Spacing.section + contentBottomPadding,
            ),
            modifier = Modifier.fillMaxWidth(),
        ) {
            item {
                Text(
                    text = AcademyCopy.HEADER,
                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp, lineHeight = 19.sp),
                    color = BittrTheme.colors.onCanvas,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 30.dp, end = 30.dp, bottom = 30.dp - 13.5.dp)
                        .testTag(TestID.Academy.headerLabel),
                )
            }

            items(state.sections, key = { it.order }) { section ->
                LevelCard(section = section, onOpenLesson = onOpenLesson)
            }
        }
    }
}

/**
 * One level — `LevelTableViewCell`: `cardView` 15 from the screen's sides, `yelloworblue2` with
 * 13 pt corners and `setShadow()`. The academy icon 20 in and 18.5 down, "level N" in Gilroy Bold
 * 18 10 after it and the count 20 from the end, both white (yellow in dark); the lessons 25 below
 * the icon, 20 from the card's sides and 25 above its bottom, three to a row, 5 apart across and
 * 20 down.
 *
 * The grid is rows of three in plain [Row]s, not a `LazyVerticalGrid`: the card is
 * already an item of the screen's `LazyColumn`, and a lazy grid cannot be measured
 * inside another lazy list in the same direction. Six lessons a level is not a list
 * that needs recycling.
 */
@Composable
private fun LevelCard(section: LevelSection, onOpenLesson: (Lesson) -> Unit) {
    val colors = BittrTheme.colors
    val titleStyle = MaterialTheme.typography.titleMedium.copy(fontSize = 18.sp, lineHeight = 18.sp)
    Column(
        modifier = Modifier
            .padding(horizontal = 15.dp)
            .fillMaxWidth()
            .iosShadow(IosCardShape)
            .background(colors.levelCard, IosCardShape)
            .padding(start = 20.dp, end = 20.dp, top = 18.5.dp, bottom = 25.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Image(
                painter = painterResource(
                    if (BittrTheme.isDark) R.drawable.academy_level_icon_yellow else R.drawable.academy_level_icon,
                ),
                contentDescription = null,
                modifier = Modifier.size(18.dp),
            )
            Text(
                text = section.title,
                style = titleStyle,
                color = colors.homeCardTitle,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 10.dp)
                    .offset(y = 1.dp),
            )
            Text(
                text = section.countLabel,
                style = titleStyle,
                color = colors.homeCardTitle,
                modifier = Modifier.offset(y = 1.dp),
            )
        }
        CanvasSpacer(25.dp)

        Column(verticalArrangement = Arrangement.spacedBy(TileRowGap)) {
            section.cells.chunked(TILE_COLUMNS).forEach { row ->
                Row(
                    horizontalArrangement = Arrangement.spacedBy(TileGap),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    row.forEach { cell ->
                        LessonTile(cell = cell, onOpenLesson = onOpenLesson, modifier = Modifier.weight(1f))
                    }
                    // A short last row keeps its tiles at a third of the width rather than
                    // stretching to fill it.
                    repeat(TILE_COLUMNS - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

/**
 * One lesson — `LessonCollectionViewCell`: the artwork 60 pt square with 8 pt corners, centred, the
 * completed tick 18 pt across its bottom edge, and the title 13 below it in Gilroy Bold 15, centred.
 *
 * The three states are iOS's, including the one that matters to the suite: only
 * [LessonAvailability.NEXT] carries `academy.nextLessonButton`. A completed lesson
 * is still tappable and still has no identifier, so a flow cannot accidentally
 * re-open something it has already finished by matching the same selector.
 *
 * Locked tiles are blurred rather than hidden, as on iOS, and are **not clickable** —
 * `lessonButton.alpha = 0` is what makes them inert there
 * (`LevelTableViewCell.swift:172`), which is a real difference from merely looking
 * dimmed. iOS's `addBlur` covers the whole cell, so the blur takes the artwork as
 * well as the title.
 */
@Composable
private fun LessonTile(cell: LessonCell, onOpenLesson: (Lesson) -> Unit, modifier: Modifier = Modifier) {
    val locked = cell.availability == LessonAvailability.LOCKED
    val completed = cell.availability == LessonAvailability.COMPLETED
    val artwork = LessonArtwork.forImage(cell.lesson.image)

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .then(
                if (locked) {
                    Modifier
                } else {
                    Modifier.clickable(role = Role.Button) { onOpenLesson(cell.lesson) }
                },
            )
            .then(
                if (cell.availability == LessonAvailability.NEXT) {
                    Modifier.testTag(TestID.Academy.nextLessonButton)
                } else {
                    Modifier
                },
            )
            .then(if (locked) Modifier.blur(6.dp).alpha(0.6f) else Modifier),
    ) {
        Box(contentAlignment = Alignment.BottomCenter) {
            Box(
                modifier = Modifier
                    .size(LessonImageSize)
                    .clip(TileShape)
                    .background(BittrTheme.colors.scrim1),
            ) {
                if (artwork != null) {
                    Image(
                        painter = painterResource(artwork),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
            if (completed) {
                // `iconCheck`, centred on the artwork's bottom edge and 7 below it.
                Image(
                    painter = painterResource(R.drawable.academy_check),
                    contentDescription = "Completed",
                    modifier = Modifier
                        .offset(y = 7.dp)
                        .size(18.dp),
                )
            }
        }
        CanvasSpacer(13.dp)
        Text(
            text = cell.lesson.title,
            style = MaterialTheme.typography.titleMedium.copy(fontSize = 15.sp, lineHeight = 17.sp),
            color = BittrTheme.colors.onCanvas,
            textAlign = TextAlign.Center,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

private const val TILE_COLUMNS = 3
/** The compositional layout's `interItemSpacing` and `interGroupSpacing`. */
private val TileGap = 5.dp
private val TileRowGap = 20.dp
private val LessonImageSize = 60.dp
private val TileShape = RoundedCornerShape(8.dp)

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun AcademyListPreview() {
    BittrTheme {
        AcademyList(
            state = AcademyUiState(completedLessonIds = setOf("whatisbitcoin")),
            onOpenLesson = {},
            onBack = {},
        )
    }
}
