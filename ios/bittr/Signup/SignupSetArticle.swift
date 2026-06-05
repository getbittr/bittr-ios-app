//
//  SignupSetArticle.swift
//  bittr
//
//  Created by Tom Melters on 12/9/25.
//

import UIKit

extension UIViewController {

    func setSignupArticle(articleSlug:String, coreVC:CoreViewController, articleButton:UIButton, articleTitle:UILabel, articleImage:UIImageView, articleSpinner:UIActivityIndicatorView) -> Article? {

        guard let receivedArticle = self.getLocalArticle(articleSlug, coreVC: coreVC) else {
            Log.info("Couldn't get article: \(articleSlug)")
            return nil
        }

        articleButton.boundString = articleSlug
        articleTitle.text = receivedArticle.title
        articleImage.image = UIImage(named: articleSlug)
        articleSpinner.stopAnimating()
        return receivedArticle
    }

    func getLocalArticle(_ withSlug:String, coreVC:CoreViewController!) -> Article? {

        if let cachedArticle = coreVC.allArticles?[withSlug] {
            return cachedArticle
        }

        guard let articleData = BittrArticles.json.data(using: .utf8),
              let receivedDictionary = (try? JSONSerialization.jsonObject(with: articleData)) as? NSDictionary,
              let actualArticles = receivedDictionary["articles"] as? NSDictionary else {
            return nil
        }

        let everyArticle = self.parseArticles(articles: actualArticles)
        coreVC.allArticles = everyArticle

        return everyArticle[withSlug]
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
