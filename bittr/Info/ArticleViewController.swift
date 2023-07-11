//
//  ArticleViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class ArticleViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    @IBOutlet weak var oneArticleTableView: UITableView!
    @IBOutlet weak var oneArticleHeaderView: UIView!
    @IBOutlet weak var oneArticleImage: UIImageView!
    @IBOutlet weak var downButton: UIButton!
    
    var article:Article?
    var headerImage = UIImage()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if article?.category == "faq" {
            article?.text.sort(by: { text1, text2 in
                (text1["order"] as! Int) < (text2["order"] as! Int)
            })
        }

        oneArticleTableView.delegate = self
        oneArticleTableView.dataSource = self
        
        oneArticleTableView.rowHeight = UITableView.automaticDimension
        
        downButton.setTitle("", for: .normal)
        
        if let actualArticle = article {
            if actualArticle.category == "General" {
                oneArticleImage.image = headerImage
            } else {
                oneArticleImage.image = UIImage(named: actualArticle.image)
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        
        if let headerView = oneArticleTableView.tableHeaderView {
            let height = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
            var headerFrame = headerView.frame
            if height != headerFrame.size.height {
                headerFrame.size.height = height
                headerView.frame = headerFrame
                oneArticleTableView.tableHeaderView = headerView
            }
        }
        
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return self.article?.text.count ?? 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "OneArticleCell", for: indexPath) as? OneArticleTableViewCell
        
        if let actualCell = cell {
            
            actualCell.setText(cellText: self.article?.text[indexPath.row]["text"] as? String ?? "")
            
            return actualCell
        }
        
        return UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        return UITableView.automaticDimension
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        
        self.dismiss(animated: true)
    }
    
}
