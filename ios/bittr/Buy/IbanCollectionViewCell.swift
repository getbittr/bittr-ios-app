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
    
    // Buttons
    @IBOutlet weak var ibanButton: UIButton!
    @IBOutlet weak var nameButton: UIButton!
    @IBOutlet weak var codeButton: UIButton!
    
    // Images
    @IBOutlet weak var copyIban: UIImageView!
    @IBOutlet weak var copyName: UIImageView!
    @IBOutlet weak var copyCode: UIImageView!

    // MARK: - Payment-mode toggle (built programmatically; the card is storyboard-based)

    let paymentModeView = UIView()
    let payoutTitleLabel = UILabel()
    let lightningPill = UIButton(type: .system)
    let onchainPill = UIButton(type: .system)

    /// Current payout mode shown by the toggle ("lightning" / "onchain" / "" when unknown).
    private(set) var currentPaymentMode = ""
    /// Called when the user taps a different pill. The owning VC performs the PATCH and
    /// re-configures the cell from the resulting (server-confirmed) state.
    var onPaymentModeChange: ((String) -> Void)?

    override func awakeFromNib() {

        self.labelYourCode.accessibilityIdentifier = TestID.Buy.yourCode
        self.labelYourEmail.accessibilityIdentifier = TestID.Buy.yourEmail
        self.labelYourIban.accessibilityIdentifier = TestID.Buy.yourIban

        // Corner radii
        self.cardBackgroundView.layer.cornerRadius = 20
        self.yourIbanView.layer.cornerRadius = 13
        self.ibanView.layer.cornerRadius = 13
        self.nameView.layer.cornerRadius = 13
        self.codeView.layer.cornerRadius = 13
        self.emailView.layer.cornerRadius = 13
        
        // Background card styling
        self.cardBackgroundView.setShadow()
        
        // Button titles
        self.ibanButton.setTitle("", for: .normal)
        self.nameButton.setTitle("", for: .normal)
        self.codeButton.setTitle("", for: .normal)

        // Payment-mode toggle (must exist before changeColors/setWords style it)
        self.setupPaymentModeToggle()

        // Colors and language
        self.changeColors()
        self.setWords()
    }

    // MARK: - Payment-mode toggle

    private func setupPaymentModeToggle() {

        paymentModeView.translatesAutoresizingMaskIntoConstraints = false
        paymentModeView.layer.cornerRadius = 13
        cardBackgroundView.addSubview(paymentModeView)

        payoutTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        payoutTitleLabel.font = self.titleYourCode.font
        paymentModeView.addSubview(payoutTitleLabel)

        let pillStack = UIStackView(arrangedSubviews: [lightningPill, onchainPill])
        pillStack.translatesAutoresizingMaskIntoConstraints = false
        pillStack.axis = .horizontal
        pillStack.distribution = .fillEqually
        pillStack.spacing = 8
        paymentModeView.addSubview(pillStack)

        for (tag, pill) in [lightningPill, onchainPill].enumerated() {
            pill.tag = tag // 0 = lightning, 1 = onchain
            pill.titleLabel?.font = self.labelYourCode.font
            pill.layer.cornerRadius = 10
            pill.addTarget(self, action: #selector(paymentPillTapped(_:)), for: .touchUpInside)
        }

        // Anchor the toggle below the deposit-code section. No bottom pin to the card
        // (kept .defaultLow-free) so it can't conflict with the storyboard constraints;
        // the cell height is enlarged in BuyViewController.sizeForItemAt to make room.
        NSLayoutConstraint.activate([
            paymentModeView.topAnchor.constraint(equalTo: codeView.bottomAnchor, constant: 12),
            paymentModeView.leadingAnchor.constraint(equalTo: codeView.leadingAnchor),
            paymentModeView.trailingAnchor.constraint(equalTo: codeView.trailingAnchor),
            paymentModeView.heightAnchor.constraint(equalToConstant: 68),

            payoutTitleLabel.topAnchor.constraint(equalTo: paymentModeView.topAnchor, constant: 8),
            payoutTitleLabel.leadingAnchor.constraint(equalTo: paymentModeView.leadingAnchor, constant: 12),
            payoutTitleLabel.trailingAnchor.constraint(equalTo: paymentModeView.trailingAnchor, constant: -12),

            pillStack.leadingAnchor.constraint(equalTo: paymentModeView.leadingAnchor, constant: 12),
            pillStack.trailingAnchor.constraint(equalTo: paymentModeView.trailingAnchor, constant: -12),
            pillStack.bottomAnchor.constraint(equalTo: paymentModeView.bottomAnchor, constant: -8),
            pillStack.topAnchor.constraint(equalTo: payoutTitleLabel.bottomAnchor, constant: 6)
        ])
    }

    /// Set the toggle to reflect a server-confirmed mode ("lightning" / "onchain" / "").
    func configurePaymentMode(_ mode: String) {
        self.currentPaymentMode = mode
        self.stylePills()
    }

    private func stylePills() {
        let yellow = Colors.getColor("yellow")
        let blackOrWhite = Colors.getColor("blackorwhite")

        let lightningSelected = (currentPaymentMode == "lightning")
        let onchainSelected = (currentPaymentMode == "onchain")

        lightningPill.backgroundColor = lightningSelected ? yellow : .clear
        onchainPill.backgroundColor = onchainSelected ? yellow : .clear
        lightningPill.setTitleColor(blackOrWhite, for: .normal)
        onchainPill.setTitleColor(blackOrWhite, for: .normal)
    }

    @objc private func paymentPillTapped(_ sender: UIButton) {
        let newMode = sender.tag == 0 ? "lightning" : "onchain"
        if newMode == currentPaymentMode { return }
        // Optimistically reflect the tap; the VC re-configures us from the server result
        // (and reverts on failure) once the PATCH completes.
        configurePaymentMode(newMode)
        onPaymentModeChange?(newMode)
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
        
        self.copyIban.tintColor = Colors.getColor("blackorwhite")
        self.copyName.tintColor = Colors.getColor("blackorwhite")
        self.copyCode.tintColor = Colors.getColor("blackorwhite")

        self.paymentModeView.backgroundColor = Colors.getColor("whiteorblue3")
        self.payoutTitleLabel.textColor = Colors.getColor("blackorwhite")
        self.stylePills()
    }

    func setWords() {

        self.titleYourEmail.text = Language.getWord(withID: "youremail")
        self.titleYourIBAN.text = Language.getWord(withID: "youriban")
        self.titleOurIBAN.text = Language.getWord(withID: "ouriban")
        self.titleOurName.text = Language.getWord(withID: "ourname")
        self.titleYourCode.text = Language.getWord(withID: "yourcode")

        // TODO: localize these via Language.getWord once the keys are added to Language.swift
        // (kept as literals here to avoid a blind multi-language edit in this PR).
        self.payoutTitleLabel.text = "Payout to"
        self.lightningPill.setTitle("⚡ Lightning", for: .normal)
        self.onchainPill.setTitle("⛓ On-chain", for: .normal)
    }
}
