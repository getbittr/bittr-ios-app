//
//  MapVCOnePlace.swift
//  bittr
//
//  Created by Tom Melters on 4/27/26.
//

import UIKit

extension MapViewController {
    
    func showOnePlace(_ thisPlace:BitcoinPlace) {
        
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let newChild = storyboard.instantiateViewController(withIdentifier: "OnePlace")
        (newChild as? OnePlaceViewController)?.mapVC = self
        (newChild as? OnePlaceViewController)?.thisPlace = thisPlace
        
        self.addChild(newChild)
        newChild.view.frame.size = self.onePlaceContainer.frame.size
        self.onePlaceContainer.addSubview(newChild.view)
        newChild.didMove(toParent: self)
        self.onePlaceStack.alpha = 1
        self.view.layoutIfNeeded()
        
        UIView.animate(withDuration: 0.6, delay: 0.2, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: .curveEaseInOut) {
            
            let contentHeight:CGFloat = (newChild as? OnePlaceViewController)?.contentStack.bounds.height ?? 0
            
            self.onePlaceHeight.constant = contentHeight + self.view.safeAreaInsets.bottom + 20
            self.onePlaceStack.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            self.onePlaceContainerTop.constant = -contentHeight - self.view.safeAreaInsets.bottom
            self.view.layoutIfNeeded()
        }
    }
    
    func hideOnePlace() {
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            
            self.onePlaceStack.backgroundColor = UIColor.black.withAlphaComponent(0)
            self.onePlaceContainerTop.constant = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.onePlaceStack.alpha = 0
            for eachSubview in self.onePlaceContainer.subviews {
                eachSubview.removeFromSuperview()
            }
        }
    }
}
