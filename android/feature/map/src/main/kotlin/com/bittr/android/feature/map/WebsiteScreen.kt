package com.bittr.android.feature.map

import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.rememberFillIcon

/**
 * A merchant's own website, in-app. Ported from iOS's `WebsiteViewController`.
 *
 * **This is untrusted third-party content**, which is the whole reason it is worth a
 * comment. BTCMap's `website` field is whatever an OpenStreetMap contributor typed;
 * the app has no relationship with the site and makes no claim about it. So:
 *
 * - **No JavaScript interface.** Nothing in the app is reachable from the page.
 *   `addJavascriptInterface` is the one line that would change that, and it is
 *   absent deliberately.
 * - **JavaScript is on**, because a shop's opening hours are routinely rendered by
 *   it and a blank page is a worse answer than a page. It is on for a page that can
 *   reach nothing, which is a very different thing from it being on in a WebView
 *   that holds wallet state — the distinction BIT-34 drew on the iOS side.
 * - **No file or content access.** A page cannot read `file://` or the app's own
 *   content providers. Both default to off on modern API levels; set explicitly,
 *   because "it defaults to safe" is not something a reader of this file can check.
 * - **Navigation stays inside.** `shouldOverrideUrlLoading` returning false keeps
 *   links in this window rather than firing intents out of the app, matching a
 *   `WKWebView` with no navigation delegate.
 *
 * The close control carries `website.downButton`, the id `bitcoin_map.yaml` waits on
 * to know the browser opened and taps to leave it.
 */
@Composable
internal fun WebsiteScreen(url: String, onClose: () -> Unit) {
    val colors = BittrTheme.colors

    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(colors.canvas)
                .statusBarsPadding()
                .navigationBarsPadding(),
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(BittrTokens.Size.minTouchTarget)
                    .clickable(role = Role.Button, onClick = onClose)
                    .testTag(TestID.Website.downButton),
            ) {
                Image(
                    imageVector = rememberFillIcon(BittrIconPaths.BACK, colors.onCanvas),
                    contentDescription = "Close",
                    modifier = Modifier.size(18.dp),
                )
            }

            AndroidView(
                factory = { context ->
                    WebView(context).apply {
                        webViewClient = WebViewClient()
                        settings.javaScriptEnabled = true
                        settings.allowFileAccess = false
                        settings.allowContentAccess = false
                        settings.domStorageEnabled = true
                        loadUrl(url.withScheme())
                    }
                },
                modifier = Modifier.fillMaxWidth().weight(1f),
            )
        }
    }
}

/**
 * BTCMap's `website` values are inconsistent — some carry a scheme, some do not.
 * A `WebView` handed `example.com` treats it as a search term, not a host.
 */
private fun String.withScheme(): String =
    if (startsWith("http://") || startsWith("https://")) this else "https://$this"
