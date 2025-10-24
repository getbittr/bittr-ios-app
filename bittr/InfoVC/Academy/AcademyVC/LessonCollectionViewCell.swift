//
//  LessonCollectionViewCell.swift
//  bittr
//
//  Created by Tom Melters on 10/21/25.
//

import UIKit

class LessonCollectionViewCell: UICollectionViewCell {
    
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var cardWidth: NSLayoutConstraint!
    @IBOutlet weak var cardHeight: NSLayoutConstraint!
    @IBOutlet weak var lessonTitle: UILabel!
    @IBOutlet weak var lessonButton: UIButton!
    @IBOutlet weak var blurView: UIView!
    
    override func awakeFromNib() {
        
        self.lessonButton.setTitle("", for: .normal)
        self.cardView.layer.cornerRadius = 8
        self.lessonTitle.setContentCompressionResistancePriority(.required, for: .vertical)
        self.changeColors()
    }
    
    func addBlur() {
        self.removeBlur()
        self.blurView.alpha = 1
        
        let blurEffect = BlurEffect()
        blurEffect.translatesAutoresizingMaskIntoConstraints = false
        blurEffect.clipsToBounds = true
        self.blurView.addSubview(blurEffect)
        
        NSLayoutConstraint.activate([
            blurEffect.topAnchor.constraint(equalTo: self.blurView.topAnchor),
            blurEffect.leadingAnchor.constraint(equalTo: self.blurView.leadingAnchor),
            blurEffect.trailingAnchor.constraint(equalTo: self.blurView.trailingAnchor),
            blurEffect.bottomAnchor.constraint(equalTo: self.blurView.bottomAnchor)
        ])
    }
    
    func removeBlur() {
        self.blurView.alpha = 0
        for eachSubview in self.blurView.subviews {
            eachSubview.removeFromSuperview()
        }
    }
    
    func changeColors() {
        
        self.lessonTitle.textColor = Colors.getColor("blackorwhite")
        
        if CacheManager.darkModeIsOn() {
            self.blurView.backgroundColor = UIColor(displayP3Red: 60/255, green: 96/255, blue: 133/255, alpha: 0.3)
        } else {
            self.blurView.backgroundColor = UIColor(displayP3Red: 235/255, green: 189/255, blue: 65/255, alpha: 0.3)
        }
    }
    
}

class BlurEffect: UIVisualEffectView {

    var blurAnimator = UIViewPropertyAnimator(duration: 1, curve: .linear)
    
    override func didMoveToSuperview() {
        guard let superview = superview else { return }
        self.backgroundColor = .clear
        self.frame = superview.bounds
        self.setupBlur()
        
        NotificationCenter.default.addObserver(self, selector: #selector(setupBlur), name: NSNotification.Name(rawValue: "setupblur"), object: nil)
    }
    
    @objc private func setupBlur() {
        self.blurAnimator.stopAnimation(true)
        self.effect = nil
        
        self.blurAnimator.addAnimations { [weak self] in
            self?.effect = UIBlurEffect(style: .regular)
        }
        
        // Determine blur intensity.
        self.blurAnimator.fractionComplete = 0.1
    }
    
    deinit {
        self.blurAnimator.stopAnimation(true)
    }
}
