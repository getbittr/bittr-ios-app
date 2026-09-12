package com.bittr.android.feature.academy

/**
 * The Academy's user-visible words, taken verbatim from the iOS `Language.swift`
 * entries the screens read today.
 *
 * Same arrangement as `ScannerCopy`: the words are here and [Id] records the
 * `shared/strings/` key each one moves to when BIT-12 migrates both platforms, so
 * the two cannot drift while the migration is in flight. None of these carry a
 * factual claim about the build, so — unlike the scanner's and the map's — they are
 * ordinary copy and can be reworded without a compliance read.
 */
internal object AcademyCopy {

    object Id {
        const val HEADER = "academyheader"
        const val TITLE = "academybeta"
    }

    /** `AcademyViewController.setLanguage()`. Carries `academy.headerLabel`. */
    const val HEADER: String =
        "Learn everything about bitcoin and take control of your financial future. " +
            "From basics to advanced topics, we've got you covered."

    /** The screen's own title, in the app bar. */
    const val TITLE: String = "Academy (beta)"

    /** `Button.swift:126` — the same button, relabelled on the last page. */
    const val NEXT: String = "Next"
    const val COMPLETE: String = "Complete"
}
