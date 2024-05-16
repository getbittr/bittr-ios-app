//
//  InfoViewController.swift
//  bittr
//
//  Created by Tom Melters on 21/04/2023.
//

import UIKit
import Sentry

class InfoViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    @IBOutlet weak var infoTableView: UITableView!
    
    @IBOutlet weak var topView: UIView!
    @IBOutlet weak var articlesCollectionView: UICollectionView!
    @IBOutlet weak var newsHeader: UIView!
    @IBOutlet weak var faqHeader: UIView!
    @IBOutlet weak var noArticles: UILabel!
    
    var coreVC:CoreViewController?
    
    
    let questions = [["title":"How does bittr work?", "image":"article1", "text":[["text":"<title>How does Bittr work?</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"]]],["title":"Why do I want to buy bitcoin?", "image":"article2", "text":[["text":"<title>Why do I want to buy bitcoin?</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"]]],["title":"What and how does bittr charge me?", "image":"article3", "text":[["text":"<title>What and how does bittr charge me?</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"]]],["title":"Does bittr support every bank account?", "image":"article4", "text":[["text":"<title>Does bittr support every bank account?</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"]]],["title":"What is dollar cost averaging?", "image":"article5", "text":[["text":"<title>What is dollar cost averaging?</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"]]]]
    
    let articles = [["title":"Save bitcoin into your bittr lightning wallet", "image":"article6", "text":[["text":"<title>Save bitcoin into your bittr lightning wallet</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"],["text":"<header>The problems</span><br><br><normal>Googling ‘business plan’ yields over 5 billion results. That’s so much information that it’s impossible to distinguish good from bad.</span><br><br><normal>Then there are tons of templates that provide little (if any) guidance into how to fill in each blank.</span><br><br><normal>Plus every template is different and there are many different philosophies as to what a business plan should and shouldn’t contain.</span><br><br><br>"]]],["title":"The new bittr app is here!", "image":"article7", "text":[["text":"<title>The new bittr app is here!</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"]]]]
    
    var faqArticles = [Article]()
    var newsArticles = [Article]()
    var everyArticle = [String:Article]()
    var allImages = [String:UIImage]()
    
    //var faqOrNews = ""
    var tappedArticle = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()

        infoTableView.delegate = self
        infoTableView.dataSource = self
        
        articlesCollectionView.delegate = self
        articlesCollectionView.dataSource = self
        
        articlesCollectionView.contentInset = UIEdgeInsets(top: 0, left: 7, bottom: 0, right: 7)
        
        newsHeader.layer.cornerRadius = 13
        newsHeader.layer.shadowColor = UIColor.black.cgColor
        newsHeader.layer.shadowOffset = CGSize(width: 0, height: 5)
        newsHeader.layer.shadowRadius = 8.0
        newsHeader.layer.shadowOpacity = 0.1
        
        faqHeader.layer.cornerRadius = 13
        faqHeader.layer.shadowColor = UIColor.black.cgColor
        faqHeader.layer.shadowOffset = CGSize(width: 0, height: 5)
        faqHeader.layer.shadowRadius = 8.0
        faqHeader.layer.shadowOpacity = 0.1
        
        NotificationCenter.default.addObserver(self, selector: #selector(launchArticle), name: NSNotification.Name(rawValue: "launcharticle"), object: nil)
        
        getArticles()
    }
    
    func parseArticles(articles:NSDictionary) -> [String:Article] {
        
        /*var faqArticles = [Article]()
        var newsArticles = [Article]()*/
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
            
            //faqArticles += [thisArticle]
            allArticles.updateValue(thisArticle, forKey: thisArticle.id)
        }
        
        return allArticles
    }
    
    func getArticles() {
        
        // TODO: Correct URL?
        var envUrl = "https://getbittr.com/api/articles"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envUrl = "https://model-arachnid-viable.ngrok-free.app/articles"
        }
        
        var request = URLRequest(url: URL(string: envUrl)!,timeoutInterval: Double.infinity)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                print("Articles request error: " + String(describing: error))
                DispatchQueue.main.async {
                    if let actualError = error {
                        SentrySDK.capture(error: actualError)
                    }
                }
                return
            }
            
            //print(String(data: data, encoding: .utf8)!)
            
            var dataDictionary:NSDictionary?
            if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                do {
                    dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                    if let actualDataDict = dataDictionary {
                        if let actualArticles = actualDataDict["articles"] as? NSDictionary {
                            self.everyArticle = self.parseArticles(articles: actualArticles)
                            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil, userInfo: self.everyArticle) as Notification)
                            for (articleid, articledata) in self.everyArticle {
                                if articledata.category == "General", articledata.isVisible == true {
                                    self.faqArticles += [articledata]
                                    //self.newsArticles += [articledata]
                                } else {
                                    if articledata.isVisible == true {
                                        self.newsArticles += [articledata]
                                    }
                                }
                            }
                            DispatchQueue.main.async {
                                self.faqArticles.sort { article1, article2 in
                                    article1.order < article2.order
                                }
                                self.newsArticles.sort { article1, article2 in
                                    article1.order < article2.order
                                }
                                self.infoTableView.reloadData()
                                self.articlesCollectionView.reloadData()
                            }
                        }
                        /*if let actualDataItems = actualDataDict["data"] as? NSDictionary {
                            let dataOurIban = actualDataItems["iban"]
                            let dataCode = actualDataItems["deposit_code"]
                            let dataSwift = actualDataItems["swift"]
                            if let actualDataOurIban = dataOurIban as? String, let actualDataCode = dataCode as? String, let actualDataSwift = dataSwift as? String {
                                CacheManager.addBittrIban(clientID: self.currentClientID, ibanID: self.currentIbanID, ourIban: actualDataOurIban, ourSwift: actualDataSwift, yourCode: actualDataCode)
                                DispatchQueue.main.async {
                                    
                                    self.nextButtonActivityIndicator.stopAnimating()
                                    self.nextButtonLabel.alpha = 1
                                    let notificationDict:[String: Any] = ["page":page, "client":self.currentClientID, "iban":self.currentIbanID, "code":true]
                                     NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                                }
                            }
                        } else if let actualApiMessage = actualDataDict["message"] as? String {
                            // Some message has been received.
                            DispatchQueue.main.async {
                                if actualApiMessage == "Unable to create customer account (invalid iban)" {
                                    self.nextButtonActivityIndicator.stopAnimating()
                                    self.nextButtonLabel.alpha = 1
                                    self.codeTextField.text = nil
                                    let alert = UIAlertController(title: "Oops!", message: "The IBAN you've entered appears to be invalid. Please enter a valid IBAN.", preferredStyle: .alert)
                                    alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: {_ in
                                        let notificationDict:[String: Any] = ["page":"6"]
                                         NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                                    }))
                                    self.present(alert, animated: true)
                                }
                            }
                        }*/
                    }
                } catch let error as NSError {
                    print("Articles request error: " + error.localizedDescription)
                    DispatchQueue.main.async {
                        SentrySDK.capture(error: error)
                    }
                }
            }
        }
        task.resume()
    }
    
    override func viewDidLayoutSubviews() {
        
        var topInset:CGFloat = 100
        var bottomInset:CGFloat = 80
        
        if #available(iOS 13.0, *) {
            if let window = UIApplication.shared.windows.first {
                if window.safeAreaInsets.bottom == 0 {
                    topInset = 120
                    bottomInset = 130
                }
            }
        } else if #available(iOS 11.0, *) {
            if let window = UIApplication.shared.keyWindow {
                if window.safeAreaInsets.bottom == 0 {
                    topInset = 120
                    bottomInset = 130
                }
            }
        }
        
        infoTableView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        
        if let headerView = infoTableView.tableHeaderView {
            let height = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
            var headerFrame = headerView.frame
            if height != headerFrame.size.height {
                headerFrame.size.height = height
                headerView.frame = headerFrame
                infoTableView.tableHeaderView = headerView
            }
        }
        
        //self.view.layoutIfNeeded()
        //infoTableView.setContentOffset(.zero, animated: true)
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        infoTableView.setContentOffset(CGPoint(x: 0, y: -150), animated: true)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return self.faqArticles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "ArticleCell", for: indexPath) as? ArticleTableViewCell
        
        if let actualCell = cell {
            
            actualCell.layer.zPosition = CGFloat(indexPath.row)
            actualCell.titleLabel.text = self.faqArticles[indexPath.row].title
            actualCell.articleButton.tag = indexPath.row
            actualCell.articleButton.accessibilityIdentifier = self.faqArticles[indexPath.row].id
            
            if let actualData = CacheManager.getImage(key: self.faqArticles[indexPath.row].image) {
                actualCell.articleImage.image = UIImage(data: actualData)
            } else {
                // Image hasn't been saved to cache before.
                
                actualCell.spinner.startAnimating()
                let session = URLSession(configuration: .default)
                let downloadPicTask = session.dataTask(with: URL(string: self.faqArticles[indexPath.row].image)!) { (data, response, error) in
                    if let e = error {
                        print("Error downloading picture: \(e)")
                    } else {
                        if let res = response as? HTTPURLResponse {
                            //print("Downloaded picture with response code \(res.statusCode)")
                            if let imageData = data {
                                let image = UIImage(data: imageData)
                                // Do something with your image.
                                DispatchQueue.main.async {
                                    actualCell.spinner.stopAnimating()
                                    actualCell.articleImage.image = image
                                    self.allImages.updateValue(image!, forKey: self.faqArticles[indexPath.row].id)
                                    NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setimage\(self.faqArticles[indexPath.row].id)"), object: nil, userInfo: ["image":image!]) as Notification)
                                    NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "updateallimages"), object: nil, userInfo: ["images":self.allImages]) as Notification)
                                    
                                    // Store image in cache.
                                    let imageSize = image!.size.height * image!.size.width
                                    let imageDownsize = 1000000 / imageSize
                                    var imageData:Data?
                                    if imageDownsize < 1 {
                                        imageData = image!.jpegData(compressionQuality: imageDownsize)!
                                    } else {
                                        imageData = image!.jpegData(compressionQuality: 1)!
                                    }
                                    if let actualImageData = imageData {
                                        CacheManager.storeImageInCache(key: self.faqArticles[indexPath.row].image, data: actualImageData)
                                    }
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
            
            return actualCell
        }
        
        return UITableViewCell()
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        if self.newsArticles.count == 0 {
            self.noArticles.alpha = 1
        } else {
            self.noArticles.alpha = 0
        }
        
        return self.newsArticles.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ArticleCollectionCell", for: indexPath) as? ArticleCollectionViewCell
        
        if let actualCell = cell {
            
            actualCell.articleTitleLabel.text = self.newsArticles[indexPath.row].title
            actualCell.articleButton.tag = indexPath.row
            actualCell.articleButton.accessibilityIdentifier = self.newsArticles[indexPath.row].id
            
            if let previouslyDownloadedImage = self.allImages[self.newsArticles[indexPath.row].id] {
                actualCell.spinner.stopAnimating()
                actualCell.articleImageView.image = previouslyDownloadedImage
            } else {
                
                if let actualData = CacheManager.getImage(key: self.newsArticles[indexPath.row].image) {
                    actualCell.articleImageView.image = UIImage(data: actualData)
                } else {
                    // Image hasn't been saved to cache before.
                    
                    actualCell.spinner.startAnimating()
                    let session = URLSession(configuration: .default)
                    let downloadPicTask = session.dataTask(with: URL(string: self.newsArticles[indexPath.row].image)!) { (data, response, error) in
                        if let e = error {
                            print("Error downloading picture: \(e)")
                        } else {
                            if let res = response as? HTTPURLResponse {
                                print("Downloaded picture with response code \(res.statusCode)")
                                if let imageData = data {
                                    let image = UIImage(data: imageData)
                                    // Do something with your image.
                                    DispatchQueue.main.async {
                                        actualCell.spinner.stopAnimating()
                                        actualCell.articleImageView.image = image
                                        self.allImages.updateValue(image!, forKey: self.newsArticles[indexPath.row].id)
                                        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setimage\(self.newsArticles[indexPath.row].id)"), object: nil, userInfo: ["image":image!]) as Notification)
                                        
                                        // Store image in cache.
                                        let imageSize = image!.size.height * image!.size.width
                                        let imageDownsize = 1000000 / imageSize
                                        var imageData:Data?
                                        if imageDownsize < 1 {
                                            imageData = image!.jpegData(compressionQuality: imageDownsize)!
                                        } else {
                                            imageData = image!.jpegData(compressionQuality: 1)!
                                        }
                                        if let actualImageData = imageData {
                                            CacheManager.storeImageInCache(key: self.newsArticles[indexPath.row].image, data: actualImageData)
                                        }
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
            
            return actualCell
        }
        
        return UICollectionViewCell()
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        return CGSize(width: 300, height: 200)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        self.tappedArticle = sender.accessibilityIdentifier ?? ""
        
        performSegue(withIdentifier: "InfoToArticle", sender: self)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "InfoToArticle" {
            
            let oneArticleVC = segue.destination as! ArticleViewController
            var article = Article()
            if let thisImage = self.allImages[self.tappedArticle] {
                oneArticleVC.headerImage = thisImage
            }
            article = self.everyArticle[self.tappedArticle] ?? Article()
            oneArticleVC.article = article
            
            /*if faqOrNews == "faq" {
                if let thisImage = self.faqImages[self.tappedArticle] {
                    oneArticleVC.headerImage = thisImage
                }
                article = self.faqArticles[self.tappedArticle]
            } else if faqOrNews == "signup" {
                
            } else {
                article.image = self.articles[self.tappedArticle]["image"] as? String ?? "article1"
                article.text = self.articles[self.tappedArticle]["text"] as? [NSDictionary] ?? [NSDictionary]()
            }
            oneArticleVC.article = article*/
        }
    }
    
    @objc func launchArticle(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let articleTag = userInfo["tag"] as? String {
                
                //self.faqOrNews = "signup"
                self.tappedArticle = articleTag
                
                performSegue(withIdentifier: "InfoToArticle", sender: self)
            }
        }
    }
    
}
