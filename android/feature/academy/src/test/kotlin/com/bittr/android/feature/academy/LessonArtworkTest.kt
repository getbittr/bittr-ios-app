package com.bittr.android.feature.academy

import org.junit.Assert.assertEquals
import org.junit.Test

class LessonArtworkTest {

    @Test
    fun `every lesson has bundled artwork`() {
        val missing = AcademyContent.levels
            .flatMap { it.lessons }
            .filter { LessonArtwork.forImage(it.image) == null }
            .map { it.id }

        assertEquals(
            "A lesson added to the content without its artwork draws an empty tile. " +
                "Copy it from ios/bittr/Assets.xcassets and add it to LessonArtwork.",
            emptyList<String>(),
            missing,
        )
    }
}
