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
    
    func changeColors() {
        
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

    // Whether the blur is already built for the current attachment. Repeated
    // "setupblur" posts are then no-ops: rebuilding a UIVisualEffectView blur
    // is an expensive filter regeneration on the main thread, and the
    // notification fans out to EVERY live instance per post (posted per
    // willDisplay, per menu navigation, per foreground) — during a wallet
    // reset's academy re-render that multiplied into a full main-thread hang
    // (watchdog kill), even after the per-instance animator-accumulation fix.
    // The blur is appearance-independent (overrideUserInterfaceStyle .light),
    // so the only event that genuinely needs a rebuild is returning from the
    // background, where iOS can drop a paused animator's effect — handled by
    // clearing the flag on willEnterForeground.
    private var isConfigured = false

    override func didMoveToSuperview() {
        guard let superview = superview else {
            // Removed from the hierarchy (removeBlur / cell reuse): stop
            // observing and kill the paused animator, so detached instances
            // don't keep doing effect work on every "setupblur" post.
            NotificationCenter.default.removeObserver(self)
            self.blurAnimator.stopAnimation(true)
            self.isConfigured = false
            return
        }
        self.backgroundColor = .clear
        self.frame = superview.bounds
        self.isConfigured = false
        self.setupBlur()

        // didMoveToSuperview can run more than once — never stack observers.
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self, selector: #selector(setupBlur), name: NSNotification.Name(rawValue: "setupblur"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(invalidateBlur), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func invalidateBlur() {
        // Backgrounding can tear down the paused animator's effect — let the
        // next "setupblur" post (SceneDelegate posts one on foregrounding)
        // rebuild it.
        self.isConfigured = false
    }

    @objc private func setupBlur() {
        // Detached instances have no business animating.
        guard self.superview != nil else { return }
        // Already built for this attachment — see isConfigured.
        guard !self.isConfigured else { return }
        self.isConfigured = true

        self.blurAnimator.stopAnimation(true)
        self.effect = nil
        self.overrideUserInterfaceStyle = .light

        // Recreate the animator instead of re-adding animation blocks to the
        // stopped one: addAnimations on a reused animator ACCUMULATES blocks,
        // and every setFractionComplete then replays the whole pile through
        // UIVisualEffectView's deferred-animation machinery on the main
        // thread.
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
