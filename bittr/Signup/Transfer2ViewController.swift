//
//  Transfer2ViewController.swift
//  bittr
//
//  Created by Tom Melters on 09/06/2023.
//

import UIKit

class Transfer2ViewController: UIViewController {

    // Bittr signup successful. Show details for setting up bank transfer.
    
    // Checkmark
    @IBOutlet weak var checkView: UIView!
    @IBOutlet weak var checkmarkImage: UIImageView!
    
    // Top labels
    @IBOutlet weak var topLabelOne: UILabel!
    @IBOutlet weak var topLabelTwo: UILabel!
    
    @IBOutlet weak var ibanView: UIView!
    @IBOutlet weak var nameView: UIView!
    @IBOutlet weak var codeView: UIView!
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var nextLabel: UILabel!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var centerViewCenterY: NSLayoutConstraint!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var screenshotView: UIView!
    @IBOutlet weak var screenshotButton: UIButton!
    @IBOutlet weak var screenshotLabel: UILabel!
    
    @IBOutlet weak var ourIbanLabel: UILabel!
    @IBOutlet weak var yourCodeLabel: UILabel!
    @IBOutlet weak var titleOurIBAN: UILabel!
    @IBOutlet weak var titleOurName: UILabel!
    @IBOutlet weak var titleYourCode: UILabel!
    
    @IBOutlet weak var ibanButton: UIButton!
    @IBOutlet weak var nameButton: UIButton!
    @IBOutlet weak var codeButton: UIButton!
    
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "when-do-i-receive-my-bitcoin"
    var pageArticle1 = Article()
    
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    var ibanVC:RegisterIbanViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii.
        self.checkView.layer.cornerRadius = 35
        self.ibanView.layer.cornerRadius = 13
        self.nameView.layer.cornerRadius = 13
        self.codeView.layer.cornerRadius = 13
        self.nextView.layer.cornerRadius = 13
        self.cardView.layer.cornerRadius = 13
        self.screenshotView.layer.cornerRadius = 13
        self.imageContainer.layer.cornerRadius = 13
        
        // Button titles.
        self.nextButton.setTitle("", for: .normal)
        self.articleButton.setTitle("", for: .normal)
        self.screenshotButton.setTitle("", for: .normal)
        self.ibanButton.setTitle("", for: .normal)
        self.nameButton.setTitle("", for: .normal)
        self.codeButton.setTitle("", for: .normal)
        
        // Checkmark elements.
        let viewBorder = CAShapeLayer()
        viewBorder.strokeColor = Colors.getColor("blackorwhite").cgColor
        viewBorder.frame = checkView.bounds
        viewBorder.fillColor = nil
        viewBorder.path = UIBezierPath(roundedRect: checkView.bounds, cornerRadius: 35).cgPath
        viewBorder.lineWidth = 2
        self.checkView.layer.addSublayer(viewBorder)
        
        self.changeColors()
        self.setWords()
        self.updateData()
        Task {
            await self.setSignupArticle(articleSlug: self.pageArticle1Slug, coreVC: self.signupVC?.coreVC ?? self.coreVC!, articleButton: self.articleButton, articleTitle: self.articleTitle, articleImage: self.articleImage, articleSpinner: self.spinner1, completion: { article in
                self.pageArticle1 = article ?? Article()
            })
        }
    }
    
    func updateData() {
        
        // Set data received from bittr API.
        let currentIbanID = self.signupVC?.currentIbanID ?? self.ibanVC!.currentIbanID
        
        for eachIbanEntity in self.coreVC!.bittrWallet.ibanEntities {
            if eachIbanEntity.id == currentIbanID {
                
                self.ourIbanLabel.text = eachIbanEntity.ourIbanNumber
                self.yourCodeLabel.text = eachIbanEntity.yourUniqueCode
                
                self.ibanButton.accessibilityIdentifier = eachIbanEntity.ourIbanNumber
                self.nameButton.accessibilityIdentifier = eachIbanEntity.ourName
                self.codeButton.accessibilityIdentifier = eachIbanEntity.yourUniqueCode
            }
        }
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        
        // Make sure data is updated
        self.updateData()
        
        let centerViewHeight = self.centerView.bounds.height
        
        if self.centerView.bounds.height + 40 > self.contentView.bounds.height {
            
            NSLayoutConstraint.deactivate([self.contentViewHeight])
            self.contentViewHeight = NSLayoutConstraint(item: self.contentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: centerViewHeight + 60)
            NSLayoutConstraint.activate([self.contentViewHeight])
            self.centerViewCenterY.constant = 0
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        self.signupVC?.moveToPage(13)
        self.ibanVC?.moveToPage(4)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        if sender.accessibilityIdentifier != nil {
            self.coreVC!.infoVC!.launchArticle(articleTag: "\(sender.accessibilityIdentifier!)")
        }
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
            self.showAlert(presentingController: self, title: Language.getWord(withID: "saved"), message: Language.getWord(withID: "screenshot2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        } else {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "screenshot3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    @IBAction func copyItem(_ sender: UIButton) {
        
        // Copy details to clipboard.
        UIPasteboard.general.string = sender.accessibilityIdentifier
        self.showAlert(presentingController: self.signupVC ?? self.ibanVC ?? self, title: Language.getWord(withID: "copied"), message: sender.accessibilityIdentifier ?? "", buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    func changeColors() {
        
        self.checkmarkImage.tintColor = Colors.getColor("blackorwhite")
        self.topLabelOne.textColor = Colors.getColor("blackorwhite")
        self.topLabelTwo.textColor = Colors.getColor("blackorwhite")
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
