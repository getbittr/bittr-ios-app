package com.bittr.android.feature.academy

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bittr.android.core.designsystem.BittrTheme

/**
 * The Academy's sizes from the design review (pass 2, `academy/03`–`07`).
 *
 * They are the review's numbers rather than `BittrTokens`' 5 dp grid: the review
 * specifies the Academy on Material's 4 dp one (24 dp column, 16 dp gaps), and the
 * designsystem has no heading at 28 sp. Kept private to the feature until another
 * screen adopts the same S13 heading, at which point it belongs in the designsystem.
 */
internal object AcademyLayout {

    /** S13: the content column's top and side padding. */
    val contentPadding = 24.dp

    /** S13: heading to whatever follows it. */
    val headingGap = 16.dp
}

/**
 * Derived from the theme's styles so they keep Gilroy and the theme's defaults, and
 * only the size, weight and leading the review specifies change.
 *
 * The review's 600 weights are written as [FontWeight.SemiBold], but the app bundles
 * only Gilroy Regular and Bold, and Compose resolves 600 to the nearest heavier face,
 * so they render as Bold.
 */
internal object AcademyType {

    val heading: TextStyle
        @Composable get() = MaterialTheme.typography.headlineSmall.copy(
            fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold,
        )

    val intro: TextStyle
        @Composable get() = MaterialTheme.typography.bodyLarge.copy(
            fontSize = 16.sp, lineHeight = 24.sp, fontWeight = FontWeight.Normal,
        )

    val levelTitle: TextStyle
        @Composable get() = MaterialTheme.typography.titleLarge.copy(
            fontSize = 20.sp, fontWeight = FontWeight.Bold,
        )

    val levelCount: TextStyle
        @Composable get() = MaterialTheme.typography.labelLarge.copy(
            fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
        )

    val tileTitle: TextStyle
        @Composable get() = MaterialTheme.typography.labelMedium.copy(
            fontSize = 13.sp, lineHeight = 17.sp, fontWeight = FontWeight.SemiBold,
        )

    val lessonBody: TextStyle
        @Composable get() = MaterialTheme.typography.bodyLarge.copy(
            fontSize = 17.sp, lineHeight = 26.sp, fontWeight = FontWeight.Normal,
        )
}

/**
 * The S13 screen heading: left-aligned, with the review's 16 dp beneath it. The caller
 * supplies the column's 24 dp side padding.
 */
@Composable
internal fun AcademyHeading(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = AcademyType.heading,
        color = BittrTheme.colors.onCanvas,
        textAlign = TextAlign.Start,
        modifier = modifier
            .fillMaxWidth()
            .padding(bottom = AcademyLayout.headingGap),
    )
}
