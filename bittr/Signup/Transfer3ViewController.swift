//
//  Transfer3ViewController.swift
//  bittr
//
//  Created by Tom Melters on 11/06/2023.
//

import UIKit

class Transfer3ViewController: UIViewController {

    // Views and buttons.
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var nextLabel: UILabel!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var backLabel: UILabel!
    
    // Scroll view.
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var centerViewCenterY: NSLayoutConstraint!
    
    // Cards
    @IBOutlet weak var amountCard: UIView!
    @IBOutlet weak var amountTitle: UILabel!
    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet weak var lightningCard: UIView!
    @IBOutlet weak var lightningTitle: UILabel!
    @IBOutlet weak var lightningLabel: UILabel!
    @IBOutlet weak var dcaCard: UIView!
    @IBOutlet weak var dcaTitle: UILabel!
    @IBOutlet weak var dcaLabel: UILabel!
    
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    var ibanVC:RegisterIbanViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii
        self.nextView.layer.cornerRadius = 13
        self.amountCard.layer.cornerRadius = 13
        self.lightningCard.layer.cornerRadius = 13
        self.dcaCard.layer.cornerRadius = 13
        
        // Button titles
        self.nextButton.setTitle("", for: .normal)
        self.backButton.setTitle("", for: .normal)
        
        // Set language and colors
        self.changeColors()
        self.setWords()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        let centerViewHeight = centerView.bounds.height
        
        if centerView.bounds.height + 40 > contentView.bounds.height {
            
            NSLayoutConstraint.deactivate([self.contentViewHeight])
            self.contentViewHeight = NSLayoutConstraint(item: self.contentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: centerViewHeight + 60)
            NSLayoutConstraint.activate([self.contentViewHeight])
            self.centerViewCenterY.constant = 0
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        let currentIbanID = self.signupVC?.currentIbanID ?? self.ibanVC!.currentIbanID
        
        for eachIbanEntity in self.coreVC!.bittrWallet.ibanEntities {
            if eachIbanEntity.id == currentIbanID {
                
                self.showAlert(presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self.ibanVC ?? self, title: Language.getWord(withID: "bankingapp"), message: "\n\(Language.getWord(withID: "bankingapp2"))\n\n\(eachIbanEntity.ourIbanNumber)\n\(eachIbanEntity.ourName)\n\(eachIbanEntity.yourUniqueCode)", buttons: [Language.getWord(withID: "done")], actions: [#selector(self.proceedToWallet)])
            }
        }
    }
    
    @objc func proceedToWallet() {
        self.hideAlert()
        
        // Hide signup
        self.coreVC!.buyVC?.registerIbanVC?.dismiss(animated: true)
        self.coreVC!.buyVC?.parseIbanEntities()
        self.coreVC!.hideSignup()
    }
    
    @IBAction func backButtonTapped(_ sender: UIButton) {
        self.signupVC?.moveToPage(12)
        self.ibanVC?.moveToPage(3)
    }
    
    func changeColors() {
        
        if CacheManager.darkModeIsOn() {
            self.backLabel.textColor = Colors.getColor("blackorwhite")
        } else {
            self.backLabel.textColor = Colors.getColor("transparentblack")
        }
        
        self.amountCard.backgroundColor = Colors.getColor("whiteorblue3")
        self.amountLabel.textColor = Colors.getColor("blackorwhite")
        self.lightningCard.backgroundColor = Colors.getColor("whiteorblue3")
        self.lightningLabel.textColor = Colors.getColor("blackorwhite")
        self.dcaCard.backgroundColor = Colors.getColor("whiteorblue3")
        self.dcaLabel.textColor = Colors.getColor("blackorwhite")

    }
    
    func setWords() {
        
        self.nextLabel.text = Language.getWord(withID: "letsgo")
        self.backLabel.text = Language.getWord(withID: "back")
        self.amountTitle.text = Language.getWord(withID: "transfer3Amount")
        self.amountLabel.text = Language.getWord(withID: "transfer3AmountLabel")
        self.lightningTitle.text = Language.getWord(withID: "transfer3Lightning")
        self.lightningLabel.text = Language.getWord(withID: "transfer3LightningLabel")
        self.dcaTitle.text = Language.getWord(withID: "transfer3DCA")
        self.dcaLabel.text = Language.getWord(withID: "transfer3DCALabel")
    }
    
}
