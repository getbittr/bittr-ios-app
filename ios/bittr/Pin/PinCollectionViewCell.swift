//
//  PinCollectionViewCell.swift
//  bittr
//
//  Created by Tom Melters on 20/11/2024.
//

import UIKit

class PinCollectionViewCell: UICollectionViewCell {
    
    @IBOutlet weak var cellCard: UIView!
    @IBOutlet weak var pinView: UIView!
    
    override func awakeFromNib() {
        
        self.cellCard.layer.cornerRadius = 13
        self.cellCard.setShadow()
        self.pinView.layer.cornerRadius = 5
    }
    
}
