package com.bittr.android.core.designsystem

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

/**
 * Shape, from BIT-4 `design-system` §1.6 — taken from the `cornerRadius`
 * assignments across the Swift sources, not from Material's defaults.
 *
 * | Slot | Value | iOS uses | Applies to |
 * |---|---|---|---|
 * | `small` | 8dp | 111 | buttons, fields, chips — the default |
 * | `medium` | 13dp | 45 | cards, sheets, the balance card |
 * | `large` | 20dp | 3 | large containers |
 *
 * The outliers at 1, 2, 5, 7 and 12dp are one- to three-use hairlines and near-misses
 * for 8. They snap to the scale; do not reproduce them.
 *
 * `extraSmall` and `extraLarge` have no iOS source — they are Material's values, kept
 * so a component that reaches for them does not fall off the theme.
 *
 * Fully round shapes (avatars, round icon buttons — 25 uses at radius 25/45/12.5, all
 * of them half the side) use [androidx.compose.foundation.shape.CircleShape] directly;
 * `Shapes` has no slot for a 50 % radius.
 */
val BittrShapes = Shapes(
    extraSmall = RoundedCornerShape(4.dp),
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(13.dp),
    large = RoundedCornerShape(20.dp),
    extraLarge = RoundedCornerShape(28.dp),
)
