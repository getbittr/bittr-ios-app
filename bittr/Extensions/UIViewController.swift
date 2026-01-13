//
//  UIViewController.swift
//  bittr
//
//  Created by Tom Melters on 1/13/26.
//

import UIKit

extension UIViewController {
    
    func addHeader(iconLight:String, iconDark:String, title:String) {
        
        let headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .clear
        headerView.clipsToBounds = false
        headerView.layer.zPosition = 100
        self.view.addSubview(headerView)
        
        let headerViewTop = NSLayoutConstraint(item: headerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 0)
        let headerViewLeft = NSLayoutConstraint(item: headerView, attribute: .leading, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0)
        let headerViewRight = NSLayoutConstraint(item: headerView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
        let headerViewHeight = NSLayoutConstraint(item: headerView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 58)
        self.view.addConstraints([headerViewTop, headerViewLeft, headerViewRight])
        headerView.addConstraint(headerViewHeight)
        
        let headerIcon = UIImageView()
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        if CacheManager.darkModeIsOn() {
            headerIcon.image = UIImage(named: iconDark)
        } else {
            headerIcon.image = UIImage(named: iconLight)
        }
        headerIcon.clipsToBounds = false
        headerIcon.contentMode = .scaleAspectFit
        headerView.addSubview(headerIcon)
        
        let headerIconHeight = NSLayoutConstraint(item: headerIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 18)
        let headerIconWidth = NSLayoutConstraint(item: headerIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 18)
        let headerIconCenterY = NSLayoutConstraint(item: headerIcon, attribute: .centerY, relatedBy: .equal, toItem: headerView, attribute: .centerY, multiplier: 1, constant: 0)
        let headerIconLeft = NSLayoutConstraint(item: headerIcon, attribute: .leading, relatedBy: .equal, toItem: headerView, attribute: .leading, multiplier: 1, constant: 20)
        headerIcon.addConstraints([headerIconHeight, headerIconWidth])
        headerView.addConstraints([headerIconLeft, headerIconCenterY])
        
        
        let headerLabel = UILabel()
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.clipsToBounds = false
        headerLabel.font = UIFont(name: "Gilroy-Bold", size: 18)
        headerLabel.textColor = Colors.getColor("whiteoryellow")
        headerLabel.text = title
        headerLabel.numberOfLines = 1
        headerLabel.textAlignment = .left
        headerLabel.lineBreakMode = .byTruncatingTail
        headerLabel.backgroundColor = .clear
        headerView.addSubview(headerLabel)
        
        let headerLabelLeft = NSLayoutConstraint(item: headerLabel, attribute: .leading, relatedBy: .equal, toItem: headerIcon, attribute: .trailing, multiplier: 1, constant: 10)
        let headerLabelCenterY = NSLayoutConstraint(item: headerLabel, attribute: .centerY, relatedBy: .equal, toItem: headerIcon, attribute: .centerY, multiplier: 1, constant: 1)
        let headerLabelHeight = NSLayoutConstraint(item: headerLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        let headerLabelWidth = NSLayoutConstraint(item: headerLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        headerLabel.addConstraints([headerLabelHeight, headerLabelWidth])
        headerView.addConstraints([headerLabelLeft, headerLabelCenterY])
        
        
        let downIcon = UIImageView()
        downIcon.translatesAutoresizingMaskIntoConstraints = false
        downIcon.clipsToBounds = false
        if CacheManager.darkModeIsOn() {
            downIcon.image = UIImage(named: "downarrow32yellow")
        } else {
            downIcon.image = UIImage(named: "downarrow32")
        }
        downIcon.contentMode = .scaleAspectFit
        headerView.addSubview(downIcon)
        
        let downIconHeight = NSLayoutConstraint(item: downIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 20)
        let downIconWidth = NSLayoutConstraint(item: downIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 20)
        let downIconCenterY = NSLayoutConstraint(item: downIcon, attribute: .centerY, relatedBy: .equal, toItem: headerIcon, attribute: .centerY, multiplier: 1, constant: 0)
        let downIconRight = NSLayoutConstraint(item: downIcon, attribute: .trailing, relatedBy: .equal, toItem: headerView, attribute: .trailing, multiplier: 1, constant: -20)
        downIcon.addConstraints([downIconHeight, downIconWidth])
        headerView.addConstraints([downIconRight, downIconCenterY])
        
        
        let downButton = UIButton()
        downButton.translatesAutoresizingMaskIntoConstraints = false
        downButton.isUserInteractionEnabled = true
        downButton.setTitle("", for: .normal)
        downButton.backgroundColor = .clear
        downButton.addTarget(self, action: #selector(self.dismissVC), for: .touchUpInside)
        downButton.layer.zPosition = 100
        headerView.addSubview(downButton)
        
        let downButtonHeight = NSLayoutConstraint(item: downButton, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
        let downButtonWidth = NSLayoutConstraint(item: downButton, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
        let downButtonCenterX = NSLayoutConstraint(item: downButton, attribute: .centerX, relatedBy: .equal, toItem: downIcon, attribute: .centerX, multiplier: 1, constant: 0)
        let downButtonCenterY = NSLayoutConstraint(item: downButton, attribute: .centerY, relatedBy: .equal, toItem: downIcon, attribute: .centerY, multiplier: 1, constant: 0)
        downButton.addConstraints([downButtonHeight, downButtonWidth])
        headerView.addConstraints([downButtonCenterX, downButtonCenterY])
        
        self.view.layoutIfNeeded()
        
    }
    
    @objc func dismissVC() {
        self.view.endEditing(true)
        self.dismiss(animated: true)
    }
    
}
