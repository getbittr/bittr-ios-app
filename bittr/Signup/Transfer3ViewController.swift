//
//  Transfer3ViewController.swift
//  bittr
//
//  Created by Tom Melters on 11/06/2023.
//

import UIKit

class Transfer3ViewController: UIViewController {

    // Views and buttons.
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var cardView2: UIView!
    @IBOutlet weak var imageContainer2: UIView!
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var articleButton2: UIButton!
    @IBOutlet weak var backButton: UIButton!
    
    var currentClientID = ""
    var currentIbanID = ""
    
    // Articles.
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "bitcoin-lightning"
    var pageArticle1 = Article()
    @IBOutlet weak var spinner2: UIActivityIndicatorView!
    @IBOutlet weak var article2Image: UIImageView!
    @IBOutlet weak var article2Title: UILabel!
    let pageArticle2Slug = "dollar-cost-averaging"
    var pageArticle2 = Article()
    
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var centerViewCenterY: NSLayoutConstraint!
    
    var articles:[String:Article]?
    var allImages:[String:UIImage]?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii and button titles.
        headerView.layer.cornerRadius = 13
        nextView.layer.cornerRadius = 13
        cardView.layer.cornerRadius = 13
        imageContainer.layer.cornerRadius = 13
        cardView2.layer.cornerRadius = 13
        imageContainer2.layer.cornerRadius = 13
        nextButton.setTitle("", for: .normal)
        articleButton.setTitle("", for: .normal)
        articleButton2.setTitle("", for: .normal)
        backButton.setTitle("", for: .normal)
        
        // Notification observers.
        NotificationCenter.default.addObserver(self, selector: #selector(updateData), name: NSNotification.Name(rawValue: "signupnext"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles2), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setArticleImage), name: NSNotification.Name(rawValue: "setimage\(pageArticle1Slug)"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setArticle2Image), name: NSNotification.Name(rawValue: "setimage\(pageArticle2Slug)"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(checkImageDownload), name: NSNotification.Name(rawValue: "checkimagedownload"), object: nil)
        
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
            if let actualArticle2 = actualArticles[pageArticle2Slug] {
                self.pageArticle2 = actualArticle2
                DispatchQueue.main.async {
                    self.article2Title.text = self.pageArticle2.title
                    if let actualData = CacheManager.getImage(key: self.pageArticle2.image) {
                        self.article2Image.image = UIImage(data: actualData)
                    }
                    if self.article2Image.image != nil {
                        self.spinner2.stopAnimating()
                    }
                }
                self.articleButton2.accessibilityIdentifier = self.pageArticle2Slug
            }
        }
        
        if let actualImages = allImages {
            if let actualImage = actualImages[pageArticle1Slug] {
                self.articleImage.image = actualImage
            }
            if let actualImage2 = actualImages[pageArticle2Slug] {
                self.article2Image.image = actualImage2
            }
        }
    }
    
    
    @objc func checkImageDownload() {
        
        if self.article2Image.image == nil {
            let session = URLSession(configuration: .default)
            let downloadPicTask = session.dataTask(with: URL(string: self.pageArticle2.image)!) { (data, response, error) in
                if let e = error {
                    print("Error downloading picture: \(e)")
                } else {
                    if let res = response as? HTTPURLResponse {
                        print("Downloaded picture with response code \(res.statusCode)")
                        if let imageData = data {
                            let image = UIImage(data: imageData)
                            // Do something with your image.
                            DispatchQueue.main.async {
                                self.spinner2.stopAnimating()
                                self.article2Image.image = image
                            }
                        } else {
                            print("Couldn't get image: Image is nil")
                        }
                    } else {
                        print("Couldn't get response code for some reason")
                    }
                }
            }
            downloadPicTask.resume()
        }
        
        if self.articleImage.image == nil {
            let session = URLSession(configuration: .default)
            let downloadPicTask = session.dataTask(with: URL(string: self.pageArticle1.image)!) { (data, response, error) in
                if let e = error {
                    print("Error downloading picture: \(e)")
                } else {
                    if let res = response as? HTTPURLResponse {
                        print("Downloaded picture with response code \(res.statusCode)")
                        if let imageData = data {
                            let image = UIImage(data: imageData)
                            // Do something with your image.
                            DispatchQueue.main.async {
                                self.spinner1.stopAnimating()
                                self.articleImage.image = image
                            }
                        } else {
                            print("Couldn't get image: Image is nil")
                        }
                    } else {
                        print("Couldn't get response code for some reason")
                    }
                }
            }
            downloadPicTask.resume()
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
    
    @objc func setSignupArticles2(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualArticle = userInfo[pageArticle2Slug] as? Article {
                self.pageArticle2 = actualArticle
                DispatchQueue.main.async {
                    self.article2Title.text = self.pageArticle2.title
                }
                self.articleButton2.accessibilityIdentifier = self.pageArticle2Slug
            }
        }
    }
    
    @objc func setArticle2Image(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualImage = userInfo["image"] as? UIImage {
                self.spinner2.stopAnimating()
                self.article2Image.image = actualImage
            }
        }
    }
    
    @objc func updateData(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let clientID = userInfo["client"] as? String, let ibanID = userInfo["iban"] as? String {
                self.currentClientID = clientID
                self.currentIbanID = ibanID
            }
        }
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        var envKey = "proddevice"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "device"
        }
        
        let deviceDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary
        if let actualDeviceDict = deviceDict {
            let clients:[Client] = CacheManager.parseDevice(deviceDict: actualDeviceDict)
            for client in clients {
                if client.id == self.currentClientID {
                    for iban in client.ibanEntities {
                        if iban.id == self.currentIbanID {
                            
                            let alert = UIAlertController(title: "Open your banking app", message: "\nCreate your (recurring) transfer to\n\n\(iban.ourIbanNumber)\n\(iban.ourName)\n\(iban.yourUniqueCode)", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Done", style: .cancel, handler: {_ in
                                // Hide signup and proceed into wallet.
                                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "restorewallet"), object: nil, userInfo: nil) as Notification)
                            }))
                            self.present(alert, animated: true)
                        }
                    }
                }
            }
        }
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["tag":sender.accessibilityIdentifier]
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func backButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
         NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
}
