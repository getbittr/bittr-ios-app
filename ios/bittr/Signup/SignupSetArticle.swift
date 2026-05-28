//
//  SignupSetArticle.swift
//  bittr
//
//  Created by Tom Melters on 12/9/25.
//

import UIKit

extension UIViewController {

    func setSignupArticle(articleSlug:String, coreVC:CoreViewController, articleButton:UIButton, articleTitle:UILabel, articleImage:UIImageView, articleSpinner:UIActivityIndicatorView, completion: @escaping (Article?) -> Void) async {

        await self.getArticle(articleSlug, coreVC: coreVC) { result in

            switch result {
            case .success(let receivedArticle):
                articleButton.boundString = articleSlug
                articleTitle.text = receivedArticle.title
                articleImage.setArticleImage(url: receivedArticle.image, coreVC: coreVC, imageSpinner: articleSpinner)
                completion(receivedArticle)
            case .failure(let receivedError):
                Log.info("Couldn't get article: \(receivedError)")
                completion(nil)
            }
        }
    }
    
    func getArticle(_ withSlug:String, coreVC:CoreViewController!, completion: @escaping (Result<Article, String>) -> Void) async {
        
        if coreVC.allArticles?[withSlug] != nil {
            return completion(.success(coreVC.allArticles![withSlug]!))
        } else {
            Task {
                await CallsManager.makeApiCall(url: "https://getbittr.com/api/articles", parameters: nil, getOrPost: .get) { result in
                    
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
                        self.image = UIImage(data: actualData)
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
