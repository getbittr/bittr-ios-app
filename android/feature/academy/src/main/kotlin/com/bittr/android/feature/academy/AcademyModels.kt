package com.bittr.android.feature.academy

/**
 * The Academy's content model, ported from `ios/bittr/Academy/Academy/Entities/`.
 *
 * Four types on iOS — `Level`, `Lesson`, `Page`, `Component` — all mutable `NSObject`
 * subclasses assembled field by field. They are immutable here and [Component] is a
 * sealed hierarchy rather than a `type` enum plus two always-present strings, because
 * the iOS shape allows a `.label` carrying a `url` and an `.image` carrying `text`,
 * and `addNextComponent` then reads whichever one the `type` says
 * (`OneLessonViewController.swift:69-84`). Making that unrepresentable costs nothing
 * and is the one thing worth changing on the way across.
 *
 * The content itself is in [AcademyContent], transcribed mechanically — see
 * `tools/academy_content.py`.
 */
data class Level(
    val order: Int,
    val lessons: List<Lesson>,
)

data class Lesson(
    val id: String,
    val title: String,
    val image: String?,
    val pages: List<Page>,
)

data class Page(
    val components: List<Component>,
)

sealed interface Component {

    /**
     * A paragraph. The text carries `<b>` markup, which iOS renders through its own
     * attributed-string pass in `Label.swift`.
     */
    data class Text(val text: String) : Component

    /** An image the page downloads when it is shown. */
    data class Image(val url: String) : Component
}
