package com.bittr.android.feature.website

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.lnurl.LnurlRequestSlot

/**
 * S-36 · Website — the in-app browser, and the Android counterpart of
 * `ios/bittr/Settings/WebsiteViewController.swift`.
 *
 * One chrome for all five iOS call sites: Settings' support / privacy / terms
 * pages, the transaction screen's block explorer link, and a map place's
 * `website`. BIT-21 proposed a `CustomTabsIntent` for the third-party ones;
 * BIT-33 corrects that, and the reason is `website.downButton`. Two shared
 * Maestro flows tap it —`shared/flows/features/bitcoin_map.yaml:110–123` and
 * `shared/flows/features/swap.yaml:387–393` — and a Custom Tab has no such
 * element and no way to be given one. The security goal is met by attaching no
 * bridge, not by changing the container.
 *
 * ### What makes this safe for a BTCMap URL
 *
 * 1. **No bridge, on any origin.** `androidx.webkit` is not a dependency of this
 *    module, so `addWebMessageListener` is not on the classpath, and
 *    `addJavascriptInterface` is absent from the whole app and kept absent by a
 *    guard test and a CI grep (R-1).
 * 2. **No Lightning navigation interception** — [WebsiteNavigationPolicy] drops
 *    `lightning:` and `lnurl` navigations, everywhere, silently (R-2).
 * 3. **The R-11 hardening baseline**, applied in one place ([HardenedWebView]) and
 *    enforced by `WebViewHardeningGuardTest`.
 * 4. **Trust is derived from the loaded URL, on every navigation** — no call site
 *    declares it. See [FirstPartyOrigins].
 *
 * Point 4 is why this composable takes a URL and not a trust level, and it is
 * the one to preserve: `map.onePlace.websiteButton` is handed its URL straight
 * from BTCMap place data.
 *
 * ### Visual spec (BIT-4 batch 4, S-36)
 *
 * Top bar 50 dp `primary`, full-bleed. Down chevron 20×20 at (20, 15) inside a
 * 40×40 touch target. Open-externally icon 26×26 at trailing 20. Web view fills
 * the rest over `surfaceContainerHigh`. Progress is a
 * [LinearProgressIndicator] bound to `onProgressChanged`, replacing iOS's
 * indeterminate `UIActivityIndicatorView` (DEV-57).
 */
@Composable
fun WebsiteScreen(
    url: String,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    // Re-derived on every committed navigation rather than computed once. A
    // first-party page that redirects off-origin, or a third-party link followed
    // out of one, is reclassified — trust follows the page, not the entry point.
    var loadedUrl by remember { mutableStateOf(url) }
    val trust = FirstPartyOrigins.trustOf(loadedUrl)

    var progress by remember { mutableFloatStateOf(0f) }

    // R-10. Nothing can claim this in v1 (no bridge), but the cancel-on-teardown
    // half is wired now because it is the half that gets forgotten.
    val lnurlSlot = remember { LnurlRequestSlot() }
    DisposableEffect(Unit) {
        onDispose { lnurlSlot.cancel() }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
    ) {
        WebsiteTopBar(
            onClose = onClose,
            onOpenExternally = { openExternally(context, loadedUrl) },
        )

        // Determinate, from onProgressChanged. Rendered only while loading so the
        // bar does not sit at 100% under a finished page.
        if (progress > 0f && progress < 1f) {
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth(),
            )
        }

        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { factoryContext ->
                HardenedWebView.create(
                    context = factoryContext,
                    onProgress = { progress = it / 100f },
                    onPageUrlChanged = { newUrl -> if (newUrl != null) loadedUrl = newUrl },
                    lnurlSlot = lnurlSlot,
                ).also { webView ->
                    // Loaded here rather than in an update block: `update` runs on
                    // every recomposition, and progress changes cause those, so
                    // reloading there would restart the page continuously.
                    webView.loadUrl(url)
                }
            },
        )
    }

    // Debug-only, and only ever the trust level and the host — never the URL. A
    // BTCMap merchant URL in logcat is a record of where the user was, and on a
    // withdraw or auth LNURL the string itself is a bearer credential.
    if (BuildConfig.DEBUG) {
        DisposableEffect(trust, loadedUrl) {
            android.util.Log.d(
                "WebsiteScreen",
                "trust=$trust host=${Uri.parse(loadedUrl).host} (no bridge attached)",
            )
            onDispose { }
        }
    }
}

/**
 * The 50 dp top bar.
 *
 * The chevron's geometry is the fiddly part and is spelled out because it is
 * spec'd: the icon is 20×20 with its top-left at (20, 15), and its touch target
 * is 40×40. A 40 dp target centred on a 20 dp icon at (20, 15) starts at
 * (10, 5) — hence the offset. Sizing the button 20 dp to match the icon would
 * make the whole thing a half-size target, and this is the control both Maestro
 * flows tap to leave the screen.
 */
@Composable
private fun WebsiteTopBar(
    onClose: () -> Unit,
    onOpenExternally: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(50.dp)
            .background(MaterialTheme.colorScheme.primary),
    ) {
        IconButton(
            onClick = onClose,
            modifier = Modifier
                .offset(x = 10.dp, y = 5.dp)
                .size(40.dp)
                // Asserted by two shared Maestro flows. Not optional, and not
                // renameable without editing shared/test-ids/test-ids.json.
                .testTag(TestID.Website.downButton),
        ) {
            Icon(
                painter = painterResource(R.drawable.ic_website_chevron_down),
                contentDescription = stringResource(R.string.website_close),
                tint = MaterialTheme.colorScheme.onPrimary,
                modifier = Modifier.size(20.dp),
            )
        }

        IconButton(
            onClick = onOpenExternally,
            modifier = Modifier
                .align(Alignment.CenterEnd)
                // Trailing 20 dp to the icon's edge; the target is 40 dp wide and
                // the 26 dp icon sits centred in it, so the box's own edge is
                // 7 dp further out.
                .offset(x = (-13).dp)
                .size(40.dp),
        ) {
            Icon(
                painter = painterResource(R.drawable.ic_website_open_external),
                contentDescription = stringResource(R.string.website_open_externally),
                tint = MaterialTheme.colorScheme.onPrimary,
                modifier = Modifier.size(26.dp),
            )
        }
    }
}

/**
 * Hands the current page to the system browser (`Intent.ACTION_VIEW`), matching
 * iOS's `safariButtonTapped`.
 *
 * Two differences from iOS worth knowing:
 *
 * - iOS opens `tappedUrl`, the URL the screen was *entered* with. This opens the
 *   URL currently loaded, which is what the user is looking at.
 * - The scheme is checked first. `ACTION_VIEW` with an arbitrary URI is a way to
 *   reach other apps' components, and the URL here can have come from BTCMap
 *   place data. Only `http` and `https` leave the app.
 */
private fun openExternally(context: android.content.Context, url: String) {
    // isForMainFrame = true, and here it is a statement of fact rather than a
    // default: [url] is the WebView's committed top-level URL, which is the main
    // frame's by definition. An iframe's URL cannot reach this function — the
    // button acts on the page the user is looking at, not on anything embedded
    // in it — so there is no subframe to demote (BIT-58).
    val decision = WebsiteNavigationPolicy.decide(
        url = url,
        trust = FirstPartyOrigins.trustOf(url),
        isForMainFrame = true,
    )
    if (decision !is NavigationDecision.Load) {
        return
    }
    try {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(url))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    } catch (_: ActivityNotFoundException) {
        // No browser installed. Nothing useful to say and nothing to fall back to.
    }
}

@Preview(showBackground = true)
@Composable
private fun WebsiteTopBarPreview() {
    BittrTheme {
        WebsiteTopBar(onClose = {}, onOpenExternally = {})
    }
}
