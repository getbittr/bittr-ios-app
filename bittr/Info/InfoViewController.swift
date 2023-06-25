//
//  InfoViewController.swift
//  bittr
//
//  Created by Tom Melters on 21/04/2023.
//

import UIKit

class InfoViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    @IBOutlet weak var infoTableView: UITableView!
    
    @IBOutlet weak var topView: UIView!
    @IBOutlet weak var articlesCollectionView: UICollectionView!
    @IBOutlet weak var newsHeader: UIView!
    @IBOutlet weak var faqHeader: UIView!
    
    
    let questions = [["title":"How does bittr work?", "image":"article1", "text":[["text":"<title>How does Bittr work?</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"]]],["title":"Why do I want to buy bitcoin?", "image":"article2", "text":[["text":"<title>Why do I want to buy bitcoin?</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"]]],["title":"What and how does bittr charge me?", "image":"article3", "text":[["text":"<title>What and how does bittr charge me?</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"]]],["title":"Does bittr support every bank account?", "image":"article4", "text":[["text":"<title>Does bittr support every bank account?</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"]]],["title":"What is dollar cost averaging?", "image":"article5", "text":[["text":"<title>What is dollar cost averaging?</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"]]]]
    
    let articles = [["title":"Save bitcoin into your bittr lightning wallet", "image":"article6", "text":[["text":"<title>Save bitcoin into your bittr lightning wallet</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"],["text":"<header>The problems</span><br><br><normal>Googling ‘business plan’ yields over 5 billion results. That’s so much information that it’s impossible to distinguish good from bad.</span><br><br><normal>Then there are tons of templates that provide little (if any) guidance into how to fill in each blank.</span><br><br><normal>Plus every template is different and there are many different philosophies as to what a business plan should and shouldn’t contain.</span><br><br><br>"]]],["title":"The new bittr app is here!", "image":"article7", "text":[["text":"<title>The new bittr app is here!</span><br><br><subtitle>By Tom⠀•⠀August 30th, 2022</span><br><br><br><intro>We try to make it as easy as possible for you to write your business plan. Here are the problems we ran into and the solution we provide.</span><br><br><br>"]]]]
    
    var faqOrNews = ""
    var tappedArticle = 0
    
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
        
        return self.questions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "ArticleCell", for: indexPath) as? ArticleTableViewCell
        
        if let actualCell = cell {
            
            actualCell.layer.zPosition = CGFloat(indexPath.row)
            actualCell.titleLabel.text = self.questions[indexPath.row]["title"] as? String
            actualCell.articleImage.image = UIImage(named: self.questions[indexPath.row]["image"] as? String ?? "article1")
            actualCell.articleButton.tag = indexPath.row
            
            return actualCell
        }
        
        return UITableViewCell()
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.articles.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ArticleCollectionCell", for: indexPath) as? ArticleCollectionViewCell
        
        if let actualCell = cell {
            
            actualCell.articleTitleLabel.text = self.articles[indexPath.row]["title"] as? String
            actualCell.articleImageView.image = UIImage(named: self.articles[indexPath.row]["image"] as? String ?? "article1")
            actualCell.articleButton.tag = indexPath.row
            
            return actualCell
        }
        
        return UICollectionViewCell()
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        return CGSize(width: 300, height: 200)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        self.faqOrNews = sender.accessibilityIdentifier ?? "faq"
        self.tappedArticle = sender.tag
        
        performSegue(withIdentifier: "InfoToArticle", sender: self)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "InfoToArticle" {
            
            let oneArticleVC = segue.destination as! ArticleViewController
            let article = Article()
            if faqOrNews == "faq" {
                article.image = self.questions[self.tappedArticle]["image"] as? String ?? "article1"
                article.text = self.questions[self.tappedArticle]["text"] as? [NSDictionary] ?? [NSDictionary]()
            } else {
                article.image = self.articles[self.tappedArticle]["image"] as? String ?? "article1"
                article.text = self.articles[self.tappedArticle]["text"] as? [NSDictionary] ?? [NSDictionary]()
            }
            oneArticleVC.article = article
        }
    }
    
    @objc func launchArticle(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let articleTag = userInfo["tag"] as? Int {
                
                self.faqOrNews = "faq"
                self.tappedArticle = articleTag
                
                performSegue(withIdentifier: "InfoToArticle", sender: self)
            }
        }
    }
    
}
