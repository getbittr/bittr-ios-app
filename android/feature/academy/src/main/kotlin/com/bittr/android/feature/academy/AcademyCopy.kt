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

    /**
     * The list's heading. Lowercase, where iOS's `academybeta` reads "Academy (beta)":
     * the third design review (S25) set screen headings in lowercase to match the top
     * bars and "bitcoin value". Lesson titles are authored content and keep their case.
     *
     * **Without "(beta)" — Ruben, 2026-09-22: the Academy is not in beta any more.** iOS
     * still ships `academybeta`, so the two platforms read differently until that key is
     * reworded; this is the only place Android says it. No flow asserts this text —
     * `academy.yaml` finds the screen by `academy.headerLabel`.
     */
    const val TITLE: String = "academy"

    /** `Button.swift:126` — the same button, relabelled on the last page. */
    const val NEXT: String = "Next"
    const val COMPLETE: String = "Complete"
}
