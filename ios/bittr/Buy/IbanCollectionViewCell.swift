//
//  IbanCollectionViewCell.swift
//  bittr
//
//  Created by Tom Melters on 14/06/2023.
//

import UIKit

class IbanCollectionViewCell: UICollectionViewCell {

    // Views
    @IBOutlet weak var cardBackgroundView: UIView!
    @IBOutlet weak var cardBackgroundViewWidth: NSLayoutConstraint!
    @IBOutlet weak var yourIbanView: UIView!
    @IBOutlet weak var ibanView: UIView!
    @IBOutlet weak var nameView: UIView!
    @IBOutlet weak var codeView: UIView!
    @IBOutlet weak var emailView: UIView!
    @IBOutlet weak var paymentModeView: UIView!
    
    // Dynamic labels
    @IBOutlet weak var labelYourEmail: UILabel!
    @IBOutlet weak var labelYourIban: UILabel!
    @IBOutlet weak var labelOurIban: UILabel!
    @IBOutlet weak var labelOurName: UILabel!
    @IBOutlet weak var labelYourCode: UILabel!

    // Static labels
    @IBOutlet weak var titleYourEmail: UILabel!
    @IBOutlet weak var titleYourIBAN: UILabel!
    @IBOutlet weak var titleOurIBAN: UILabel!
    @IBOutlet weak var titleOurName: UILabel!
    @IBOutlet weak var titleYourCode: UILabel!
    @IBOutlet weak var titlePaymentMode: UILabel!
    
    // Buttons
    @IBOutlet weak var ibanButton: UIButton!
    @IBOutlet weak var nameButton: UIButton!
    @IBOutlet weak var codeButton: UIButton!
    @IBOutlet weak var paymentModeButton: UIButton!
    @IBOutlet weak var paymentModeSwitch: UISwitch!
    @IBOutlet weak var paymentModeSpinner: UIActivityIndicatorView!
    
    // Images
    @IBOutlet weak var copyIban: UIImageView!
    @IBOutlet weak var copyName: UIImageView!
    @IBOutlet weak var copyCode: UIImageView!
    
    // Variables
    var ibanEntity:IbanEntity?
    var buyVC:BuyViewController?

    override func awakeFromNib() {

        self.labelYourCode.accessibilityIdentifier = TestID.Buy.yourCode
        self.labelYourEmail.accessibilityIdentifier = TestID.Buy.yourEmail
        self.labelYourIban.accessibilityIdentifier = TestID.Buy.yourIban
        self.paymentModeSwitch.accessibilityIdentifier = TestID.Buy.paymentModeSwitch
        self.paymentModeButton.accessibilityIdentifier = TestID.Buy.paymentModeButton

        // Corner radii
        self.cardBackgroundView.layer.cornerRadius = 20
        self.yourIbanView.layer.cornerRadius = 13
        self.ibanView.layer.cornerRadius = 13
        self.nameView.layer.cornerRadius = 13
        self.codeView.layer.cornerRadius = 13
        self.emailView.layer.cornerRadius = 13
        self.paymentModeView.layer.cornerRadius = 13

        // Background card styling
        self.cardBackgroundView.setShadow()

        // Button titles
        self.ibanButton.setTitle("", for: .normal)
        self.nameButton.setTitle("", for: .normal)
        self.codeButton.setTitle("", for: .normal)
        self.paymentModeButton.setTitle("", for: .normal)

        // Colors and language
        self.changeColors()
        self.setWords()
    }
    
    @IBAction func didChangePaymentModeSwitch(_ sender: UISwitch) {
        guard self.buyVC != nil, self.ibanEntity != nil else { return }
        
        let newMode = sender.isOn ? "lightning" : "onchain"
        Log.info("Will switch payment mode to \(newMode).")

        // Disable the switch + show the spinner while the PATCH is in flight so a
        // second flip can't fire a concurrent, racing request. cellForItemAt
        // re-enables it (and stops the spinner) when the cell is reloaded with the
        // server-confirmed value, on both success and failure.
        sender.isEnabled = false
        self.paymentModeSpinner.startAnimating()
        self.buyVC!.setPaymentMode(for: self.ibanEntity!, newMode: newMode)
    }
    
    func changeColors() {

        self.labelYourEmail.textColor = Colors.getColor("blackorwhite")
        self.labelYourIban.textColor = Colors.getColor("blackorwhite")
        self.labelOurIban.textColor = Colors.getColor("blackorwhite")
        self.labelOurName.textColor = Colors.getColor("blackorwhite")
        self.labelYourCode.textColor = Colors.getColor("blackorwhite")

        self.cardBackgroundView.backgroundColor = Colors.getColor("yelloworblue2")
        self.yourIbanView.backgroundColor = Colors.getColor("whiteorblue3")
        self.ibanView.backgroundColor = Colors.getColor("whiteorblue3")
        self.nameView.backgroundColor = Colors.getColor("whiteorblue3")
        self.codeView.backgroundColor = Colors.getColor("whiteorblue3")
        self.emailView.backgroundColor = Colors.getColor("whiteorblue3")
        self.paymentModeView.backgroundColor = Colors.getColor("whiteorblue3")
        self.paymentModeSpinner.color = Colors.getColor("blackorwhite")

        self.copyIban.tintColor = Colors.getColor("blackorwhite")
        self.copyName.tintColor = Colors.getColor("blackorwhite")
        self.copyCode.tintColor = Colors.getColor("blackorwhite")
    }

    func setWords() {

        self.titleYourEmail.text = Language.getWord(withID: "youremail")
        self.titleYourIBAN.text = Language.getWord(withID: "youriban")
        self.titleOurIBAN.text = Language.getWord(withID: "ouriban")
        self.titleOurName.text = Language.getWord(withID: "ourname")
        self.titleYourCode.text = Language.getWord(withID: "yourcode")
        self.titlePaymentMode.text = Language.getWord(withID: "buyvclightning")
    }
}
