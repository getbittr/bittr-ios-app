//
//  Image.swift
//  bittr
//
//  Created by Tom Melters on 10/24/25.
//

import UIKit

extension OneLessonViewController {
    
    func addImage(url:String, previousComponent:ComponentType?) {
        
        let cardView = UIView()
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.clipsToBounds = false
        cardView.backgroundColor = .white
        cardView.layer.cornerRadius = 13
        cardView.setShadow()
        self.centerView.addSubview(cardView)
        
        var topSpacing:CGFloat = 0
        if previousComponent != nil {
            switch previousComponent! {
            case .label:
                topSpacing = 20
            case .image:
                topSpacing = 30
            }
        }
        
        let cardViewTop = NSLayoutConstraint(item: cardView, attribute: .top, relatedBy: .equal, toItem: self.centerView, attribute: .top, multiplier: 1, constant: self.heightFromTop + topSpacing)
        let cardViewLeft = NSLayoutConstraint(item: cardView, attribute: .leading, relatedBy: .equal, toItem: self.centerView, attribute: .leading, multiplier: 1, constant: 30)
        let cardViewRight = NSLayoutConstraint(item: cardView, attribute: .trailing, relatedBy: .equal, toItem: self.centerView, attribute: .trailing, multiplier: 1, constant: -30)
        
        self.centerView.addConstraints([cardViewTop, cardViewLeft, cardViewRight])
        
        Task {
            let imageData = await self.getImage(urlString: url)
            
            DispatchQueue.main.async {
                if imageData != nil {
                    
                    let imageView = UIImageView()
                    imageView.translatesAutoresizingMaskIntoConstraints = false
                    imageView.clipsToBounds = true
                    imageView.layer.cornerRadius = 13
                    imageView.image = UIImage(data: imageData!)
                    cardView.addSubview(imageView)
                    
                    let imageWidth = imageView.image!.size.width
                    let imageHeight = imageView.image!.size.height
                    let HeightToWidthRatio = imageHeight/imageWidth
                    let itsViewWidth = self.centerView.bounds.size.width - 60
                    let finalImageHeight = itsViewWidth * HeightToWidthRatio
                    
                    let cardViewHeight = NSLayoutConstraint(item: cardView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: finalImageHeight)
                    
                    cardView.addConstraint(cardViewHeight)
                    
                    let imageViewTop = NSLayoutConstraint(item: imageView, attribute: .top, relatedBy: .equal, toItem: cardView, attribute: .top, multiplier: 1, constant: 0)
                    let imageViewLeft = NSLayoutConstraint(item: imageView, attribute: .leading, relatedBy: .equal, toItem: cardView, attribute: .leading, multiplier: 1, constant: 0)
                    let imageViewRight = NSLayoutConstraint(item: imageView, attribute: .trailing, relatedBy: .equal, toItem: cardView, attribute: .trailing, multiplier: 1, constant: 0)
                    let imageViewBottom = NSLayoutConstraint(item: imageView, attribute: .bottom, relatedBy: .equal, toItem: cardView, attribute: .bottom, multiplier: 1, constant: 0)
                    
                    cardView.addConstraints([imageViewTop, imageViewLeft, imageViewRight, imageViewBottom])
                    
                    self.centerView.layoutIfNeeded()
                    self.heightFromTop += (finalImageHeight + topSpacing)
                    
                    self.addNextComponent()
                } else {
                    let cardViewHeight = NSLayoutConstraint(item: cardView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 30)
                    cardView.addConstraint(cardViewHeight)
                    
                    self.centerView.layoutIfNeeded()
                    self.heightFromTop += (30 + topSpacing)
                    
                    self.addNextComponent()
                }
            }
        }
        
    }
}
