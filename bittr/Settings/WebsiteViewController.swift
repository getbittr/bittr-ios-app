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
    
    override func loadView() {
        super.loadView()
        
        let webConfiguration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        
        let script = """
            const observer = new MutationObserver(() => {
                const links = Array.from(document.querySelectorAll('a'))
                    .map(a => a.href)
                    .filter(h => h.toLowerCase().includes('lnurl') || h.toLowerCase().startsWith('lightning:'));
                
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
        
        let absolute = url.absoluteString.lowercased()
        if absolute.hasPrefix("lightning:") || absolute.hasPrefix("lnurl") || absolute.contains("tag=login") {
            self.handleLNURL(code: absolute.replacingOccurrences(of: "lightning:", with: ""))
            decisionHandler(.cancel)
            return
        }
        
        decisionHandler(.allow)
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        
        if message.name == "lnurl", let url = message.body as? String {
            print("Did find URL: \(url)")
            self.handleLNURL(code: url.replacingOccurrences(of: "lightning:", with: ""))
        }
    }
    
}
