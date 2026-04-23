//
//  PlaceTableViewCell.swift
//  bittr
//
//  Created by Tom Melters on 4/23/26.
//

import UIKit

class PlaceTableViewCell: UITableViewCell {
    
    // UI elements
    @IBOutlet weak var cellCard: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var cellIcon: UIImageView!
    @IBOutlet weak var placeName: UILabel!
    @IBOutlet weak var addressStack: UIView!
    @IBOutlet weak var addressStackHeight: NSLayoutConstraint!
    @IBOutlet weak var placeAddress: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.cellCard.layer.cornerRadius = 13
        self.cellCard.setShadow()
        self.imageContainer.layer.cornerRadius = 7
        
        self.changeColors()
    }
    
    func changeColors() {
        self.cellCard.backgroundColor = Colors.getColor("whiteorblue2")
        self.imageContainer.backgroundColor = Colors.getColor("grey1orblue3")
        self.placeName.textColor = Colors.getColor("blackorwhite")
        self.placeAddress.textColor = Colors.getColor("blackorwhite")
    }
}
