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
    @IBOutlet weak var lessonImage: UIImageView!
    @IBOutlet weak var iconCheck: UIImageView!
    
    override func awakeFromNib() {
        
        // Button titles.
        self.lessonButton.setTitle("", for: .normal)
        
        // Corner radii.
        self.cardView.layer.cornerRadius = 8
        self.lessonImage.layer.cornerRadius = 8
        
        // Check icon styling.
        self.iconCheck.layer.shadowColor = UIColor(displayP3Red: 53/255, green: 154/255, blue: 71/255, alpha: 1).cgColor
        self.iconCheck.layer.shadowOffset = CGSize(width: 0, height: 2)
        self.iconCheck.layer.shadowRadius = 6
        self.iconCheck.layer.shadowOpacity = 0.2
        
        // Resistance priority.
        self.lessonTitle.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Repaint on dark-mode change, like the app's other list cells.
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        // Color management.
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
    
    @objc func changeColors() {
        
        self.lessonTitle.textColor = Colors.getColor("blackorwhite")
        
        if CacheManager.darkModeIsOn() {
            self.blurView.backgroundColor = UIColor(displayP3Red: 57/255, green: 81/255, blue: 115/255, alpha: 0.3)
        } else {
            self.blurView.backgroundColor = UIColor(displayP3Red: 235/255, green: 189/255, blue: 65/255, alpha: 0.3)
        }
    }
    
}

class BlurEffect: UIVisualEffectView {
    
    var blurAnimator = UIViewPropertyAnimator(duration: 1, curve: .linear)
    
    // The size the blur was last built at.
    private var blurredSize: CGSize?
    // Whether a rebuild is already queued for the end of the current runloop turn.
    private var blurIsScheduled = false
    
    override func didMoveToSuperview() {
        guard let superview = superview else {
            NotificationCenter.default.removeObserver(self)
            self.blurAnimator.stopAnimation(true)
            self.blurredSize = nil
            self.blurIsScheduled = false
            return
        }
        self.backgroundColor = .clear
        self.frame = superview.bounds
        self.setNeedsLayout()
        
        // didMoveToSuperview can run more than once — never stack observers.
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self, selector: #selector(setupBlur), name: NSNotification.Name(rawValue: "setupblur"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(invalidateBlur), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if self.blurredSize != self.bounds.size {
            self.scheduleBlur()
        }
    }
    
    // Runs setupBlur at the end of the current runloop turn.
    private func scheduleBlur() {
        guard !self.blurIsScheduled else { return }
        self.blurIsScheduled = true
        
        DispatchQueue.main.async { [weak self] in
            self?.blurIsScheduled = false
            self?.setupBlur()
        }
    }
    
    @objc private func invalidateBlur() {
        // Backgrounding can tear down the paused animator's effect — force one
        // rebuild on the next setupblur post / layout pass.
        self.blurredSize = nil
        self.setNeedsLayout()
    }
    
    @objc private func setupBlur() {
        // Detached instances have no business animating; a zero size isn't laid out yet.
        guard self.superview != nil, self.bounds.size != .zero else { return }
        // Already built for this size.
        guard self.blurredSize != self.bounds.size else { return }
        self.blurredSize = self.bounds.size
        
        self.blurAnimator.stopAnimation(true)
        self.effect = nil
        self.overrideUserInterfaceStyle = .light
        
        // Recreate the animator.
        self.blurAnimator = UIViewPropertyAnimator(duration: 1, curve: .linear)
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
