//
//  ReceiveOnchain.swift
//  bittr
//
//  Created by Tom Melters on 14/07/2024.
//

import UIKit
import CoreImage.CIFilterBuiltins
import CodeScanner
import LDKNode
import LDKNodeFFI
import LightningDevKit
import Sentry
import BitcoinDevKit

extension ReceiveViewController {
    
    func getNewAddress(resetAddress:Bool) {
        
        if let cachedAddress = CacheManager.getLastAddress(), resetAddress == false {
            print("Showing cached address.")
            self.addressLabel.text = cachedAddress
            self.addressCopy.alpha = 1
            self.qrCodeImage.image = self.generateQRCode(from: "bitcoin:" + cachedAddress)
            self.qrCodeImage.layer.magnificationFilter = .nearest
            self.qrCodeImage.alpha = 1
            self.qrCodeLogoView.alpha = 1
            self.addressSpinner.stopAnimating()
            self.qrCodeSpinner.stopAnimating()
        } else {
            print("Showing new address.")
            Task {
                do {
                    //let address = try await LightningNodeService.shared.newFundingAddress()
                    let wallet = LightningNodeService.shared.getWallet()
                    if let address = try wallet?.getAddress(addressIndex: .new).address.asString() {
                        DispatchQueue.main.async {
                            CacheManager.storeLastAddress(newAddress: address)
                            self.addressLabel.text = address
                            self.addressCopy.alpha = 1
                            self.qrCodeImage.image = self.generateQRCode(from: "bitcoin:" + address)
                            self.qrCodeImage.layer.magnificationFilter = .nearest
                            self.qrCodeImage.alpha = 1
                            self.qrCodeLogoView.alpha = 1
                            self.addressSpinner.stopAnimating()
                            self.qrCodeSpinner.stopAnimating()
                        }
                    } else {
                        DispatchQueue.main.async {
                            let alert = UIAlertController(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "addressfail"), preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: Language.getWord(withID: "tryagain"), style: .cancel, handler: {_ in
                                self.getNewAddress(resetAddress: resetAddress)
                            }))
                            alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: {_ in
                                self.addressSpinner.stopAnimating()
                                self.qrCodeSpinner.stopAnimating()
                            }))
                            self.present(alert, animated: true)
                        }
                    }
                } catch let error as NodeError {
                    let errorString = handleNodeError(error)
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "addressfail2")). (\(errorString).) \(Language.getWord(withID: "pleasetryagain")).", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: Language.getWord(withID: "tryagain"), style: .cancel, handler: {_ in
                            self.getNewAddress(resetAddress: resetAddress)
                        }))
                        alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: {_ in
                            self.addressSpinner.stopAnimating()
                            self.qrCodeSpinner.stopAnimating()
                        }))
                        self.present(alert, animated: true)
                        
                        SentrySDK.capture(error: error)
                    }
                } catch {
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "addressfail"), preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: Language.getWord(withID: "tryagain"), style: .cancel, handler: {_ in
                            self.getNewAddress(resetAddress: resetAddress)
                        }))
                        alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: {_ in
                            self.addressSpinner.stopAnimating()
                            self.qrCodeSpinner.stopAnimating()
                        }))
                        self.present(alert, animated: true)
                        
                        SentrySDK.capture(error: error)
                    }
                }
            }
        }
    }
    
    
}
