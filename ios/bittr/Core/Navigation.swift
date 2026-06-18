//
//  Navigation.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension CoreViewController {

    @IBAction func menuButtonTapped(_ sender: UIButton) {
        
        if sender.tag == 1 {
            if self.infoContainerView.subviews.count > 0 {
                // Academy is already in view.
                return
            } else {
                // Load Academy.
                self.loadInfoVC()
            }
        }
        
        let menuViews:[UIView] = [self.walletView, self.academyView, self.settingsView]
        let menuConstraint = menuViews[sender.tag]
        let leadingConstant = CGFloat(sender.tag * -1) * self.view.safeAreaLayoutGuide.layoutFrame.size.width
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            
            // Selected menu item.
            NSLayoutConstraint.deactivate([self.selectedViewLeading, self.selectedViewTrailing])
            self.selectedViewLeading = NSLayoutConstraint(item: self.selectedView, attribute: .leading, relatedBy: .equal, toItem: menuConstraint, attribute: .leading, multiplier: 1, constant: 0)
            self.selectedViewTrailing = NSLayoutConstraint(item: self.selectedView, attribute: .trailing, relatedBy: .equal, toItem: menuConstraint, attribute: .trailing, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.selectedViewLeading, self.selectedViewTrailing])
            
            // Container view.
            self.homeContainerViewLeading.constant = leadingConstant
            self.homeContainerViewTrailing.constant = leadingConstant
            
            self.view.layoutIfNeeded()
        } completion: { _ in
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setupblur"), object: nil, userInfo: nil) as Notification)
            if sender.tag != 1 {
                self.hideInfoVC()
            }
        }
    }
    
    
    func loadInfoVC() {
        
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let newChild = storyboard.instantiateViewController(withIdentifier: "Academy")
        if let newChild = newChild as? AcademyViewController {
            newChild.coreVC = self
        }
        
        self.addChild(newChild)
        newChild.view.frame.size = self.infoContainerView.frame.size
        self.infoContainerView.addSubview(newChild.view)
        newChild.didMove(toParent: self)
    }
    
    func hideInfoVC() {
        if self.infoContainerView.subviews.count > 0 {
            for eachSubview in self.infoContainerView.subviews {
                eachSubview.removeFromSuperview()
            }
        }
    }
    
    
    func launchArticle(articleTag:String) {
        self.tappedArticle = articleTag
        performSegue(withIdentifier: "CoreToArticle", sender: self)
    }
    
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "CoreToSettings" {
            if let settingsVC = segue.destination as? SettingsViewController {
                settingsVC.coreVC = self
                self.settingsVC = settingsVC
            }
        } else if segue.identifier == "CoreToPin" {
            if let pinVC = segue.destination as? PinViewController {
                pinVC.coreVC = self
            }
        } else if segue.identifier == "CoreToHome" {
            if let homeVC = segue.destination as? HomeViewController {
                homeVC.coreVC = self
                self.homeVC = homeVC
            }
        } else if segue.identifier == "CoreToQuestion" {
            if let questionVC = segue.destination as? QuestionViewController {
                questionVC.headerText = self.tappedQuestion
                questionVC.answerText = self.tappedAnswer
                questionVC.coreVC = self
                questionVC.questionType = self.tappedType
            }
        } else if segue.identifier == "CoreToArticle" {
            if let oneArticleVC = segue.destination as? ArticleViewController, self.tappedArticle != nil {
                let article = self.allArticles?[self.tappedArticle!] ?? Article()
                oneArticleVC.article = article
            }
        } else if segue.identifier == "CoreToSwap" {
            if let swapVC = segue.destination as? SwapViewController {
                self.swapVC = swapVC
                swapVC.coreVC = self
                swapVC.isFromLightningPayment = self.isFromLightningPayment
                swapVC.pendingLightningInvoice = self.pendingLightningInvoice
                swapVC.pendingOnchainAmount = self.pendingSuggestedSwapAmount
                self.isFromLightningPayment = false
                self.pendingLightningInvoice = ""
                self.pendingSuggestedSwapAmount = 0
            }
        } else if segue.identifier == "CoreToAnimation" {
            if let animationVC = segue.destination as? AnimationViewController {
                animationVC.coreVC = self
            }
        }
    }
    
    func showSettings() {
        
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let newChild = storyboard.instantiateViewController(withIdentifier: "SettingsVC")
        (newChild as? SettingsViewController)?.coreVC = self
        
        self.addChild(newChild)
        newChild.view.frame.size = self.settingsContainer.frame.size
        self.settingsContainer.addSubview(newChild.view)
        newChild.didMove(toParent: self)
        
        self.settingsBackground.alpha = 1
        self.view.layoutIfNeeded()

        // Compute the open position once (after layout) and remember it — the
        // swipe-to-dismiss handler clamps against and snaps back to it.
        let contentHeight:CGFloat = (newChild as? SettingsViewController)?.centerView.bounds.height ?? 0
        self.settingsOpenConstant = -contentHeight - self.view.safeAreaInsets.bottom

        UIView.animate(withDuration: 0.6, delay: 0.2, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: .curveEaseInOut) {
            self.settingsBackground.backgroundColor = .black.withAlphaComponent(0.5)
            self.settingsContainerTop.constant = self.settingsOpenConstant
            self.view.layoutIfNeeded()
        }
    }

    // Drag the open settings popup down to dismiss it (Option A: interactive).
    // The popup is positioned by settingsContainerTop (open = settingsOpenConstant,
    // a negative value; closed = 0), so we track the finger by adding the
    // downward translation to the open constant, then either complete the
    // dismissal or spring back depending on distance/velocity.
    @objc func handleSettingsPan(_ recognizer: UIPanGestureRecognizer) {
        // Only active while the popup is actually open.
        guard !self.settingsContainer.subviews.isEmpty else { return }

        let translationY = recognizer.translation(in: self.settingsContainer).y
        let contentHeight = -self.settingsOpenConstant   // open constant is negative

        switch recognizer.state {
        case .changed:
            // Only allow dragging downward (toward closed) from the open position.
            let offset = max(0, translationY)
            self.settingsContainerTop.constant = self.settingsOpenConstant + offset
            // Fade the dim out as the sheet is pulled down.
            let progress = contentHeight > 0 ? min(1, offset / contentHeight) : 0
            self.settingsBackground.backgroundColor = .black.withAlphaComponent(0.5 * (1 - progress))
            self.view.layoutIfNeeded()
        case .ended, .cancelled, .failed:
            let velocityY = recognizer.velocity(in: self.settingsContainer).y
            if translationY > contentHeight / 3 || velocityY > 800 {
                self.hideSettings()
            } else {
                // Not far/fast enough — spring back to the open position.
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                    self.settingsContainerTop.constant = self.settingsOpenConstant
                    self.settingsBackground.backgroundColor = .black.withAlphaComponent(0.5)
                    self.view.layoutIfNeeded()
                }
            }
        default:
            break
        }
    }

    func hideSettings() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            self.settingsBackground.backgroundColor = UIColor(red: 138/255, green: 111/255, blue: 81/255, alpha: 0)
            self.settingsContainerTop.constant = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.settingsBackground.alpha = 0
            for eachSubview in self.settingsContainer.subviews {
                eachSubview.removeFromSuperview()
            }
        }
    }

}

extension CoreViewController: UIGestureRecognizerDelegate {
    // Let the settings-popup swipe-to-dismiss pan run alongside the settings
    // table's scroll pan, so a downward drag started on a row still dismisses.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
