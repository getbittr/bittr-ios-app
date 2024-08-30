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
    
    @IBOutlet weak var labelYourEmail: UILabel!
    @IBOutlet weak var labelYourIban: UILabel!
    @IBOutlet weak var labelOurIban: UILabel!
    @IBOutlet weak var labelOurName: UILabel!
    @IBOutlet weak var labelYourCode: UILabel!
    
    @IBOutlet weak var ibanButton: UIButton!
    @IBOutlet weak var nameButton: UIButton!
    @IBOutlet weak var codeButton: UIButton!
    
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
        
        ibanButton.setTitle("", for: .normal)
        nameButton.setTitle("", for: .normal)
        codeButton.setTitle("", for: .normal)
        
        self.changeColors()
    }
    
    func changeColors() {
        
        self.labelYourEmail.textColor = Colors.getColor(color: "black")
        self.labelYourIban.textColor = Colors.getColor(color: "black")
        self.labelOurIban.textColor = Colors.getColor(color: "black")
        self.labelOurName.textColor = Colors.getColor(color: "black")
        self.labelYourCode.textColor = Colors.getColor(color: "black")
        
        self.cardBackgroundView.backgroundColor = Colors.getColor(color: "cardbackground")
        yourIbanView.backgroundColor = Colors.getColor(color: "whiteorlightblue")
        ibanView.backgroundColor = Colors.getColor(color: "whiteorlightblue")
        nameView.backgroundColor = Colors.getColor(color: "whiteorlightblue")
        codeView.backgroundColor = Colors.getColor(color: "whiteorlightblue")
        emailView.backgroundColor = Colors.getColor(color: "whiteorlightblue")
    }
}
