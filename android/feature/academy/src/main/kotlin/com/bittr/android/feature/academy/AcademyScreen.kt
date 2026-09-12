package com.bittr.android.feature.academy

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrBody
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrCheckBadge
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer

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
            contentPadding = androidx.compose.foundation.layout.PaddingValues(
                start = BittrTokens.Spacing.gutter,
                end = BittrTokens.Spacing.gutter,
                top = BittrTokens.Spacing.sm,
                bottom = BittrTokens.Spacing.section,
            ),
            modifier = Modifier.fillMaxWidth(),
        ) {
            item {
                Column {
                    Text(
                        text = AcademyCopy.TITLE,
                        style = MaterialTheme.typography.headlineSmall,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    CanvasSpacer(BittrTokens.Spacing.sm)
                    BittrBody(
                        text = AcademyCopy.HEADER,
                        textAlign = TextAlign.Start,
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

@Composable
private fun LevelCard(section: LevelSection, onOpenLesson: (Lesson) -> Unit) {
    BittrCard(horizontalAlignment = Alignment.Start) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(section.title, style = MaterialTheme.typography.titleMedium)
            Text(section.countLabel, style = MaterialTheme.typography.bodyMedium)
        }
        CanvasSpacer(BittrTokens.Spacing.md)

        section.cells.forEach { cell ->
            LessonRow(cell = cell, onOpenLesson = onOpenLesson)
            CanvasSpacer(BittrTokens.Spacing.sm)
        }
    }
}

/**
 * One lesson cell.
 *
 * The three states are iOS's, including the one that matters to the suite: only
 * [LessonAvailability.NEXT] carries `academy.nextLessonButton`. A completed lesson
 * is still tappable and still has no identifier, so a flow cannot accidentally
 * re-open something it has already finished by matching the same selector.
 *
 * Locked cells are blurred rather than hidden, as on iOS, and are **not clickable** —
 * `lessonButton.alpha = 0` is what makes them inert there
 * (`LevelTableViewCell.swift:172`), which is a real difference from merely looking
 * dimmed.
 */
@Composable
private fun LessonRow(cell: LessonCell, onOpenLesson: (Lesson) -> Unit) {
    val locked = cell.availability == LessonAvailability.LOCKED
    val completed = cell.availability == LessonAvailability.COMPLETED

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
        modifier = Modifier
            .fillMaxWidth()
            .background(BittrTheme.colors.scrim1, BittrCanvasShapes.field)
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
            .heightIn(min = BittrTokens.Size.minTouchTarget)
            .padding(horizontal = BittrTokens.Spacing.md, vertical = BittrTokens.Spacing.sm),
    ) {
        Text(
            text = cell.lesson.title,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier
                .weight(1f)
                .then(if (locked) Modifier.blur(6.dp).alpha(0.6f) else Modifier),
        )
        if (completed) {
            Box(contentAlignment = Alignment.Center) {
                BittrCheckBadge(size = 22.dp)
            }
        }
    }
}

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
