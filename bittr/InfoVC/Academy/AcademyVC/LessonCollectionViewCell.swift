//
//  LessonCollectionViewCell.swift
//  bittr
//
//  Created by Tom Melters on 10/21/25.
//

import UIKit

class LessonCollectionViewCell: UICollectionViewCell {
    
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var cardWidth: NSLayoutConstraint!
    @IBOutlet weak var cardHeight: NSLayoutConstraint!
    @IBOutlet weak var lessonTitle: UILabel!
    @IBOutlet weak var lessonButton: UIButton!
    
    override func awakeFromNib() {
        
        self.lessonButton.setTitle("", for: .normal)
        self.cardView.layer.cornerRadius = 8
        self.lessonTitle.setContentCompressionResistancePriority(.required, for: .vertical)
        self.changeColors()
    }
    
    func changeColors() {
        self.lessonTitle.textColor = Colors.getColor("blackorwhite")
    }
    
}
