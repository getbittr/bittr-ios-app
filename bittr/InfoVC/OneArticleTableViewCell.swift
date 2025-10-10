//
//  OneArticleTableViewCell.swift
//  bittr
//
//  Created by Tom Melters on 17/05/2023.
//

import UIKit

class OneArticleTableViewCell: UITableViewCell {

    @IBOutlet weak var cellContentView: UIView!
    var cellTextLabel = UILabel()
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        cellTextLabel.numberOfLines = 0
        cellTextLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cellTextLabel)
        
        let textLabelTop = NSLayoutConstraint(item: cellTextLabel, attribute: .top, relatedBy: .equal, toItem: cellContentView, attribute: .top, multiplier: 1, constant: 20)
        let textLabelLeft = NSLayoutConstraint(item: cellTextLabel, attribute: .left, relatedBy: .equal, toItem: cellContentView, attribute: .left, multiplier: 1, constant: 20)
        let textLabelRight = NSLayoutConstraint(item: cellTextLabel, attribute: .right, relatedBy: .equal, toItem: cellContentView, attribute: .right, multiplier: 1, constant: -20)
        let textLabelHeight = NSLayoutConstraint(item: cellTextLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 20)
        let contentViewBottom = NSLayoutConstraint(item: cellContentView, attribute: .bottom, relatedBy: .equal, toItem: cellTextLabel, attribute: .bottom, multiplier: 1, constant: 0)
        
        cellContentView.addConstraints([textLabelTop, textLabelLeft, textLabelRight, contentViewBottom])
        cellTextLabel.addConstraint(textLabelHeight)
        
        cellContentView.layoutIfNeeded()
    }
    
    func setText(cellText:String) {
        
        let newCellText = cellText.replacingOccurrences(of: "<strong>", with: "").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        
        var textColor = "0, 0, 0"
        if CacheManager.darkModeIsOn() {
            textColor = "1, 1, 1"
        }
        
        let htmlText = newCellText.replacingOccurrences(of: "<title>", with: "<span style=\"font-family: 'Gilroy-Bold', '-apple-system'; line-height: 1.2; font-size: 26; color: rgb(\(textColor))\">").replacingOccurrences(of: "<intro>", with: "<span style=\"font-family: 'Gilroy-Bold', '-apple-system'; line-height: 1.2; font-size: 18; color: rgb(\(textColor))\">").replacingOccurrences(of: "<header>", with: "<span style=\"font-family: 'Gilroy-Bold', '-apple-system'; line-height: 1.2; font-size: 20; color: rgb(\(textColor))\">").replacingOccurrences(of: "<normal>", with: "<span style=\"font-family: 'Gilroy-Regular', '-apple-system'; line-height: 1.2; font-size: 18; color: rgb(\(textColor))\">").replacingOccurrences(of: "<subtitle>", with: "<span style=\"font-family: 'Gilroy-Bold', '-apple-system'; line-height: 1.2; font-size: 12; color: rgb(\(textColor))\">")
        
        if let htmlData = htmlText.data(using: .unicode) {
            
            do {
                let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                
                self.cellTextLabel.attributedText = attributedText
                self.cellTextLabel.textColor = Colors.getColor("blackorwhite")
            } catch {
                print("Couldn't fetch text: \(error.localizedDescription)")
            }
        }
        
        self.contentView.layoutIfNeeded()
    }

}
