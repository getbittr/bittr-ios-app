package com.bittr.android.push

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrBody
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrInlineAlert
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrTokens

/**
 * What a push puts on screen, over whatever screen is showing — iOS presents all three
 * from `CoreViewController`, above every other view controller.
 *
 * Drawn in the activity's own window rather than as dialogs, so the root's
 * `testTagsAsResourceId` covers the ids (Maestro reads only the focused window), and
 * later in the tree than the navigation host so it covers it. Order is iOS's: the
 * Question card, then the loading card, then an alert on top of both.
 */
@Composable
fun PushOverlayHost(coordinator: PushCoordinator) {
    val state by coordinator.uiState.collectAsState()

    state.question?.let { question ->
        PushQuestionCard(question = question, onDown = coordinator::closeQuestion)
    }
    state.loading?.let { PushLoadingCard(it) }
    state.alert?.let { alert ->
        BackHandler {
            alert.buttons.firstOrNull { it.dismisses }?.let(coordinator::onAlertButton)
        }
        BittrInlineAlert(
            title = alert.title,
            message = alert.message,
            buttons = alert.buttons.map { button ->
                BittrAlertButton(label = button.label, dismissesAlert = button.dismisses) {
                    coordinator.onAlertButton(button)
                }
            },
            cardTestTag = alert.testTag,
        )
    }
}

/** `QuestionViewController` with a push's header and body. */
@Composable
private fun PushQuestionCard(question: PushQuestion, onDown: () -> Unit) {
    BackHandler(onBack = onDown)
    BittrCanvas(
        appBar = false,
        // Taps land here rather than on the screen underneath.
        modifier = Modifier.pointerInput(Unit) { detectTapGestures { } },
    ) {
        BittrModalHeader(
            title = question.title,
            onDown = onDown,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(BittrTokens.Spacing.md),
        ) {
            BittrCard(modifier = Modifier.testTag(TestID.Question.yellowCard)) {
                BittrBody(
                    text = question.answer,
                    textAlign = TextAlign.Start,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(TestID.Question.answerLabel),
                )
            }
        }
    }
}

/** iOS `LoadingOverlayView`: a card with a spinner and bold text, and nothing to tap. */
@Composable
private fun PushLoadingCard(loading: PushLoading) {
    BackHandler { /* Not dismissable, as on iOS. */ }
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.4f))
            .pointerInput(Unit) { detectTapGestures { } },
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(11.dp, Alignment.CenterHorizontally),
            modifier = Modifier
                .padding(horizontal = BittrTokens.Spacing.xl)
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(28.dp))
                .padding(25.dp)
                .let { if (loading.testTag != null) it.testTag(loading.testTag) else it },
        ) {
            CircularProgressIndicator(
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.size(20.dp),
            )
            Text(
                text = loading.message,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
            )
        }
    }
}
