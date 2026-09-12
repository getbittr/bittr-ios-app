package com.bittr.android.feature.academy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The lesson unlock rule, which is the Academy's only real logic and the thing
 * `academy.yaml` is built on top of.
 *
 * The flow taps `academy.nextLessonButton`, completes a lesson, and taps the *same
 * selector* again expecting the next one. That works only if exactly one cell
 * carries the identifier at any time and it moves forward on completion. These are
 * the cases where that could break.
 */
class LessonUnlockTest {

    private val content = AcademyContent.levels

    private fun state(vararg completed: String) =
        AcademyUiState(completedLessonIds = completed.toSet())

    private fun availability(state: AcademyUiState, lessonId: String) =
        state.sections.flatMap { it.cells }.first { it.lesson.id == lessonId }.availability

    @Test
    fun `the content survived the transcription`() {
        assertEquals("Four levels, as in Demo Data.swift.", 4, content.size)
        assertEquals("Twenty-two lessons.", 22, content.sumOf { it.lessons.size })

        val ids = content.flatMap { it.lessons }.map { it.id }
        assertEquals("Lesson ids are the completion keys and must be unique.", ids.size, ids.toSet().size)

        assertTrue(
            "Every lesson needs at least two pages: the flow advances to page 2 and " +
                "exercises Back before it starts looping, so a one-page lesson would fail at " +
                "the first tap rather than reporting a content problem.",
            content.flatMap { it.lessons }.all { it.pages.size >= 2 },
        )
        assertTrue(
            "A page with no components draws a spinner that never stops.",
            content.flatMap { it.lessons }.flatMap { it.pages }.all { it.components.isNotEmpty() },
        )
    }

    @Test
    fun `a fresh wallet unlocks exactly the first lesson`() {
        val state = state()
        val next = state.sections.flatMap { it.cells }
            .filter { it.availability == LessonAvailability.NEXT }

        assertEquals(
            "More than one cell carrying academy.nextLessonButton makes the flow's tap " +
                "ambiguous — Maestro takes the first match, which need not be the frontier.",
            1,
            next.size,
        )
        assertEquals(content.first().lessons.first().id, next.single().lesson.id)
    }

    @Test
    fun `completing a lesson moves the frontier to the next one`() {
        val first = content.first().lessons[0]
        val second = content.first().lessons[1]

        val after = state().completing(first.id)

        assertEquals(LessonAvailability.COMPLETED, availability(after, first.id))
        assertEquals(second.id, after.nextLesson?.id)
        assertEquals(
            "Exactly one frontier after a completion, or the flow's second tap is ambiguous.",
            1,
            after.sections.flatMap { it.cells }.count { it.availability == LessonAvailability.NEXT },
        )
    }

    /**
     * The cross-level link. iOS resolves the first lesson of a level against the
     * **last lesson of the previous level** (`LevelTableViewCell.swift:148-151`), not
     * against nothing — treating the levels independently would unlock the head of
     * every level on a blank wallet, which is four frontier cells and a flow that
     * taps whichever one Maestro sees first.
     */
    @Test
    fun `a level's first lesson waits on the previous level's last`() {
        val lastOfLevel1 = content[0].lessons.last()
        val firstOfLevel2 = content[1].lessons.first()

        assertEquals(
            "Locked while level 1 is unfinished.",
            LessonAvailability.LOCKED,
            availability(state(), firstOfLevel2.id),
        )

        val finishedLevel1 = state(*content[0].lessons.map { it.id }.toTypedArray())
        assertEquals(
            "Unlocked by completing the last lesson of level 1 (${lastOfLevel1.id}).",
            LessonAvailability.NEXT,
            availability(finishedLevel1, firstOfLevel2.id),
        )
    }

    @Test
    fun `a lesson two ahead of the frontier stays locked`() {
        val third = content.first().lessons[2]
        assertEquals(LessonAvailability.LOCKED, availability(state(), third.id))
    }

    /**
     * A completed lesson is tappable and carries no identifier, so a flow cannot
     * re-open something already finished through the same selector.
     */
    @Test
    fun `a completed lesson is not the frontier`() {
        val first = content.first().lessons.first()
        val after = state(first.id)

        assertEquals(LessonAvailability.COMPLETED, availability(after, first.id))
        assertTrue(after.nextLesson?.id != first.id)
    }

    @Test
    fun `a wallet that has finished everything has no frontier`() {
        val everything = state(*content.flatMap { it.lessons }.map { it.id }.toTypedArray())

        assertNull(
            "Nothing left to open, and iOS draws that the same way — no cell carries the id.",
            everything.nextLesson,
        )
        assertNotNull("The sections still render.", everything.sections)
        assertTrue(
            everything.sections.all { it.completedCount == it.lessonCount },
        )
    }

    @Test
    fun `the level counter reads as iOS builds it`() {
        val first = content.first()
        val after = state(first.lessons[0].id, first.lessons[1].id)

        assertEquals("2 of ${first.lessons.size}", after.sections.first().countLabel)
        assertEquals("level 1", after.sections.first().title)
    }
}
