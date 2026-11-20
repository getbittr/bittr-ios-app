package com.bittr.android

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import com.bittr.android.core.designsystem.BittrAppBarLogoHeight
import com.bittr.android.core.designsystem.BittrLogo
import com.bittr.android.core.designsystem.BittrTheme

/**
 * iOS's privacy cover (`CoreViewController.showPrivacyCover`): `yelloworblue3` with the logo in the
 * middle. A window of its own, so it lies over every sheet and pop-up the app has open.
 */
@Composable
internal fun PrivacyCover() {
    Dialog(onDismissRequest = {}, properties = CoverDialog) {
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        SideEffect {
            window?.setDimAmount(0f)
            window?.setWindowAnimations(0)
        }
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .fillMaxSize()
                .background(BittrTheme.colors.primaryHigh),
        ) {
            BittrLogo(height = BittrAppBarLogoHeight)
        }
    }
}

private val CoverDialog = DialogProperties(
    usePlatformDefaultWidth = false,
    decorFitsSystemWindows = false,
    dismissOnBackPress = false,
    dismissOnClickOutside = false,
)
