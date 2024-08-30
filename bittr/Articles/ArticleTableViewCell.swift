//
//  ArticleTableViewCell.swift
//  bittr
//
//  Created by Tom Melters on 21/04/2023.
//

import UIKit

class ArticleTableViewCell: UITableViewCell {

    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var spinner: UIActivityIndicatorView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        cardView.layer.cornerRadius = 13
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        cardView.layer.shadowRadius = 12.0
        cardView.layer.shadowOpacity = 0.05
        
        imageContainer.layer.cornerRadius = 13
        
        articleButton.setTitle("", for: .normal)
        
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        self.changeColors()
    }
    
    @objc func changeColors() {
        
        self.cardView.backgroundColor = Colors.getColor(color: "cardview")
        self.titleLabel.textColor = Colors.getColor(color: "black")
    }

}
