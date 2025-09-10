//
//  Signup1ViewController.swift
//  bittr
//
//  Created by Tom Melters on 22/05/2023.
//

import UIKit
import BitcoinDevKit

class Signup1ViewController: UIViewController {

    // Create or Restore wallet view. First view new users see.
    
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var topLabel: UILabel!
    
    // Next button
    @IBOutlet weak var buttonView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    
    // Restore button
    @IBOutlet weak var restoreView: UIView!
    @IBOutlet weak var restoreButton: UIButton!
    @IBOutlet weak var restoreLabel: UILabel!
    
    // Article
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "what-is-bittr"
    var pageArticle1 = Article()
    
    @IBOutlet weak var nextButtonSpinner: UIActivityIndicatorView!
    @IBOutlet weak var createWalletLabel: UILabel!
    
    var nextTapped = false
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii
        self.headerView.layer.cornerRadius = 13
        self.buttonView.layer.cornerRadius = 13
        self.restoreView.layer.cornerRadius = 13
        self.cardView.layer.cornerRadius = 13
        self.imageContainer.layer.cornerRadius = 13
        
        // Button titles
        self.nextButton.setTitle("", for: .normal)
        self.restoreButton.setTitle("", for: .normal)
        self.articleButton.setTitle("", for: .normal)
        
        // Card styling
        self.cardView.layer.shadowColor = UIColor.black.cgColor
        self.cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        self.cardView.layer.shadowRadius = 12.0
        self.cardView.layer.shadowOpacity = 0.05
        
        self.changeColors()
        self.setWords()
        Task {
            await self.setSignupArticle(articleSlug: self.pageArticle1Slug, coreVC: self.signupVC!.coreVC!, articleButton: self.articleButton, articleTitle: self.articleTitle, articleImage: self.articleImage, articleSpinner: self.spinner1, completion: { article in
                self.pageArticle1 = article ?? Article()
            })
        }
    }
    
    @IBAction func restoreButtonClicked(_ sender: UIButton) {
        
        self.signupVC?.moveToPage(2)
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        // Check internet connection.
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            self.showAlert(presentingController: self.signupVC ?? self, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        self.createWalletLabel.alpha = 0
        self.nextButtonSpinner.startAnimating()
        self.nextTapped = true
        
        var mnemonicString = ""
        if let actualMnemonic = CacheManager.getMnemonic() {
            // Mnemonic found in storage.
            print("Did find mnemonic.")
            mnemonicString = actualMnemonic
        } else {
            // Create new mnemonic.
            print("Did not find mnemonic. Creating a new one.")
            mnemonicString = BitcoinDevKit.Mnemonic(wordCount: .words12).description
            CacheManager.storeMnemonic(mnemonic: mnemonicString)
        }
        
        // Send mnemonic to 3rd signup view.
        if self.signupVC?.coreVC == nil { print("CoreVC nil.") }
        self.signupVC?.coreVC?.newMnemonic = mnemonicString.components(separatedBy: " ")

        self.didReceiveMnemonic()
    }
    
    func didReceiveMnemonic() {
        
        self.createWalletLabel.alpha = 1
        self.nextButtonSpinner.stopAnimating()
        
        if nextTapped == true {
            self.signupVC?.moveToPage(4)
            nextTapped = false
        }
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        if sender.accessibilityIdentifier != nil {
            self.coreVC!.infoVC!.launchArticle(articleTag: "\(sender.accessibilityIdentifier!)")
        }
    }
    
    func changeColors() {
        self.topLabel.textColor = Colors.getColor("blackorwhite")
        if CacheManager.darkModeIsOn() {
            self.restoreLabel.textColor = Colors.getColor("blackorwhite")
        } else {
            self.restoreLabel.textColor = Colors.getColor("transparentblack")
        }
    }
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "welcome")
        self.topLabel.text = Language.getWord(withID: "createyourownwallet")
        self.createWalletLabel.text = Language.getWord(withID: "createwallet")
        self.restoreLabel.text = Language.getWord(withID: "restorewallet")
    }
    
}

extension UIViewController {
    
    func setSignupArticle(articleSlug:String, coreVC:CoreViewController, articleButton:UIButton, articleTitle:UILabel, articleImage:UIImageView, articleSpinner:UIActivityIndicatorView, completion: @escaping (Article?) -> Void) async {
        
        await self.getArticle(articleSlug, coreVC: coreVC) { result in
            
            switch result {
            case .success(let receivedArticle):
                articleButton.accessibilityIdentifier = articleSlug
                articleTitle.text = receivedArticle.title
                articleImage.setArticleImage(url: receivedArticle.image, coreVC: coreVC, imageSpinner: articleSpinner)
                completion(receivedArticle)
            case .failure(let receivedError):
                print("Couldn't get article: \(receivedError)")
                completion(nil)
            }
        }
    }
    
    func getArticle(_ withSlug:String, coreVC:CoreViewController!, completion: @escaping (Result<Article, String>) -> Void) async {
        
        if coreVC.allArticles?[withSlug] != nil {
            return completion(.success(coreVC.allArticles![withSlug]!))
        } else {
            Task {
                await CallsManager.makeApiCall(url: "https://getbittr.com/api/articles", parameters: nil, getOrPost: "GET") { result in
                    
                    switch result {
                    case .success(let receivedDictionary):
                        
                        if let actualArticles = receivedDictionary["articles"] as? NSDictionary {
                            
                            let everyArticle = self.parseArticles(articles: actualArticles)
                            coreVC.allArticles = everyArticle
                            
                            DispatchQueue.main.async {
                                if everyArticle[withSlug] != nil {
                                    return completion(.success(everyArticle[withSlug]!))
                                } else {
                                    return completion(.failure("Article doesn't exist."))
                                }
                            }
                        }
                    case .failure(let error):
                        return completion(.failure(error.localizedDescription))
                    }
                }
            }
        }
    }
    
    func parseArticles(articles:NSDictionary) -> [String:Article] {
        
        var allArticles = [String:Article]()
        
        for (articleid, articledata) in articles {
            
            let thisArticle = Article()
            
            if let actualArticleID = articleid as? String {
                thisArticle.id = actualArticleID
            }
            if let actualArticleData = articledata as? NSDictionary {
                
                if let actualArticleImage = actualArticleData["headerimage"] as? String {
                    thisArticle.image = actualArticleImage
                }
                if let actualArticleText = actualArticleData["text"] as? [NSDictionary] {
                    thisArticle.text = actualArticleText
                }
                if let actualArticleDate = actualArticleData["date"] as? Int {
                    thisArticle.date = actualArticleDate
                }
                if let actualArticleTitle = actualArticleData["title"] as? String {
                    thisArticle.title = actualArticleTitle
                }
                if let actualArticleOrder = actualArticleData["order"] as? Int {
                    thisArticle.order = actualArticleOrder
                }
                if let actualArticleVisibility = actualArticleData["visible"] as? Bool {
                    thisArticle.isVisible = actualArticleVisibility
                }
                if let actualArticleCategory = actualArticleData["category"] as? String {
                    thisArticle.category = actualArticleCategory
                }
            }
            
            allArticles.updateValue(thisArticle, forKey: thisArticle.id)
        }
        
        return allArticles
    }
}

extension UIImageView {
    
    func setArticleImage(url:String, coreVC:CoreViewController?, imageSpinner:UIActivityIndicatorView?) {
        
        if let actualData = CacheManager.getImage(key: url) {
            // Image is available in cache.
            self.image = UIImage(data: actualData)
            imageSpinner?.stopAnimating()
        } else {
            // Image needs to be downloaded.
            Task {
                if let actualData = await coreVC?.getImage(urlString: url) {
                    // Image successfully downloaded.
                    DispatchQueue.main.async {
                        imageSpinner?.stopAnimating()
                        self.image = UIImage(data: actualData)
                        CacheManager.storeImageInCache(key: url, data: actualData)
                        imageSpinner?.stopAnimating()
                    }
                } else {
                    // Image couldn't be downloaded.
                    DispatchQueue.main.async {
                        imageSpinner?.stopAnimating()
                    }
                }
            }
        }
    }
}
