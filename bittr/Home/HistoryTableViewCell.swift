//
//  HistoryTableViewCell.swift
//  bittr
//
//  Created by Tom Melters on 18/04/2023.
//

import UIKit

class HistoryTableViewCell: UITableViewCell {

    @IBOutlet weak var dateView: UIView!
    @IBOutlet weak var dayLabel: UILabel!
    @IBOutlet weak var satsLabel: UILabel!
    @IBOutlet weak var eurosLabel: UILabel!
    @IBOutlet weak var transactionButton: UIButton!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var gainView: UIView!
    @IBOutlet weak var gainLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        
        dateView.layer.cornerRadius = 7
        gainView.layer.cornerRadius = 7
        cardView.layer.cornerRadius = 13
        transactionButton.setTitle("", for: .normal)
        
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        cardView.layer.shadowRadius = 12.0
        cardView.layer.shadowOpacity = 0.05
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
