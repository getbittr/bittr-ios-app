//
//  WebsiteViewController.swift
//  bittr
//
//  Created by Tom Melters on 17/12/2023.
//

import UIKit
import WebKit

class WebsiteViewController: UIViewController, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {

    // UI elements
    @IBOutlet weak var topBar: UIView!
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var safariButton: UIButton!
    @IBOutlet weak var websiteView: UIView!
    @IBOutlet weak var webSpinner: UIActivityIndicatorView!
    
    // Variables
    var tappedUrl:String?
    var webView = WKWebView()
    var pendingLnurlAuth:LNURLAuthRequest?
    var isHandlingLnurlAuth = false

    /// The only origin whose pages may start a Lightning flow from inside this WebView.
    ///
    /// Two of this controller's five call sites open pages bittr does not control:
    /// `OnePlaceViewController` opens a merchant's website straight from BTCMap data, and
    /// `TransactionViewController` opens the block explorer. The LNURL bridge below is
    /// therefore opt-in per origin, not global — otherwise any such page could hand the
    /// wallet an LNURL-auth request and get it signed with the user's stable identity.
    private static let lnurlBridgeHost = "getbittr.com"

    private static func isFirstParty(_ url:URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == lnurlBridgeHost || host.hasSuffix(".\(lnurlBridgeHost)")
    }

    private var initialUrl:URL? {
        self.tappedUrl.flatMap { URL(string: $0) }
    }

    /// Whether the page *currently on screen* is one bittr controls.
    ///
    /// `webView.url` is what matters here, not `tappedUrl`: a first-party page is free to
    /// navigate somewhere else, and a `WKUserScript` stays installed for every page the
    /// WebView loads afterwards. Falls back to the requested URL for the first load,
    /// before `webView.url` is populated.
    private var isShowingFirstPartyPage:Bool {
        Self.isFirstParty(self.webView.url ?? self.initialUrl)
    }

    override func loadView() {
        super.loadView()

        let webConfiguration = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Install the bridge only when we were asked to open a first-party page. For any
        // other URL this stays a plain browser: no injected script, no `lnurl` handler.
        if Self.isFirstParty(self.initialUrl) {
            let script = """
                const BECH32_LNURL = /^lnurl1[02-9ac-hj-np-z]{6,}$/;

                // Match the lightning scheme, or a bech32 LNURL in the raw attribute —
                // not any href that happens to contain the substring "lnurl".
                const lnurlFrom = (anchor) => {
                    const resolved = (anchor.href || '');
                    const lowered = resolved.toLowerCase();
                    if (lowered.startsWith('lightning:') || lowered.startsWith('lnurl:')) {
                        return resolved;
                    }
                    const raw = (anchor.getAttribute('href') || '').trim().toLowerCase();
                    return BECH32_LNURL.test(raw) ? raw : null;
                };

                const observer = new MutationObserver(() => {
                    const links = Array.from(document.querySelectorAll('a'))
                        .map(lnurlFrom)
                        .filter(Boolean);

                    if (links.length > 0) {
                        window.webkit.messageHandlers.lnurl.postMessage(links[0]);
                    }
                });

                observer.observe(document.body, { childList: true, subtree: true });
                """

            let userScript = WKUserScript(
                source: script,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            contentController.addUserScript(userScript)
            contentController.add(self, name: "lnurl")
        }

        webConfiguration.userContentController = contentController
        
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        
        // Set colors
        self.changeColors()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        downButton.setTitle("", for: .normal)
        downButton.accessibilityIdentifier = TestID.Website.downButton
        safariButton.setTitle("", for: .normal)
        
        webView.translatesAutoresizingMaskIntoConstraints = false
        websiteView.addSubview(webView)
        webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
        
        let webViewTopConstraint = NSLayoutConstraint(item: webView, attribute: .top, relatedBy: .equal, toItem: websiteView, attribute: .top, multiplier: 1, constant: 0)
        let webViewBottomConstraint = NSLayoutConstraint(item: webView, attribute: .bottom, relatedBy: .equal, toItem: websiteView, attribute: .bottom, multiplier: 1, constant: 0)
        let webViewLeftConstraint = NSLayoutConstraint(item: webView, attribute: .left, relatedBy: .equal, toItem: websiteView, attribute: .left, multiplier: 1, constant: 0)
        let webViewRightConstraint = NSLayoutConstraint(item: webView, attribute: .right, relatedBy: .equal, toItem: websiteView, attribute: .right, multiplier: 1, constant: 0)
        
        websiteView.addConstraints([webViewTopConstraint, webViewLeftConstraint, webViewRightConstraint, webViewBottomConstraint])
        
        if let actualTappedUrl = self.tappedUrl {
            self.webSpinner.startAnimating()
            let thisUrl = URL(string: actualTappedUrl)
            let myRequest = URLRequest(url: thisUrl!)
            webView.load(myRequest)
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if self.webView.estimatedProgress == 1.0 {
            // Loading is complete.
            self.webSpinner.stopAnimating()
        }
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    @IBAction func safariButtonTapped(_ sender: UIButton) {
        if let actualTappedUrl = self.tappedUrl {
            let websiteUrl:NSURL? = NSURL(string: actualTappedUrl)
            if websiteUrl != nil {
                UIApplication.shared.open(websiteUrl! as URL, options: [:], completionHandler: nil)
            }
        }
    }
    
    func changeColors() {
        
        self.topBar.backgroundColor = Colors.getColor("yelloworblue1")
        self.view.backgroundColor = Colors.getColor("whiteorblue2")
        self.websiteView.backgroundColor = Colors.getColor("whiteorblue2")
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        // Match on the scheme, and on a properly parsed `tag=login` query item — not on a
        // substring of the whole URL, which made every https link carrying `tag=login`
        // anywhere in it an auth attempt against that host.
        let scheme = url.scheme?.lowercased()
        let hasLoginTag = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .contains { $0.name.lowercased() == "tag" && $0.value?.lowercased() == "login" } ?? false
        let isLnurlNavigation = scheme == "lightning"
            || scheme == "lnurl"
            || url.absoluteString.lowercased().hasPrefix("lnurl1")
            || (scheme == "https" && hasLoginTag)

        if isLnurlNavigation {
            // Only a page bittr controls may drive the wallet. A third-party page reached
            // from the map or the block explorer gets the navigation cancelled, nothing more.
            guard self.isShowingFirstPartyPage else {
                Log.info("Ignoring an LNURL navigation from a third-party page.")
                decisionHandler(.cancel)
                return
            }

            self.isHandlingLnurlAuth = true
            self.handleLNURL(code: url.lnurlCode)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {

        // The script is installed only for first-party pages, but such a page can navigate
        // to a third-party one and the script goes with it — so re-check what is actually
        // on screen before acting on anything it posts.
        guard self.isShowingFirstPartyPage else {
            Log.info("Ignoring an LNURL message from a third-party page.")
            return
        }

        if !self.isHandlingLnurlAuth, message.name == "lnurl", let url = message.body as? String {
            Log.debug("Did find URL: \(url)")
            self.isHandlingLnurlAuth = true
            self.handleLNURL(code: URL(string: url)?.lnurlCode ?? url)
        }
    }

}

private extension URL {

    /// The payload to hand to `handleLNURL`: this URL with any `lightning:` prefix removed.
    ///
    /// Case is only flattened for a bech32 LNURL, and then only to lowercase. Bech32 is
    /// case-insensitive but must be uniform, so lowercasing an all-uppercase `LNURL1…` is
    /// the canonical form and always decodes. An https `tag=login` callback is *not*
    /// case-insensitive — lowercasing the whole URL, as this code used to, corrupts its
    /// path and its k1, so that case is passed through untouched.
    var lnurlCode:String {
        let stripped = self.absoluteString.replacingOccurrences(
            of: "lightning:",
            with: "",
            options: [.caseInsensitive, .anchored]
        )

        let lowered = stripped.lowercased()
        let isBech32Lnurl = lowered.range(
            of: "^lnurl1[02-9ac-hj-np-z]{6,}$",
            options: .regularExpression
        ) != nil

        return isBech32Lnurl ? lowered : stripped
    }
}
