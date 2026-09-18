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
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.rememberStrokeIcon

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
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    progressStore: LessonProgressStore? = null,
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
    )
}

@Composable
internal fun AcademyList(
    state: AcademyUiState,
    onOpenLesson: (Lesson) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    BittrCanvas(modifier = modifier, onBack = onBack) {
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.md),
            contentPadding = PaddingValues(
                start = AcademyLayout.contentPadding,
                end = AcademyLayout.contentPadding,
                top = AcademyLayout.contentPadding,
                bottom = BittrTokens.Spacing.section,
            ),
            modifier = Modifier.fillMaxWidth(),
        ) {
            item {
                Column {
                    AcademyHeading(AcademyCopy.TITLE)
                    Text(
                        text = AcademyCopy.HEADER,
                        style = AcademyType.intro,
                        color = BittrTheme.colors.onCanvas.copy(alpha = 0.8f),
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag(TestID.Academy.headerLabel),
                    )
                }
            }

            items(state.sections, key = { it.order }) { section ->
                LevelCard(section = section, onOpenLesson = onOpenLesson)
            }
        }
    }
}

/**
 * One level: its header over a three-column grid of lesson tiles, as iOS's
 * `LevelTableViewCell` holds a `UICollectionView` of `LessonCollectionViewCell`s.
 *
 * The grid is rows of three in plain [Row]s, not a `LazyVerticalGrid`: the card is
 * already an item of the screen's `LazyColumn`, and a lazy grid cannot be measured
 * inside another lazy list in the same direction. Six lessons a level is not a list
 * that needs recycling.
 *
 * Not `BittrCard`: the review puts the grid 16 dp inside the card on every side, where
 * `BittrCard`'s gutter is 22 × 28 and leaves the tiles too small for three across.
 */
@Composable
private fun LevelCard(section: LevelSection, onOpenLesson: (Lesson) -> Unit) {
    val colors = BittrTheme.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.cardWash, BittrCanvasShapes.card)
            .padding(LevelCardPadding),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Image(
                imageVector = rememberStrokeIcon(BittrIconPaths.ACADEMY, colors.onCanvas),
                contentDescription = null,
                modifier = Modifier.size(20.dp),
            )
            Text(
                text = section.title,
                style = AcademyType.levelTitle,
                color = colors.onCanvas,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = section.countLabel,
                style = AcademyType.levelCount,
                color = colors.onCanvas.copy(alpha = 0.6f),
            )
        }
        CanvasSpacer(16.dp)

        Column(verticalArrangement = Arrangement.spacedBy(TileGap)) {
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
 * One lesson tile: the artwork, square, with the title under it.
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
            .clip(TileShape)
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
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
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
            if (completed) {
                CompletedBadge(
                    Modifier
                        .align(Alignment.BottomStart)
                        .padding(4.dp),
                )
            }
        }
        CanvasSpacer(8.dp)
        Text(
            text = cell.lesson.title,
            style = AcademyType.tileTitle,
            color = BittrTheme.colors.onCanvas,
            textAlign = TextAlign.Center,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/**
 * The completed tick on a tile. Not `BittrCheckBadge`, which is the ink disc of the
 * success screens: on the artwork the review wants green, as iOS's `iconCheck` is
 * (`LessonCollectionViewCell.swift:31`), and the ink disc would read as a control.
 * The green is fixed in both schemes because it sits on the artwork, not the canvas.
 */
@Composable
private fun CompletedBadge(modifier: Modifier = Modifier) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(22.dp)
            .background(CompletedGreen, CircleShape),
    ) {
        Image(
            imageVector = rememberStrokeIcon(BittrIconPaths.CHECK, Color.White, strokeWidth = 2.6f),
            contentDescription = "Completed",
            modifier = Modifier.size(12.dp),
        )
    }
}

private const val TILE_COLUMNS = 3
private val TileGap = 12.dp
private val LevelCardPadding = 16.dp
private val TileShape = RoundedCornerShape(14.dp)
private val CompletedGreen = Color(0xFF1F8A4C)

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
