//
//  InfoViewController.swift
//  bittr
//
//  Created by Tom Melters on 21/04/2023.
//

import UIKit
import Sentry

class InfoViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    // Views
    @IBOutlet weak var infoTableView: UITableView!
    @IBOutlet weak var topView: UIView!
    @IBOutlet weak var articlesCollectionView: UICollectionView!
    @IBOutlet weak var newsHeader: UIView!
    @IBOutlet weak var faqHeader: UIView!
    @IBOutlet weak var noArticles: UILabel!
    @IBOutlet weak var newsLabel: UILabel!
    @IBOutlet weak var questionsLabel: UILabel!
    
    // Variables
    var coreVC:CoreViewController?
    var faqArticles = [Article]()
    var newsArticles = [Article]()
    var everyArticle = [String:Article]()
    var allImages = [String:UIImage]()
    var tappedArticle = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Table and Collection views
        infoTableView.delegate = self
        infoTableView.dataSource = self
        articlesCollectionView.delegate = self
        articlesCollectionView.dataSource = self
        articlesCollectionView.contentInset = UIEdgeInsets(top: 0, left: 7, bottom: 0, right: 7)
        
        // Headers
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
        
        // Download articles.
        self.setWords()
        self.getArticles()
    }
    
    func getArticles() {
        
        // TODO: Public?
        var envUrl = "https://getbittr.com/api/articles"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envUrl = "https://getbittr.com/api/articles"
        }
        
        let request = URLRequest(url: URL(string: envUrl)!,timeoutInterval: Double.infinity)
        
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
            
            var dataDictionary:NSDictionary?
            if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                do {
                    dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                    if let actualDataDict = dataDictionary {
                        if let actualArticles = actualDataDict["articles"] as? NSDictionary {
                            
                            self.everyArticle = self.parseArticles(articles: actualArticles)
                            self.coreVC?.allArticles = self.everyArticle
                            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil, userInfo: self.everyArticle) as Notification)
                            
                            // Divide articles into two categories.
                            for (_, articledata) in self.everyArticle {
                                if articledata.category == "General", articledata.isVisible == true {
                                    self.faqArticles += [articledata]
                                } else {
                                    if articledata.isVisible == true {
                                        self.newsArticles += [articledata]
                                    }
                                }
                            }
                            
                            // Update articles table.
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
                
                Task {
                    if let actualData = await self.getImage(urlString: self.faqArticles[indexPath.row].image) {
                        DispatchQueue.main.async {
                            actualCell.spinner.stopAnimating()
                            actualCell.articleImage.image = UIImage(data: actualData)
                            self.allImages.updateValue(UIImage(data: actualData)!, forKey: self.faqArticles[indexPath.row].id)
                            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setimage\(self.faqArticles[indexPath.row].id)"), object: nil, userInfo: ["image":UIImage(data: actualData)!]) as Notification)
                        }
                    }
                }
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
                    print("Will download image.")
                    
                    Task {
                        if let actualData = await self.getImage(urlString: self.newsArticles[indexPath.row].image) {
                            DispatchQueue.main.async {
                                actualCell.spinner.stopAnimating()
                                actualCell.articleImageView.image = UIImage(data: actualData)
                                self.allImages.updateValue(UIImage(data: actualData)!, forKey: self.newsArticles[indexPath.row].id)
                                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setimage\(self.newsArticles[indexPath.row].id)"), object: nil, userInfo: ["image":UIImage(data: actualData)!]) as Notification)
                            }
                        }
                    }
                    
                    /*let session = URLSession(configuration: .default)
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
                    downloadPicTask.resume()*/
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
        }
    }
    
    func launchArticle(articleTag:String) {
        self.tappedArticle = articleTag
        performSegue(withIdentifier: "InfoToArticle", sender: self)
    }
    
}

extension UIViewController {
    
    func getImage(urlString:String) async -> Data? {
        
        do {
            var request = URLRequest(url: URL(string: urlString)!)
            request.httpMethod = "GET"
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }
            
            // Store image in cache.
            let image = UIImage(data: data)!
            let imageSize = image.size.height * image.size.width
            let imageDownsize = 1000000 / imageSize
            var imageData:Data?
            if imageDownsize < 1 {
                imageData = image.jpegData(compressionQuality: imageDownsize)!
            } else {
                imageData = image.jpegData(compressionQuality: 1)!
            }
            if let actualImageData = imageData {
                CacheManager.storeImageInCache(key: urlString, data: actualImageData)
            }
            
            return data
        } catch {
            print("Some error occurred fetching image. \(error.localizedDescription)")
            return nil
        }
    }
    
}
