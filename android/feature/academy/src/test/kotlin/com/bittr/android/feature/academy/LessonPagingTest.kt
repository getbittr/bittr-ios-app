package com.bittr.android.feature.academy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Paging inside a lesson, against the steps `academy.yaml` drives: forward to page 2,
 * back to page 1, forward again, then Next until Complete.
 */
class LessonPagingTest {

    private val lesson = AcademyContent.levels.first().lessons.first()

    @Test
    fun `a fresh page starts loading with no buttons`() {
        val state = LessonUiState(lesson)

        assertTrue(state.isLoadingPage)
        assertFalse(
            "iOS builds the buttons after the last component, so neither id exists " +
                "mid-load. The flow's wait-then-tap ordering depends on that.",
            state.showsButtons,
        )
    }

    @Test
    fun `page one has no back button and the last page completes`() {
        val first = LessonUiState(lesson).pageLoaded()
        assertTrue(first.isFirstPage)
        assertFalse(first.isLastPage)

        var state = first
        repeat(lesson.pages.size - 1) { state = state.nextPage().pageLoaded() }

        assertTrue(state.isLastPage)
        assertFalse(state.isFirstPage)
    }

    @Test
    fun `back returns to page one and forward returns to page two`() {
        val page2 = LessonUiState(lesson).pageLoaded().nextPage()
        assertEquals(1, page2.pageIndex)
        assertTrue("Paging re-runs loadPage, which restarts the spinner.", page2.isLoadingPage)

        val backToPage1 = page2.pageLoaded().previousPage()
        assertEquals(0, backToPage1.pageIndex)
        assertTrue(backToPage1.isFirstPage)

        assertEquals(1, backToPage1.pageLoaded().nextPage().pageIndex)
    }

    @Test
    fun `paging past either end is a no-op`() {
        val first = LessonUiState(lesson).pageLoaded()
        assertEquals(
            "Back on page 1 has no button to come from, but the guard is what keeps a " +
                "stray call from indexing out of the pages list.",
            first,
            first.previousPage(),
        )

        var last = first
        repeat(lesson.pages.size - 1) { last = last.nextPage().pageLoaded() }
        assertEquals(
            "Next on the last page completes the lesson; it must not page anywhere.",
            last,
            last.nextPage(),
        )
    }

    @Test
    fun `every page of every lesson is reachable by paging forward`() {
        AcademyContent.levels.flatMap { it.lessons }.forEach { each ->
            var state = LessonUiState(each).pageLoaded()
            var visited = 1
            while (!state.isLastPage) {
                state = state.nextPage().pageLoaded()
                visited++
            }
            assertEquals(
                "Lesson ${each.id} does not page through all of its pages.",
                each.pages.size,
                visited,
            )
        }
    }
}
