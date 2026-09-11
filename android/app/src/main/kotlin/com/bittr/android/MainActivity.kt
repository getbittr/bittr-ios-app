package com.bittr.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.navigation.BittrNavHost
import dagger.hilt.android.AndroidEntryPoint

/**
 * The single Activity. Navigation is Compose Navigation inside it — see
 * [BittrNavHost].
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            BittrTheme {
                BittrApp()
            }
        }
    }
}

/**
 * App root.
 *
 * Two things here are load-bearing for the Maestro harness and are easy to delete
 * by accident:
 *
 * 1. **`testTagsAsResourceId = true`.** Compose `Modifier.testTag` is invisible to
 *    UIAutomator — and therefore to Maestro — unless this is set on an ancestor. It
 *    is set once here and inherited by everything below. Without it every
 *    `assertVisible: id:` in `shared/flows/` fails with "element not found" while
 *    the app looks perfectly correct on screen.
 *
 * 2. **The `core.launchComplete` tag.** iOS sets this once its launch animation
 *    finishes, and every flow gates on it via `helpers/wait_for_launch.yaml`. The
 *    scaffold has no launch animation, so the marker is simply the root — accurate
 *    today. When the animation is ported, this tag must move to whatever composes
 *    *after* the cover is gone, or the flows will resume tapping into a cover that
 *    swallows the taps. That failure looks like a flaky test, not a bug.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun BittrApp() {
    Surface(modifier = Modifier.fillMaxSize()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .semantics { testTagsAsResourceId = true }
                .testTag(TestID.Core.launchComplete),
        ) {
            BittrNavHost()
        }
    }
}
