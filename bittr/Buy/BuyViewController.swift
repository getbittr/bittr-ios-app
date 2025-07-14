//
//  BuyViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class BuyViewController: UIViewController, UITextFieldDelegate, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    // General
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var ibanCollectionView: UICollectionView!
    
    // Add another
    @IBOutlet weak var addAnotherView: UIView!
    @IBOutlet weak var addAnotherButton: UIButton!
    @IBOutlet weak var emptyLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var addAnotherLabel: UILabel!
    @IBOutlet weak var addAnotherViewTop: NSLayoutConstraint!
    
    // Continue view
    @IBOutlet weak var continueView: UIView!
    @IBOutlet weak var continueButton: UIButton!
    
    // Client details
    var allIbanEntities = [IbanEntity]()
    
    // Articles
    var coreVC:CoreViewController?
    var registerIbanVC:RegisterIbanViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii and button titles.
        self.addAnotherView.layer.cornerRadius = 13
        self.continueView.layer.cornerRadius = 13
        self.continueButton.setTitle("", for: .normal)
        self.downButton.setTitle("", for: .normal)
        self.addAnotherButton.setTitle("", for: .normal)
        
        // Collection view.
        self.ibanCollectionView.delegate = self
        self.ibanCollectionView.dataSource = self
        
        // Button border.
        let viewBorder = CAShapeLayer()
        if CacheManager.darkModeIsOn() {
            viewBorder.strokeColor = UIColor.white.cgColor
        } else {
            viewBorder.strokeColor = UIColor.black.cgColor
        }
        viewBorder.frame = self.addAnotherView.bounds
        viewBorder.fillColor = nil
        viewBorder.path = UIBezierPath(roundedRect: self.addAnotherView.bounds, cornerRadius: 13).cgPath
        viewBorder.lineWidth = 1
        self.addAnotherView.layer.addSublayer(viewBorder)
        
        // Set colors and language.
        self.changeColors()
        self.setWords()
        
        // Parse IBAN entities.
        self.parseIbanEntities()
    }
    
    func parseIbanEntities() {
        
        self.allIbanEntities = [IbanEntity]()
        
        if self.coreVC == nil {return}
        for eachIbanEntity in self.coreVC!.bittrWallet.ibanEntities {
            if eachIbanEntity.yourUniqueCode != "" {
                self.allIbanEntities += [eachIbanEntity]
            }
        }
        
        self.ibanCollectionView.reloadData()
    }
    
    override func viewDidLayoutSubviews() {
        
        let viewWidth = self.view.safeAreaLayoutGuide.layoutFrame.size.width
        let viewInset = (viewWidth - 335)/2
        ibanCollectionView.contentInset = UIEdgeInsets(top: 0, left: viewInset, bottom: 0, right: viewInset)
        self.view.layoutIfNeeded()
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func saveButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "IbanCell", for: indexPath) as? IbanCollectionViewCell
        
        if let actualCell = cell {
            
            if self.allIbanEntities.count == 0 {
                
                return actualCell
            }
            
            actualCell.labelYourEmail.text = self.allIbanEntities[indexPath.row].yourEmail
            actualCell.labelYourIban.text = self.allIbanEntities[indexPath.row].yourIbanNumber
            actualCell.labelOurIban.text = self.allIbanEntities[indexPath.row].ourIbanNumber
            actualCell.labelOurName.text = self.allIbanEntities[indexPath.row].ourName
            actualCell.labelYourCode.text = self.allIbanEntities[indexPath.row].yourUniqueCode
            
            actualCell.ibanButton.accessibilityIdentifier = self.allIbanEntities[indexPath.row].ourIbanNumber
            actualCell.nameButton.accessibilityIdentifier = self.allIbanEntities[indexPath.row].ourName
            actualCell.codeButton.accessibilityIdentifier = self.allIbanEntities[indexPath.row].yourUniqueCode
            
            return actualCell
        }
        
        return UICollectionViewCell()
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        if self.allIbanEntities.count > 0 {
            self.emptyLabel.alpha = 0
            self.continueView.alpha = 0
            self.addAnotherView.alpha = 1
            self.addAnotherButton.alpha = 1
            self.addAnotherViewTop.constant = 40
            self.view.layoutIfNeeded()
            
            return self.allIbanEntities.count
        } else {
            self.emptyLabel.alpha = 1
            self.continueView.alpha = 1
            self.addAnotherView.alpha = 0
            self.addAnotherButton.alpha = 0
            self.addAnotherViewTop.constant = -100
            self.view.layoutIfNeeded()
            
            return 0
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        return CGSize(width: 335, height: 285)
    }
    
    @IBAction func continueButtonTapped(_ sender: UIButton) {
        self.performSegue(withIdentifier: "GoalToRegister", sender: self)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "GoalToRegister" {
            
            let registerVC = segue.destination as? RegisterIbanViewController
            if let actualRegisterVC = registerVC {
                
                actualRegisterVC.coreVC = self.coreVC
                self.registerIbanVC = actualRegisterVC
            }
        }
    }

    @IBAction func copyItem(_ sender: UIButton) {
        
        UIPasteboard.general.string = sender.accessibilityIdentifier
        self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: sender.accessibilityIdentifier ?? "", buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.subtitleLabel.textColor = Colors.getColor("blackorwhite")
        self.addAnotherLabel.textColor = Colors.getColor("blackorwhite")
    }
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "buybitcoin")
        self.subtitleLabel.text = Language.getWord(withID: "buysubtitle")
        self.emptyLabel.text = Language.getWord(withID: "buyempty")
        self.addAnotherLabel.text = "+  " + Language.getWord(withID: "addanother")
    }
}
