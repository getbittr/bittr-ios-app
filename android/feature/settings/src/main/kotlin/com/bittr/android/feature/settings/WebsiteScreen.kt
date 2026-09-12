package com.bittr.android.feature.settings

import android.graphics.Bitmap
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrTheme

/**
 * The website pages — `ios/bittr/Settings/WebsiteViewController`.
 *
 * Support, the privacy policy and the terms, each loaded into a web view under a bar
 * with the down button that closes it. The bar carries `website.downButton` rather
 * than `header.downButton`: iOS gives this screen its own id, and
 * `features/settings.yaml` selects on it three times.
 *
 * ### What is deliberately not ported here
 *
 * `WebsiteViewController` also injects a `MutationObserver` that watches the page for
 * LNURL links and hands them to the app's LNURL-auth handler, and cancels navigation
 * to `lightning:` / `lnurl` / `tag=login` URLs. That is the login-with-Lightning path
 * — BIT-10's flow and BIT-34's origin gate — and it needs both the LNURL handler and
 * a node. **The gate is what matters, not the feature**: BIT-34 exists because a web
 * view that hands any page's LNURL link to a signing key is a phishing surface, so
 * the wrong order to port these in is handler first, origin check later.
 *
 * So the client below allows `https://getbittr.com` and blocks everything else,
 * including `lightning:`. A blocked LNURL link does nothing today, which is the
 * correct behaviour for a build that cannot honour it. [shouldOverrideUrlLoading] is
 * where BIT-34's check goes, and it is already the only door.
 */
@Composable
fun WebsiteScreen(
    page: WebsitePage,
    onDown: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var loading by remember(page) { mutableStateOf(true) }
    val colors = BittrTheme.colors

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surfaceBright)
            .navigationBarsPadding(),
    ) {
        CompositionLocalProvider(LocalContentColor provides colors.onCanvas) {
            BittrModalHeader(
                title = SettingsStrings.SETTINGS,
                onDown = onDown,
                icon = BittrIconPaths.SETTINGS,
                // No `header.titleLabel` here: iOS's WebsiteViewController draws its
                // own `topBar` rather than calling `addHeader`, so only the down
                // button is identified, and adding an id Android-only would put the
                // two platforms on different selectors.
                downTestTag = TestID.Website.downButton,
                modifier = Modifier
                    .background(colors.canvas)
                    .statusBarsPadding(),
            )
        }

        Box(modifier = Modifier.fillMaxSize()) {
            AndroidView(
                factory = { context ->
                    WebView(context).apply {
                        webViewClient = BittrWebViewClient(
                            onPageStarted = { loading = true },
                            onPageFinished = { loading = false },
                        )
                        tag = page
                        loadUrl(page.url)
                    }
                },
                // `update` runs on every recomposition — including the one the
                // spinner's own state change causes — so the load has to be guarded
                // by something. Not by the view's current URL: that is the *landed*
                // page, which differs from the requested one after any redirect, and
                // comparing them would reload forever. The tag is the page that was
                // asked for.
                update = { view ->
                    if (view.tag != page) {
                        view.tag = page
                        view.loadUrl(page.url)
                    }
                },
                modifier = Modifier.fillMaxSize(),
            )

            // `webSpinner`, which iOS starts on load and stops at
            // `estimatedProgress == 1.0`.
            if (loading) {
                CircularProgressIndicator(
                    color = colors.emphasis,
                    modifier = Modifier.align(Alignment.Center),
                )
            }
        }
    }
}

/**
 * Keeps the web view on bittr's own pages.
 *
 * JavaScript is left **off** — it is off by default on `WebView` and these are three
 * static content pages. The iOS side turns it on only to run the LNURL observer,
 * which is not ported; see the note on [WebsiteScreen].
 */
private class BittrWebViewClient(
    private val onPageStarted: () -> Unit,
    private val onPageFinished: () -> Unit,
) : WebViewClient() {

    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
        onPageStarted()
    }

    override fun onPageFinished(view: WebView?, url: String?) {
        onPageFinished()
    }

    /**
     * Anything that is not an `https://getbittr.com` page is refused rather than
     * handed to the system.
     *
     * Returning true cancels the navigation without opening it anywhere else, which
     * is the conservative half of what iOS does — iOS cancels *and* routes LNURL to
     * its auth handler. Adding the second half is BIT-10/BIT-34's, and this is the
     * single place it goes.
     */
    override fun shouldOverrideUrlLoading(
        view: WebView?,
        request: WebResourceRequest?,
    ): Boolean {
        val url = request?.url ?: return true
        return !(url.scheme == "https" && url.host?.endsWith("getbittr.com") == true)
    }
}
