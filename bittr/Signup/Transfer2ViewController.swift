//
//  Transfer2ViewController.swift
//  bittr
//
//  Created by Tom Melters on 09/06/2023.
//

import UIKit

class Transfer2ViewController: UIViewController {

    @IBOutlet weak var checkView: UIView!
    @IBOutlet weak var ibanView: UIView!
    @IBOutlet weak var nameView: UIView!
    @IBOutlet weak var codeView: UIView!
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var centerViewCenterY: NSLayoutConstraint!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var screenshotView: UIView!
    @IBOutlet weak var screenshotButton: UIButton!
    
    var currentClientID = ""
    var currentIbanID = ""
    
    @IBOutlet weak var ourIbanLabel: UILabel!
    @IBOutlet weak var yourCodeLabel: UILabel!
    
    @IBOutlet weak var ibanButton: UIButton!
    @IBOutlet weak var nameButton: UIButton!
    @IBOutlet weak var codeButton: UIButton!
    
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "when-do-i-receive-my-bitcoin"
    var pageArticle1 = Article()
    
    var articles:[String:Article]?
    var allImages:[String:UIImage]?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        checkView.layer.cornerRadius = 35
        ibanView.layer.cornerRadius = 13
        nameView.layer.cornerRadius = 13
        codeView.layer.cornerRadius = 13
        nextView.layer.cornerRadius = 13
        cardView.layer.cornerRadius = 13
        screenshotView.layer.cornerRadius = 13
        imageContainer.layer.cornerRadius = 13
        nextButton.setTitle("", for: .normal)
        articleButton.setTitle("", for: .normal)
        screenshotButton.setTitle("", for: .normal)
        
        ibanButton.setTitle("", for: .normal)
        nameButton.setTitle("", for: .normal)
        codeButton.setTitle("", for: .normal)
        
        let viewBorder = CAShapeLayer()
        viewBorder.strokeColor = UIColor.black.cgColor
        viewBorder.frame = checkView.bounds
        viewBorder.fillColor = nil
        viewBorder.path = UIBezierPath(roundedRect: checkView.bounds, cornerRadius: 35).cgPath
        viewBorder.lineWidth = 2
        self.checkView.layer.addSublayer(viewBorder)
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateData), name: NSNotification.Name(rawValue: "signupnext"), object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setArticleImage), name: NSNotification.Name(rawValue: "setimage\(pageArticle1Slug)"), object: nil)
        
        if let actualArticles = articles {
            if let actualArticle = actualArticles[pageArticle1Slug] {
                self.pageArticle1 = actualArticle
                DispatchQueue.main.async {
                    self.articleTitle.text = self.pageArticle1.title
                    if let actualData = CacheManager.getImage(key: self.pageArticle1.image) {
                        self.articleImage.image = UIImage(data: actualData)
                    }
                    if self.articleImage.image != nil {
                        self.spinner1.stopAnimating()
                    }
                }
                self.articleButton.accessibilityIdentifier = self.pageArticle1Slug
            }
        }
        
        if let actualImages = allImages {
            if let actualImage = actualImages[pageArticle1Slug] {
                self.articleImage.image = actualImage
            }
        }
    }
    
    @objc func setSignupArticles(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualArticle = userInfo[pageArticle1Slug] as? Article {
                self.pageArticle1 = actualArticle
                DispatchQueue.main.async {
                    self.articleTitle.text = self.pageArticle1.title
                }
                self.articleButton.accessibilityIdentifier = self.pageArticle1Slug
            }
        }
    }
    
    @objc func setArticleImage(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualImage = userInfo["image"] as? UIImage {
                self.spinner1.stopAnimating()
                self.articleImage.image = actualImage
            }
        }
    }
    
    
    @objc func updateData(notification:NSNotification) {
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let clientID = userInfo["client"] as? String, let ibanID = userInfo["iban"] as? String {
                self.currentClientID = clientID
                self.currentIbanID = ibanID
                
                if userInfo["code"] as? Bool == true {
                    
                    let deviceDict = UserDefaults.standard.value(forKey: "device") as? NSDictionary
                    if let actualDeviceDict = deviceDict {
                        let clients:[Client] = CacheManager.parseDevice(deviceDict: actualDeviceDict)
                        for client in clients {
                            if client.id == self.currentClientID {
                                for iban in client.ibanEntities {
                                    if iban.id == self.currentIbanID {
                                        
                                        self.ourIbanLabel.text = iban.ourIbanNumber
                                        self.yourCodeLabel.text = iban.yourUniqueCode
                                        
                                        self.ibanButton.accessibilityIdentifier = iban.ourIbanNumber
                                        self.nameButton.accessibilityIdentifier = iban.ourName
                                        self.codeButton.accessibilityIdentifier = iban.yourUniqueCode
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        
        var centerViewHeight = centerView.bounds.height
        
        if centerView.bounds.height + 40 > contentView.bounds.height {
            
            NSLayoutConstraint.deactivate([self.contentViewHeight])
            self.contentViewHeight = NSLayoutConstraint(item: self.contentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: centerViewHeight + 60)
            NSLayoutConstraint.activate([self.contentViewHeight])
            self.centerViewCenterY.constant = 0
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
         NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["tag":sender.accessibilityIdentifier]
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func screenshotButtonTapped(_ sender: UIButton) {
        
        let imageSize = UIScreen.main.bounds.size as CGSize
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 0)
        let context = UIGraphicsGetCurrentContext()
        for obj:AnyObject in UIApplication.shared.windows {
            if let window = obj as? UIWindow {
                if window.responds(to: #selector(getter: UIWindow.screen)) || window.screen == UIScreen.main {
                    context!.saveGState()
                    context!.translateBy(x: window.center.x, y: window.center.y)
                    context!.concatenate(window.transform)
                    context!.translateBy(x: -window.bounds.size.width * window.layer.anchorPoint.x, y: -window.bounds.size.height * window.layer.anchorPoint.y)
                    window.layer.render(in: context!)
                    context!.restoreGState()
                }
            }
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIImageWriteToSavedPhotosAlbum(image!, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        
        if error == nil {
            let alert = UIAlertController(title: "Saved", message: "We've added the screenshot to your Photo Library.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
        } else {
            let alert = UIAlertController(title: "Oops", message: "We couldn't save your screenshot. Try taking a screenshot manually.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
        }
    }
    
    @IBAction func copyItem(_ sender: UIButton) {
        
        UIPasteboard.general.string = sender.accessibilityIdentifier
        let alert = UIAlertController(title: "Copied", message: sender.accessibilityIdentifier, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
}
