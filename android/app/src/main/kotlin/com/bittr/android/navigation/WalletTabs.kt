package com.bittr.android.navigation

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import com.bittr.android.core.designsystem.LocalAppBarLogoVisible
import com.bittr.android.core.designsystem.LocalAppBarBackgroundVisible
import com.bittr.android.core.designsystem.BittrAppBarLogoOverlay
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrBottomNavBar
import com.bittr.android.core.designsystem.BittrNavTab
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.MenuSlideSpec
import kotlin.math.roundToInt
import com.bittr.android.core.designsystem.OverlayHost
import com.bittr.android.core.designsystem.LocalOverlayHost
import com.bittr.android.core.designsystem.OverlayHostLayer
import androidx.compose.runtime.remember

/**
 * Wallet and Academy side by side under one menu bar — iOS's `homeContainerView` and
 * `infoContainerView`, which `menuButtonTapped` slides across by a screen width while the menu's
 * selection slides with them ([MenuSlideSpec]). The bar stays put and Settings is reachable from
 * either.
 *
 * The pages fill the screen and the bar floats over their lower edge, as on iOS; each page is given
 * the space the bar takes, to leave at the end of what it scrolls so its last row can clear it.
 *
 * One top bar over both, too — `CoreViewController`'s `topBar`, which the containers slide under:
 * its translucent fill, curve and logo stay put while the pages move, and the pages leave their
 * own out.
 *
 * Academy is built the first time it is chosen and let go once Wallet has slid back over it, as
 * `loadInfoVC` and `hideInfoVC` do. Back from Academy goes to Wallet.
 *
 * @param wallet Home, without its own menu bar.
 * @param academy the Academy, without a back arrow.
 */
@Composable
internal fun WalletTabs(
    onSettings: () -> Unit,
    wallet: @Composable (modifier: Modifier, bottomSpace: Dp) -> Unit,
    academy: @Composable (modifier: Modifier, bottomSpace: Dp) -> Unit,
) {
    var tab by rememberSaveable { mutableStateOf(BittrNavTab.Wallet) }
    val progress by animateFloatAsState(
        targetValue = if (tab == BittrNavTab.Academy) 1f else 0f,
        animationSpec = MenuSlideSpec,
        label = "walletTabs",
    )
    BackHandler(enabled = tab == BittrNavTab.Academy) { tab = BittrNavTab.Wallet }
    // The bar's plates, their 10 above and 20 below, and the system bar under them.
    val bottomSpace = MenuBarSpace + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    // What a page puts above the menu bar — Home's sync view, drawn over everything as iOS's
    // `CoreViewController` draws it.
    val overlay = remember { OverlayHost() }

    // Behind both pages, and seen only where the spring overshoots and a page's trailing edge pulls
    // away from the screen's: the canvas yellow, as the pages' own tops and Academy are.
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BittrTheme.colors.canvas),
    ) {
        val outerLogoVisible = LocalAppBarLogoVisible.current
        val outerBarVisible = LocalAppBarBackgroundVisible.current
        CompositionLocalProvider(
            LocalAppBarLogoVisible provides false,
            LocalAppBarBackgroundVisible provides false,
            LocalOverlayHost provides overlay,
        ) {
            BoxWithConstraints(
                modifier = Modifier
                    .fillMaxSize()
                    .clipToBounds()
                    // The pages run down behind the bar and the system bar; [bottomSpace] clears both.
                    .consumeWindowInsets(WindowInsets.navigationBars),
            ) {
                val width = constraints.maxWidth
                wallet(
                    Modifier
                        .fillMaxSize()
                        .offset { IntOffset((-progress * width).roundToInt(), 0) },
                    bottomSpace,
                )
                // The spring overshoots either way, so Academy is kept while it is anywhere on its way.
                if (tab == BittrNavTab.Academy || progress != 0f) {
                    academy(
                        Modifier
                            .fillMaxSize()
                            .offset { IntOffset(((1f - progress) * width).roundToInt(), 0) },
                        bottomSpace,
                    )
                }
            }
        }
        // The one top bar. Hidden with the rest of the app's logos until the launch animation has
        // landed, and while a stack slide pins the nav host's own over this one.
        CompositionLocalProvider(LocalAppBarLogoVisible provides outerLogoVisible) {
            BittrAppBarLogoOverlay(background = outerBarVisible)
        }
        BittrBottomNavBar(
            // Choosing the page already showing does nothing, as on iOS.
            onWallet = { tab = BittrNavTab.Wallet },
            onAcademy = { tab = BittrNavTab.Academy },
            onSettings = onSettings,
            selected = tab,
            walletTestTag = TestID.Nav.walletButton,
            academyTestTag = TestID.Nav.academyButton,
            settingsTestTag = TestID.Nav.settingsButton,
            // Clear of the system's navigation bar by more than the plates' shadow, which the bar's
            // scrim would otherwise cover.
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(bottom = 20.dp),
        )
        OverlayHostLayer(overlay)
    }
}

/** The menu bar's plates with 10 above them and 20 below. */
private val MenuBarSpace = 10.dp + 45.dp + 20.dp
