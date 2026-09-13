package com.bittr.android.feature.academy

/**
 * How one lesson cell is drawn, and — the part the Maestro suite depends on —
 * whether it is the cell that carries `academy.nextLessonButton`.
 *
 * Ported from `LevelTableViewCell.swift:146-177`.
 */
enum class LessonAvailability {

    /** In [Set] of completed ids. Tappable, shows the tick, carries no test id. */
    COMPLETED,

    /**
     * Available and not yet done — the single frontier lesson. **This is the only
     * state that carries `academy.nextLessonButton`**, which is what lets
     * `academy.yaml` use one selector for the first lesson and again for the one
     * that unlocks behind it.
     */
    NEXT,

    /** Blurred out on iOS, and `lessonButton.alpha = 0` so it cannot be tapped. */
    LOCKED,
}

/** One lesson as the Academy list draws it. */
data class LessonCell(
    val lesson: Lesson,
    val availability: LessonAvailability,
)

/** One level as the Academy list draws it, with iOS's "n of m" counter. */
data class LevelSection(
    val order: Int,
    val cells: List<LessonCell>,
) {
    val completedCount: Int get() = cells.count { it.availability == LessonAvailability.COMPLETED }
    val lessonCount: Int get() = cells.size

    /** `LevelTableViewCell`'s `countLabel` — "2 of 6". */
    val countLabel: String get() = "$completedCount of $lessonCount"

    /** `levelLabel` — iOS numbers from the row index, so level 1 is the first row. */
    val title: String get() = "level $order"
}

/**
 * State of the Academy screen: the levels, resolved against the completed set.
 *
 * @param completedLessonIds what `CacheManager.getCompletedLessons()` returns on iOS.
 */
data class AcademyUiState(
    val levels: List<Level> = AcademyContent.levels,
    val completedLessonIds: Set<String> = emptySet(),
) {

    /**
     * Lessons resolved to how they are drawn.
     *
     * The iOS rule, verbatim: a lesson is available when it is itself completed, or
     * it has no predecessor, or its predecessor is completed — where the predecessor
     * of the first lesson in a level is the **last lesson of the previous level**,
     * not nothing (`LevelTableViewCell.swift:146-155`). That cross-level link is the
     * whole reason the sections cannot be resolved independently, and getting it
     * wrong strands every level after the first: level 2's first lesson would read
     * as unlocked from a blank start and level 1's last would unlock nothing.
     */
    val sections: List<LevelSection>
        get() {
            var previous: Lesson? = null
            return levels.map { level ->
                val cells = level.lessons.map { lesson ->
                    val availability = when {
                        lesson.id in completedLessonIds -> LessonAvailability.COMPLETED
                        previous == null -> LessonAvailability.NEXT
                        previous!!.id in completedLessonIds -> LessonAvailability.NEXT
                        else -> LessonAvailability.LOCKED
                    }
                    previous = lesson
                    LessonCell(lesson, availability)
                }
                LevelSection(order = level.order, cells = cells)
            }
        }

    /**
     * The lesson `academy.nextLessonButton` opens.
     *
     * There is at most one, and on a wallet whose completions are contiguous there is
     * exactly one. It can be null — a user who has finished every lesson has no
     * frontier, and iOS draws that the same way: no cell carries the identifier and
     * the flow's `tapOn` would fail. Nothing to fix; there is nothing left to open.
     */
    val nextLesson: Lesson?
        get() = sections.asSequence()
            .flatMap { it.cells }
            .firstOrNull { it.availability == LessonAvailability.NEXT }
            ?.lesson

    /** Applies a completion, as `nextPage` does on the final page of a lesson. */
    fun completing(lessonId: String): AcademyUiState =
        copy(completedLessonIds = completedLessonIds + lessonId)
}

/**
 * State of one open lesson: which page is showing and whether its images are still
 * arriving.
 *
 * `loadPage` clears the page, hides the content and starts `centerSpinner`; the
 * spinner stops once every component on the page has been added, which for an image
 * component means once its download has returned — success *or* failure, since
 * `addImage` calls `addNextComponent()` down both branches
 * (`Image.swift:69-79`). That is why `academy.yaml` can wait on the spinner
 * disappearing rather than on the image appearing.
 */
data class LessonUiState(
    val lesson: Lesson,
    val pageIndex: Int = 0,
    val isLoadingPage: Boolean = true,
) {

    val page: Page get() = lesson.pages[pageIndex]

    val isFirstPage: Boolean get() = pageIndex == 0

    /** The last page relabels Next as Complete — same button, different id. */
    val isLastPage: Boolean get() = pageIndex == lesson.pages.size - 1

    /**
     * iOS builds the buttons only after the last component is laid out, so neither
     * `academy.nextPageButton` nor `academy.completeButton` exists while the page is
     * loading. The flow relies on that: it waits for the spinner to stop before
     * tapping, and the button's absence is the fallback if it does not.
     */
    val showsButtons: Boolean get() = !isLoadingPage

    fun previousPage(): LessonUiState =
        if (isFirstPage) this else copy(pageIndex = pageIndex - 1, isLoadingPage = true)

    fun nextPage(): LessonUiState =
        if (isLastPage) this else copy(pageIndex = pageIndex + 1, isLoadingPage = true)

    fun pageLoaded(): LessonUiState = copy(isLoadingPage = false)
}
