//
//  BlurEffectViewLight.swift
//  bittr
//
//  Created by Tom Melters on 25/03/2023.
//

import UIKit

class BlurEffectViewLight: UIVisualEffectView {

    /*var animator = UIViewPropertyAnimator(duration: 1, curve: .linear)
    
    override func didMoveToSuperview() {
        guard let superview = superview else { return }
        backgroundColor = .clear
        frame = superview.bounds //Or setup constraints instead
        setupBlur()
        
        //NotificationCenter.default.addObserver(self, selector: #selector(setupBlur), name: NSNotification.Name(rawValue: "setupblur"), object: nil)
    }*/
    
    /*@objc private func setupBlur() {
        animator.stopAnimation(true)
        effect = nil

        animator.addAnimations { [weak self] in
            self?.effect = UIBlurEffect(style: .regular)
        }
        animator.fractionComplete = 0.1   //This is your blur intensity in range 0 - 1
    }
    
    deinit {
        animator.stopAnimation(true)
    }*/

}
