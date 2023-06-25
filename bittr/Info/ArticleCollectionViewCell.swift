//
//  ArticleCollectionViewCell.swift
//  bittr
//
//  Created by Tom Melters on 12/05/2023.
//

import UIKit

class ArticleCollectionViewCell: UICollectionViewCell {
    
    @IBOutlet weak var articleCardView: UIView!
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var articleTitleLabel: UILabel!
    @IBOutlet weak var articleBlackView: UIView!
    @IBOutlet weak var articleImageView: UIImageView!
    
    override func awakeFromNib() {
        
        articleButton.setTitle("", for: .normal)
        
        articleBlackView.alpha = 0.3
        articleBlackView.layer.cornerRadius = 13
        articleCardView.layer.cornerRadius = 13
        /*articleCardView.layer.shadowColor = UIColor.black.cgColor
        articleCardView.layer.shadowOffset = CGSize(width: 0, height: 10)
        articleCardView.layer.shadowRadius = 15.0
        articleCardView.layer.shadowOpacity = 0.1*/
        articleCardView.layer.shadowColor = UIColor.black.cgColor
        articleCardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        articleCardView.layer.shadowRadius = 12.0
        articleCardView.layer.shadowOpacity = 0.05
        
        articleImageView.layer.cornerRadius = 13
    }
}
