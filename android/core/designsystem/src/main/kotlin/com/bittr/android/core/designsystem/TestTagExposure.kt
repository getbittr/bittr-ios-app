package com.bittr.android.core.designsystem

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId

/**
 * Publish this subtree's `testTag`s as accessibility resource ids.
 *
 * The app root sets `testTagsAsResourceId` once (`MainActivity`), and that is what lets
 * the shared Maestro flows find `id:` selectors at all. **A dialog does not inherit it:**
 * `AlertDialog` composes into its own window with its own semantics root, so without this
 * every `alert.button.N` inside one was invisible to Maestro and each flow step that taps
 * an alert button failed as "element not found" on Android.
 */
@OptIn(ExperimentalComposeUiApi::class)
fun Modifier.exposeTestTags(): Modifier = semantics { testTagsAsResourceId = true }
