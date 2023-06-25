//
//  IbanCollectionViewCell.swift
//  bittr
//
//  Created by Tom Melters on 14/06/2023.
//

import UIKit

class IbanCollectionViewCell: UICollectionViewCell {
    
    @IBOutlet weak var cardBackgroundView: UIView!
    @IBOutlet weak var yourIbanView: UIView!
    @IBOutlet weak var ibanView: UIView!
    @IBOutlet weak var nameView: UIView!
    @IBOutlet weak var codeView: UIView!
    @IBOutlet weak var emailView: UIView!
    
    override func awakeFromNib() {
        
        cardBackgroundView.layer.cornerRadius = 20
        yourIbanView.layer.cornerRadius = 13
        ibanView.layer.cornerRadius = 13
        nameView.layer.cornerRadius = 13
        codeView.layer.cornerRadius = 13
        emailView.layer.cornerRadius = 13
        
        cardBackgroundView.layer.shadowColor = UIColor.black.cgColor
        cardBackgroundView.layer.shadowOffset = CGSize(width: 0, height: 7)
        cardBackgroundView.layer.shadowRadius = 10.0
        cardBackgroundView.layer.shadowOpacity = 0.1
    }
    
}
