//
//  GoalViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class GoalViewController: UIViewController, UITextFieldDelegate, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    @IBOutlet weak var headerView: UIView!
    
    @IBOutlet weak var euroView: UIView!
    @IBOutlet weak var amountView: UIView!
    @IBOutlet weak var weekView: UIView!
    @IBOutlet weak var downButton: UIButton!
    
    @IBOutlet weak var euroTextField: UITextField!
    @IBOutlet weak var euroButton: UIButton!
    @IBOutlet weak var amountTextField: UITextField!
    @IBOutlet weak var amountButton: UIButton!
    @IBOutlet weak var weekLabel: UILabel!
    @IBOutlet weak var weekButton: UIButton!
    @IBOutlet weak var saveView: UIView!
    @IBOutlet weak var saveButton: UIButton!
    
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

        headerView.layer.cornerRadius = 13
        euroView.layer.cornerRadius = 13
        amountView.layer.cornerRadius = 13
        weekView.layer.cornerRadius = 13
        saveView.layer.cornerRadius = 13
        
        headerView2.layer.cornerRadius = 13
        
        downButton.setTitle("", for: .normal)
        euroButton.setTitle("", for: .normal)
        amountButton.setTitle("", for: .normal)
        weekButton.setTitle("", for: .normal)
        saveButton.setTitle("", for: .normal)
        addAnotherButton.setTitle("", for: .normal)
        
        euroTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        amountTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        euroTextField.delegate = self
        amountTextField.delegate = self
        
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
        
        for eachIbanEntity in self.client.ibanEntities {
            if eachIbanEntity.yourUniqueCode != "" {
                self.allIbanEntities += [eachIbanEntity]
            }
        }
        
        self.ibanCollectionView.reloadData()
    }
    
    @objc func resetClient() {
        let deviceDict = UserDefaults.standard.value(forKey: "device") as? NSDictionary
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
    
    @objc func doneButtonTapped() {
        self.view.endEditing(true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
        
    }
    
    @objc func keyboardWillDisappear() {
        
        self.euroButton.alpha = 1
        self.amountButton.alpha = 1
        
        NSLayoutConstraint.deactivate([contentViewBottom])
        contentViewBottom = NSLayoutConstraint(item: contentView!, attribute: .bottom, relatedBy: .equal, toItem: scrollView, attribute: .bottom, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([contentViewBottom])
        
        self.view.layoutIfNeeded()
    }
    
    @objc func keyboardWillAppear(_ notification:Notification) {
        
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            let keyboardHeight = keyboardSize.height
            
            NSLayoutConstraint.deactivate([contentViewBottom])
            contentViewBottom = NSLayoutConstraint(item: contentView!, attribute: .bottom, relatedBy: .equal, toItem: scrollView, attribute: .bottom, multiplier: 1, constant: -keyboardHeight)
            NSLayoutConstraint.activate([contentViewBottom])
            
            self.view.layoutIfNeeded()
        }
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        
        if self.amountTextField.text != "1" {
            if self.weekLabel.text == "day" {
                self.weekLabel.text = "days"
            } else if self.weekLabel.text == "week" {
                self.weekLabel.text = "weeks"
            } else if self.weekLabel.text == "month" {
                self.weekLabel.text = "months"
            } else if self.weekLabel.text == "year" {
                self.weekLabel.text = "years"
            }
        } else {
            if self.weekLabel.text == "days" {
                self.weekLabel.text = "day"
            } else if self.weekLabel.text == "weeks" {
                self.weekLabel.text = "week"
            } else if self.weekLabel.text == "months" {
                self.weekLabel.text = "month"
            } else if self.weekLabel.text == "years" {
                self.weekLabel.text = "year"
            }
        }
    }
    
    @IBAction func euroButtonTapped(_ sender: UIButton) {
        
        self.euroTextField.becomeFirstResponder()
        self.euroButton.alpha = 0
    }
    
    @IBAction func amountButtonTapped(_ sender: UIButton) {
        
        self.amountTextField.becomeFirstResponder()
        self.amountButton.alpha = 0
    }
    
    @IBAction func weekButtonTapped(_ sender: UIButton) {
        
        var day = "day"
        var week = "week"
        var month = "month"
        var year = "year"
        
        if self.amountTextField.text != "1" {
            day = day + "s"
            week = week + "s"
            month = month + "s"
            year = year + "s"
        }
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let dayOption = UIAlertAction(title: day, style: .default) { (action) in
            self.weekLabel.text = day
        }
        let weekOption = UIAlertAction(title: week, style: .default) { (action) in
            self.weekLabel.text = week
        }
        let monthOption = UIAlertAction(title: month, style: .default) { (action) in
            self.weekLabel.text = month
        }
        let yearOption = UIAlertAction(title: year, style: .default) { (action) in
            self.weekLabel.text = year
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        actionSheet.addAction(dayOption)
        actionSheet.addAction(weekOption)
        actionSheet.addAction(monthOption)
        actionSheet.addAction(yearOption)
        actionSheet.addAction(cancelAction)
        present(actionSheet, animated: true, completion: nil)
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
