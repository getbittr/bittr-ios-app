//
//  WebsiteViewController.swift
//  bittr
//
//  Created by Tom Melters on 17/12/2023.
//

import UIKit
import WebKit

class WebsiteViewController: UIViewController, WKUIDelegate {

    // UI elements
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var safariButton: UIButton!
    @IBOutlet weak var websiteView: UIView!
    @IBOutlet weak var webSpinner: UIActivityIndicatorView!
    
    // Variables
    var tappedUrl:String?
    var webView = WKWebView()
    
    override func loadView() {
        super.loadView()
        
        let webConfiguration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.uiDelegate = self
        webView.navigationDelegate = self as? WKNavigationDelegate
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
    
}
