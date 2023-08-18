//
//  ReceiveViewController.swift
//  bittr
//
//  Created by Tom Melters on 05/05/2023.
//

import UIKit
import CoreImage.CIFilterBuiltins
import CodeScanner

class ReceiveViewController: UIViewController {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var qrView: UIView!
    @IBOutlet weak var addressView: UIView!
    @IBOutlet weak var refreshView: UIView!
    
    @IBOutlet weak var addressLabel: UILabel!
    @IBOutlet weak var addressCopy: UIImageView!
    @IBOutlet weak var addressSpinner: UIActivityIndicatorView!
    @IBOutlet weak var qrcodeSpinner: UIActivityIndicatorView!
    @IBOutlet weak var qrCodeImage: UIImageView!
    @IBOutlet weak var copyAddressButton: UIButton!
    @IBOutlet weak var refreshButton: UIButton!
    let addressViewModel = AddressViewModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        downButton.setTitle("", for: .normal)
        copyAddressButton.setTitle("", for: .normal)
        refreshButton.setTitle("", for: .normal)
        headerView.layer.cornerRadius = 13
        qrView.layer.cornerRadius = 13
        addressView.layer.cornerRadius = 13
        refreshView.layer.cornerRadius = 13
        
        NotificationCenter.default.addObserver(self, selector: #selector(setNewAddress), name: NSNotification.Name(rawValue: "setnewaddress"), object: nil)
        
        addressCopy.alpha = 0
        qrCodeImage.alpha = 0
        addressLabel.text = ""
        addressSpinner.startAnimating()
        qrcodeSpinner.startAnimating()
        getNewAddress()
    }
    
    func getNewAddress() {
        Task {
            await addressViewModel.newFundingAddress()
        }
    }
    
    @objc func setNewAddress(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let newAddress = userInfo["address"] as? String {
                self.addressLabel.text = newAddress
                self.addressCopy.alpha = 1
                self.qrCodeImage.image = generateQRCode(from: newAddress)
                self.qrCodeImage.layer.magnificationFilter = .nearest
                self.qrCodeImage.alpha = 1
                self.addressSpinner.stopAnimating()
                self.qrcodeSpinner.stopAnimating()
            }
        }
    }
    
    @IBAction func copyAddressTapped(_ sender: UIButton) {
        
        UIPasteboard.general.string = self.addressLabel.text
        let alert = UIAlertController(title: "Copied", message: self.addressLabel.text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    @IBAction func refreshButtonTapped(_ sender: UIButton) {
        
        addressCopy.alpha = 0
        qrCodeImage.alpha = 0
        addressLabel.text = ""
        addressSpinner.startAnimating()
        qrcodeSpinner.startAnimating()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.getNewAddress()
        }
    }
    
    func generateQRCode(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        
        if let outputImage = filter.outputImage {
            if let cgimg = context.createCGImage(outputImage, from: outputImage.extent) {
                return UIImage(cgImage: cgimg)
            }
        }
        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
}
