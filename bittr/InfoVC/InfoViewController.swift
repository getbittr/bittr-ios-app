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
        self.infoTableView.delegate = self
        self.infoTableView.dataSource = self
        self.articlesCollectionView.delegate = self
        self.articlesCollectionView.dataSource = self
        self.articlesCollectionView.contentInset = UIEdgeInsets(top: 0, left: 7, bottom: 0, right: 7)
        
        // Headers
        self.newsHeader.layer.cornerRadius = 13
        self.newsHeader.layer.shadowColor = UIColor.black.cgColor
        self.newsHeader.layer.shadowOffset = CGSize(width: 0, height: 5)
        self.newsHeader.layer.shadowRadius = 8.0
        self.newsHeader.layer.shadowOpacity = 0.1
        self.faqHeader.layer.cornerRadius = 13
        self.faqHeader.layer.shadowColor = UIColor.black.cgColor
        self.faqHeader.layer.shadowOffset = CGSize(width: 0, height: 5)
        self.faqHeader.layer.shadowRadius = 8.0
        self.faqHeader.layer.shadowOpacity = 0.1
        
        // Download articles.
        self.setWords()
        self.getArticles()
    }
    
    func getArticles() {
        
        if self.coreVC?.allArticles == nil {
            
            Task {
                await CallsManager.makeApiCall(url: "https://getbittr.com/api/articles", parameters: nil, getOrPost: .get) { result in
                    
                    switch result {
                    case .success(let receivedDictionary):
                        if let actualArticles = receivedDictionary["articles"] as? NSDictionary {
                            
                            self.everyArticle = self.parseArticles(articles: actualArticles)
                            self.coreVC?.allArticles = self.everyArticle
                            
                            DispatchQueue.main.async {
                                self.updateArticlesTable()
                            }
                        }
                    case .failure(let error):
                        return
                    }
                }
            }
        } else {
            self.everyArticle = self.coreVC!.allArticles!
            self.updateArticlesTable()
        }
    }
    
    func updateArticlesTable() {
        
        for (_, articledata) in self.everyArticle {
            if articledata.category == "General", articledata.isVisible {
                self.faqArticles += [articledata]
            } else {
                if articledata.isVisible {
                    self.newsArticles += [articledata]
                }
            }
        }
        
        // Update articles table.
        self.faqArticles.sort { article1, article2 in
            article1.order < article2.order
        }
        self.newsArticles.sort { article1, article2 in
            article1.order < article2.order
        }
        self.infoTableView.reloadData()
        self.articlesCollectionView.reloadData()
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
                            }
                        }
                    }
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
            article = self.coreVC?.allArticles?[self.tappedArticle] ?? Article()
            oneArticleVC.article = article
        }
    }
    
}

extension UIViewController {
    
    func getImage(urlString:String) async -> Data? {
        
        do {
            var request = URLRequest(url: URL(string: urlString)!)
            request.httpMethod = "GET"
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard response is HTTPURLResponse else {
                return nil
            }
            
            // Store image in cache.
            let image = UIImage(data: data)!
            CacheManager.storeImageInCache(key: urlString, data: image.resizeImage())
            
            return image.resizeImage()
        } catch {
            print("Some error occurred fetching image. \(error.localizedDescription)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "InfoViewController row 294", key: "context")
                }
            }
            if let actualData = CacheManager.getImage(key: urlString) {
                return actualData
            } else {
                return nil
            }
        }
    }
    
}

extension UIImage {
    
    func resizeImage() -> Data {
        
        // Don't enlarge the image.
        if 1080 > self.size.width {
            print("Image is narrower than 1080 pixels. No need to resize.")
            return self.jpegData(compressionQuality: 1)!
        }
        
        // Check the current ratio.
        let widthRatio = 1080 / self.size.width
        
        // Calculate new size.
        let newSize = CGSize(width: self.size.width * widthRatio, height: self.size.height * widthRatio)
        
        // This is the rect that we've calculated out and this is what is actually used below
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        // Actually do the resizing to the rect using the ImageContext stuff
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: rect)
        var newImage = UIGraphicsGetImageFromCurrentImageContext()
        if newImage == nil {
            print("Image could not be downsized.")
            newImage = self
        }
        UIGraphicsEndImageContext()
        
        return newImage!.jpegData(compressionQuality: 1)!
    }
}
