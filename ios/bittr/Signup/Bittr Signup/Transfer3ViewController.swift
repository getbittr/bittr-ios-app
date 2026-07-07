//
//  Transfer3ViewController.swift
//  bittr
//
//  Created by Tom Melters on 09/06/2023.
//

import UIKit
import Sentry

class Transfer3ViewController: UIViewController {

    // Bittr signup successful. Show details for setting up bank transfer.
    
    // Top items
    @IBOutlet weak var checkView: UIView!
    @IBOutlet weak var topLabelOne: UILabel!
    @IBOutlet weak var topLabelTwo: UILabel!
    
    // View items
    @IBOutlet weak var ibanView: UIView!
    @IBOutlet weak var nameView: UIView!
    @IBOutlet weak var codeView: UIView!
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var nextLabel: UILabel!
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var screenshotView: UIView!
    @IBOutlet weak var screenshotButton: UIButton!
    @IBOutlet weak var screenshotLabel: UILabel!
    
    // Main labels
    @IBOutlet weak var ourIbanLabel: UILabel!
    @IBOutlet weak var yourCodeLabel: UILabel!
    @IBOutlet weak var titleOurIBAN: UILabel!
    @IBOutlet weak var titleOurName: UILabel!
    @IBOutlet weak var titleYourCode: UILabel!
    
    // Copy buttons
    @IBOutlet weak var ibanButton: UIButton!
    @IBOutlet weak var nameButton: UIButton!
    @IBOutlet weak var codeButton: UIButton!
    
    // Variables
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    var ibanVC:RegisterIbanViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Count successful Bittr signup.
        SentrySDK.metrics.count(key: "bittrsignup.success")

        // Corner radii.
        self.checkView.layer.cornerRadius = 25
        self.ibanView.layer.cornerRadius = 8
        self.nameView.layer.cornerRadius = 8
        self.codeView.layer.cornerRadius = 8
        self.nextView.layer.cornerRadius = 8
        self.screenshotView.layer.cornerRadius = 8
        self.centerView.layer.cornerRadius = 13
        self.centerView.setShadow()
        
        // Button titles.
        self.nextButton.setTitle("", for: .normal)
        self.screenshotButton.setTitle("", for: .normal)
        self.ibanButton.setTitle("", for: .normal)
        self.nameButton.setTitle("", for: .normal)
        self.codeButton.setTitle("", for: .normal)
        
        self.topLabelOne.accessibilityIdentifier = TestID.Signup.Bittr.Success.topLabelOne
        self.topLabelTwo.accessibilityIdentifier = TestID.Signup.Bittr.Success.topLabelTwo
        self.ourIbanLabel.accessibilityIdentifier = TestID.Signup.Bittr.Success.ourIbanLabel
        self.yourCodeLabel.accessibilityIdentifier = TestID.Signup.Bittr.Success.yourCodeLabel
        self.ibanButton.accessibilityIdentifier = TestID.Signup.Bittr.Success.ibanButton
        self.nameButton.accessibilityIdentifier = TestID.Signup.Bittr.Success.nameButton
        self.codeButton.accessibilityIdentifier = TestID.Signup.Bittr.Success.codeButton
        self.screenshotButton.accessibilityIdentifier = TestID.Signup.Bittr.Success.screenshotButton
        self.nextButton.accessibilityIdentifier = TestID.Signup.Bittr.Success.nextButton

        // Set colors, language, data.
        self.changeColors()
        self.setWords()
        self.updateData()
    }
    
    func updateData() {
        // Set data received from bittr API.
        let currentIbanID = self.signupVC?.currentIbanID ?? self.ibanVC!.currentIbanID
        
        for eachIbanEntity in self.coreVC!.bittrWallet.ibanEntities {
            if eachIbanEntity.id == currentIbanID {
                
                self.ourIbanLabel.text = eachIbanEntity.ourIbanNumber
                self.yourCodeLabel.text = eachIbanEntity.yourUniqueCode
                
                self.ibanButton.boundString = eachIbanEntity.ourIbanNumber
                self.nameButton.boundString = eachIbanEntity.ourName
                self.codeButton.boundString = eachIbanEntity.yourUniqueCode
            }
        }
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        self.signupVC?.moveToPage(13)
        self.ibanVC?.moveToPage(4)
    }
    
    @IBAction func screenshotButtonTapped(_ sender: UIButton) {
        
        let imageSize = UIScreen.main.bounds.size as CGSize
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 0)
        let context = UIGraphicsGetCurrentContext()
        for obj:AnyObject in UIApplication.shared.windows {
            if let window = obj as? UIWindow {
                if window.responds(to: #selector(getter: UIWindow.screen)) || window.screen == UIScreen.main {
                    context!.saveGState()
                    context!.translateBy(x: window.center.x, y: window.center.y)
                    context!.concatenate(window.transform)
                    context!.translateBy(x: -window.bounds.size.width * window.layer.anchorPoint.x, y: -window.bounds.size.height * window.layer.anchorPoint.y)
                    window.layer.render(in: context!)
                    context!.restoreGState()
                }
            }
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIImageWriteToSavedPhotosAlbum(image!, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        
        if error == nil {
            self.showAlert(presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self.ibanVC ?? self, title: Language.getWord(withID: "saved"), message: Language.getWord(withID: "screenshot2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        } else {
            self.showAlert(presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self.ibanVC ?? self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "screenshot3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    @IBAction func copyItem(_ sender: UIButton) {

        // Copy details to clipboard.
        let value = sender.boundString ?? ""
        UIPasteboard.general.string = value
        self.showAlert(presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self.ibanVC ?? self, title: Language.getWord(withID: "copied"), message: value, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    func changeColors() {
        
        self.topLabelOne.textColor = Colors.getColor("blackorwhite")
        self.topLabelTwo.textColor = Colors.getColor("blackorwhite")
        self.centerView.backgroundColor = Colors.getColor("yelloworblue1")
    }
    
    func setWords() {
        
        self.topLabelOne.text = Language.getWord(withID: "readyfortransfer")
        self.topLabelTwo.text = Language.getWord(withID: "personaldetails")
        self.titleOurIBAN.text = Language.getWord(withID: "ouriban")
        self.titleOurName.text = Language.getWord(withID: "ourname")
        self.titleYourCode.text = Language.getWord(withID: "yourcode")
        self.screenshotLabel.text = Language.getWord(withID: "screenshot")
        self.nextLabel.text = Language.getWord(withID: "finaldetails")
    }
    
}
