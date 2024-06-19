//
//  BuyViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class BuyViewController: UIViewController, UITextFieldDelegate, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    @IBOutlet weak var downButton: UIButton!
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    
    @IBOutlet weak var headerView2: UIView!
    @IBOutlet weak var ibanCollectionView: UICollectionView!
    @IBOutlet weak var addAnotherView: UIView!
    @IBOutlet weak var addAnotherButton: UIButton!
    @IBOutlet weak var emptyLabel: UILabel!
    
    var client = Client()
    var articles:[String:Article]?
    var allImages:[String:UIImage]?
    
    var allIbanEntities = [IbanEntity]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        headerView2.layer.cornerRadius = 13
        
        downButton.setTitle("", for: .normal)
        addAnotherButton.setTitle("", for: .normal)
        
        ibanCollectionView.delegate = self
        ibanCollectionView.dataSource = self
        
        addAnotherView.layer.cornerRadius = 13
        let viewBorder = CAShapeLayer()
        viewBorder.strokeColor = UIColor.black.cgColor
        viewBorder.frame = addAnotherView.bounds
        viewBorder.fillColor = nil
        viewBorder.path = UIBezierPath(roundedRect: addAnotherView.bounds, cornerRadius: 13).cgPath
        viewBorder.lineWidth = 1
        addAnotherView.layer.addSublayer(viewBorder)
        
        NotificationCenter.default.addObserver(self, selector: #selector(resetClient), name: NSNotification.Name(rawValue: "restorewallet"), object: nil)
        
        self.parseIbanEntities()
    }
    
    func parseIbanEntities() {
        
        allIbanEntities = [IbanEntity]()
        
        for eachIbanEntity in self.client.ibanEntities {
            if eachIbanEntity.yourUniqueCode != "" {
                self.allIbanEntities += [eachIbanEntity]
            }
        }
        
        self.ibanCollectionView.reloadData()
    }
    
    @objc func resetClient() {
        
        var envKey = "proddevice"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "device"
        }
        
        let deviceDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary
        if let actualDeviceDict = deviceDict {
            // Client exists in cache.
            let clients:[Client] = CacheManager.parseDevice(deviceDict: actualDeviceDict)
            self.client = clients[0]
            //self.ibanCollectionView.reloadData()
            self.parseIbanEntities()
        }
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
        
        if /*self.client.ibanEntities.count*/ self.allIbanEntities.count > 0 {
            self.emptyLabel.alpha = 0
            return self.allIbanEntities.count
        }
        
        self.emptyLabel.alpha = 1
        return 0
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        return CGSize(width: 335, height: 285)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "GoalToRegister" {
            
            let registerVC = segue.destination as? RegisterIbanViewController
            if let actualRegisterVC = registerVC {
                
                actualRegisterVC.currentClientID = self.client.id
                if let actualArticles = self.articles {
                    actualRegisterVC.articles = actualArticles
                }
                if let actualImages = self.allImages {
                    actualRegisterVC.allImages = actualImages
                }
            }
        }
    }

    @IBAction func copyItem(_ sender: UIButton) {
        
        UIPasteboard.general.string = sender.accessibilityIdentifier
        let alert = UIAlertController(title: "Copied", message: sender.accessibilityIdentifier, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
}
