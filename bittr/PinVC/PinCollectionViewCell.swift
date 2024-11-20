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
        
        cellCard.layer.cornerRadius = 13
        pinView.layer.cornerRadius = 5
    }
    
    
}
