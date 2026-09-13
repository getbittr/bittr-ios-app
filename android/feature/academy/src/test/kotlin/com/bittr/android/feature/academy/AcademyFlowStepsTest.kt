package com.bittr.android.feature.academy

import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * `shared/flows/features/academy.yaml`, step for step, on the JVM.
 *
 * The flow needs an emulator to prove the tags are bridged onto the accessibility
 * tree (guarded separately by `TestTagsAsResourceIdGuardTest` in `:app`). Everything
 * else it asserts — that each identifier exists at the moment the flow reaches it,
 * and that tapping it produces the next state — is a property of the composition,
 * and this walks it in ninety seconds instead of a boot.
 *
 * The image loader is stubbed to return nothing, which is the *interesting* case:
 * `addImage` carries on down its failure branch too, so a page with an unreachable
 * image must still finish loading and still show its button.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
class AcademyFlowStepsTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val store = InMemoryLessonProgressStore()

    private val firstLesson = AcademyContent.levels.first().lessons[0]
    private val secondLesson = AcademyContent.levels.first().lessons[1]

    private fun academy() {
        composeRule.setContent {
            BittrTheme {
                AcademyScreen(onBack = {}, progressStore = store)
            }
        }
    }

    /** `extendedWaitUntil` with the flow's own generosity, in JVM terms. */
    private fun awaitTag(tag: String) {
        composeRule.waitUntil(TIMEOUT_MS) {
            composeRule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun tagIsGone(tag: String): Boolean =
        composeRule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty()

    @Test
    fun `the flow walks a lesson end to end and the next one unlocks`() {
        academy()

        // - assertVisible: id: "academy.headerLabel"
        composeRule.onNodeWithTag(TestID.Academy.headerLabel).assertIsDisplayed()

        // - tapOn: id: "academy.nextLessonButton"
        // - extendedWaitUntil: visible academy.nextPageButton
        composeRule.onNodeWithTag(TestID.Academy.nextLessonButton).performClick()
        awaitTag(TestID.Academy.nextPageButton)

        // Page 1 is the first page, so there is no Back button. The flow relies on
        // that when it pages back below.
        assertEquals(true, tagIsGone(TestID.Academy.backPageButton))

        // - tapOn: academy.nextPageButton  → page 2, which has Back.
        composeRule.onNodeWithTag(TestID.Academy.nextPageButton).performClick()
        awaitTag(TestID.Academy.backPageButton)

        // - tapOn: academy.backPageButton  → page 1, Back gone again.
        composeRule.onNodeWithTag(TestID.Academy.backPageButton).performClick()
        awaitTag(TestID.Academy.nextPageButton)
        assertEquals(true, tagIsGone(TestID.Academy.backPageButton))

        // - repeat while academy.nextPageButton is visible: tap it.
        var guard = 0
        while (!tagIsGone(TestID.Academy.nextPageButton)) {
            composeRule.onNodeWithTag(TestID.Academy.nextPageButton).performClick()
            composeRule.waitForIdle()
            check(guard++ < MAX_PAGES) { "the flow's paging loop does not terminate" }
        }

        // - assertVisible: academy.completeButton — the same button, relabelled.
        composeRule.onNodeWithTag(TestID.Academy.completeButton).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Academy.completeButton).performClick()

        // - assertVisible: academy.headerLabel — back on the Academy.
        awaitTag(TestID.Academy.headerLabel)
        assertEquals(
            "Completing the lesson has to persist, or the next open re-locks it.",
            setOf(firstLesson.id),
            store.completedLessonIds(),
        )

        // - tapOn: academy.nextLessonButton again → the following lesson.
        composeRule.onNodeWithTag(TestID.Academy.nextLessonButton).performClick()
        awaitTag(TestID.Academy.nextPageButton)
    }

    @Test
    fun `exactly one cell carries the flow's selector`() {
        academy()

        assertEquals(
            "Maestro takes the first match. Two cells carrying academy.nextLessonButton " +
                "would open whichever one the list happens to compose first.",
            1,
            composeRule.onAllNodesWithTag(TestID.Academy.nextLessonButton)
                .fetchSemanticsNodes().size,
        )
    }

    @Test
    fun `a page with an unreachable image still finishes loading`() {
        val lessonWithImage = AcademyContent.levels
            .flatMap { it.lessons }
            .first { lesson -> lesson.pages.any { it.components.any { c -> c is Component.Image } } }

        composeRule.setContent {
            BittrTheme {
                OneLessonScreen(
                    lesson = lessonWithImage,
                    onCompleted = {},
                    onClose = {},
                    imageLoader = object : LessonImageLoader {
                        override suspend fun load(url: String): ImageBitmap? = null
                    },
                )
            }
        }

        val imagePage = lessonWithImage.pages
            .indexOfFirst { page -> page.components.any { it is Component.Image } }

        awaitTag(TestID.Academy.nextPageButton)
        repeat(imagePage) {
            composeRule.onNodeWithTag(TestID.Academy.nextPageButton).performClick()
            composeRule.waitForIdle()
        }

        assertEquals(
            "The spinner has to stop on a failed download too — `addImage` calls " +
                "addNextComponent() down both branches (Image.swift:69-79), and the flow " +
                "waits on the spinner rather than on the image.",
            true,
            tagIsGone(TestID.Academy.lessonSpinner),
        )
    }

    private companion object {
        const val TIMEOUT_MS = 10_000L

        /** No lesson has anything like this many pages; it only stops a hung loop. */
        const val MAX_PAGES = 50
    }
}
