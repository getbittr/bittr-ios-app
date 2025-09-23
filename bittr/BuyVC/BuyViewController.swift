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
        self.ibanCollectionView.contentInset = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        
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
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func saveButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "IbanCell", for: indexPath) as? IbanCollectionViewCell {
            
            if self.allIbanEntities.count == 0 { return cell }
            
            cell.cardBackgroundViewWidth.constant = self.view.bounds.width - 30
            
            cell.labelYourEmail.text = self.allIbanEntities[indexPath.row].yourEmail
            cell.labelYourIban.text = self.allIbanEntities[indexPath.row].yourIbanNumber
            cell.labelOurIban.text = self.allIbanEntities[indexPath.row].ourIbanNumber
            cell.labelOurName.text = self.allIbanEntities[indexPath.row].ourName
            cell.labelYourCode.text = self.allIbanEntities[indexPath.row].yourUniqueCode
            
            cell.ibanButton.accessibilityIdentifier = self.allIbanEntities[indexPath.row].ourIbanNumber
            cell.nameButton.accessibilityIdentifier = self.allIbanEntities[indexPath.row].ourName
            cell.codeButton.accessibilityIdentifier = self.allIbanEntities[indexPath.row].yourUniqueCode
            
            return cell
        } else {
            return UICollectionViewCell()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        if self.allIbanEntities.count > 0 {
            self.emptyLabel.alpha = 0
            self.continueView.alpha = 0
            self.addAnotherViewTop.constant = 40
            self.view.layoutIfNeeded()
            
            return self.allIbanEntities.count
        } else {
            self.emptyLabel.alpha = 1
            self.continueView.alpha = 1
            self.addAnotherViewTop.constant = -100
            self.view.layoutIfNeeded()
            
            return 0
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        let viewWidth = self.view.safeAreaLayoutGuide.layoutFrame.size.width
        let cellWidth = viewWidth - 30
        return CGSize(width: cellWidth, height: 285)
    }
    
    @IBAction func continueButtonTapped(_ sender: UIButton) {
        self.performSegue(withIdentifier: "GoalToRegister", sender: self)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "GoalToRegister" {
            if let registerVC = segue.destination as? RegisterIbanViewController {
                registerVC.coreVC = self.coreVC
                self.registerIbanVC = registerVC
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
        self.emptyLabel.textColor = Colors.getColor("blackorwhite")
    }
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "buybitcoin")
        self.subtitleLabel.text = Language.getWord(withID: "buysubtitle")
        self.emptyLabel.text = Language.getWord(withID: "buyempty")
        self.addAnotherLabel.text = "+  " + Language.getWord(withID: "addanother")
    }
}
