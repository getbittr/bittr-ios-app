//
//  QRCodeScanner.swift
//  bittr
//
//  Created by Tom Melters on 02/07/2024.
//

import UIKit
import AVFoundation
import LNURLDecoder
import LightningDevKit
import Sentry

extension SendViewController {
    
    func showScannerView() {
        
        if fixQrScanner() {
            // Open QR scanner.
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                self.addressStack.alpha = 0
                self.toLabel.alpha = 0
                self.toView.alpha = 0
                self.pasteButton.alpha = 0
                self.amountStack.alpha = 0
                self.availableAmount.alpha = 0
                self.availableButton.alpha = 0
                self.scannerView.alpha = 1
                
                // Update Next button
                self.nextLabel.text = Language.getWord(withID: "manualinput")
                self.arrowIconWidth.constant = 0
                self.arrowIconLeading.constant = 0
                
                NSLayoutConstraint.deactivate([self.nextViewTop])
                self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.scannerView, attribute: .bottom, multiplier: 1, constant: 30)
                NSLayoutConstraint.activate([self.nextViewTop])
                
                self.view.layoutIfNeeded()
            }
            
            if (self.captureSession?.isRunning == false) {
                DispatchQueue.global(qos: .background).async {
                    self.captureSession.startRunning()
                }
            }
        } else {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "scanningnotsupported"), message: Language.getWord(withID: "scanningnotavailable"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    func fixQrScanner() -> Bool {
        
        captureSession = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            self.scannerWorks = false
            return false
        }
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "QRCodeScanner row 61", key: "context")
                }
            }
            self.scannerWorks = false
            return false
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            return false
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return false
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = self.scannerView.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        self.scannerView.layer.addSublayer(previewLayer)
        
        self.scannerWorks = true
        return true
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        
        if let actualCaptureSession = captureSession {
            actualCaptureSession.stopRunning()
        }

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            self.handleScannedOrPastedString(stringValue, scanned: true)
        }
    }
    
    func handleScannedOrPastedString(_ code:String, scanned:Bool) {
        print("Code: " + code)
        
        // Parse code components.
        let bitcoinAddress = code.lowercased().extractBitcoinAddress()
        let lightningInvoice = code.lowercased().extractLightningInvoice()
        let lnurl = code.lowercased().extractLNURL()
        let amount = code.lowercased().extractAmount()
        
        // Check and handle parsed code components.
        if lnurl != nil {
            Log.info("Did find LNURL.")
            
            self.toTextField.text = lnurl!
            self.handleLNURL(code: lnurl!)
            self.onchainOrLightning = .lightning
            self.hideScanner()
        } else if lightningInvoice != nil {
            Log.info("Did find invoice.")
            
            // Example QR
            // bitcoin:bc1qhg5nndn8ngrykjun9k7rgczw2x3ywwtcf0hplz?amount=0.00001&lightning=lnbc10u1pnma0z3dqqnp4q0wy5shnpskxc050schq0r5gkkk39e5w89qzfcd5fz9ngejqjwhavpp5vfpx5dwh97vf7wrvcu9mt006mkdft5fjzfnrqakf6288dhj9r2pssp5e64sv4zyf4esy4wgdkdndtne2lxr4lf0ndpy2e0n3qm80kfty77q9qyysgqcqpcxqrrssrzjqd54day770dcv0n0fhp57f9vuxd7zack3gy8p6pletmw0f5rsv439apyqqqqqqqqqvqqqqlgqqqqqqgq2qvw6n7wd6x6ej47u5a2k253jy65js489qvrf36v8mnw79u3hvaz9k3926ypm2d92h7wxlff7gtyen3ny0gp9mqwjhj8kvk3w9kaq5dxqqtqwll6
            
            // Check if we have sufficient funds in Lightning.
            if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: lightningInvoice!).getValue() {
                
                let invoiceAmount:Int = {
                    if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                        // Regular invoice
                        return Int(invoiceAmountMilli)/1000
                    } else {
                        // Zero invoice
                        return amount ?? 0
                    }
                }()
                
                if invoiceAmount > (self.coreVC?.bittrWallet.lightningChannels.getActiveChannel()?.outboundCapacityMsat ?? 0)/1000 {
                    // We can't send this much in Lightning. Send onchain.
                    self.handleScannedOrPastedString(bitcoinAddress!, scanned: scanned)
                    return
                } else {
                    // We have sufficient funds in Lightning.
                    self.toTextField.text = lightningInvoice!
                    self.amountTextField.text = "\(invoiceAmount)"
                    self.btcLabel.text = "Sats"
                    self.selectedCurrency = .satoshis
                    self.onchainOrLightning = .lightning
                }
                
                if bitcoinAddress != nil {
                    Log.info("Did also find onchain address.")
                    self.bitcoinQR = bitcoinAddress!
                }
            }
        } else if bitcoinAddress != nil {
            Log.info("Did find onchain address.")
            self.toTextField.text = bitcoinAddress!
            self.onchainOrLightning = .onchain
            if amount != nil, amount != 0 {
                self.amountTextField.text = "\(amount!)"
                self.btcLabel.text = "Sats"
                self.selectedCurrency = .satoshis
            }
        } else {
            Log.info("Did not find a valid address or invoice.")
            self.toTextField.text = nil
            self.amountTextField.text = nil
            self.showAlert(presentingController: self, title: Language.getWord(withID: "nobitcoinaddressfound"), message: Language.getWord(withID: "pleasescan"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Hide QR scanner and switch views to onchain or lightning.
        self.hideScanner()
    }
}

extension String {
    
    func extractBitcoinAddress() -> String? {
        let components = self.components(separatedBy: CharacterSet(charactersIn: "&:?="))
        for eachComponent in components {
            if eachComponent.isValidBitcoinAddress() {
                return eachComponent
            }
        }
        return nil
    }
    
    func extractLightningInvoice() -> String? {
        let components = self.components(separatedBy: CharacterSet(charactersIn: "&:?="))
        for eachComponent in components {
            if eachComponent.isValidInvoice() {
                return eachComponent
            }
        }
        return nil
    }
    
    func extractLNURL() -> String? {
        let components = self.components(separatedBy: CharacterSet(charactersIn: "&:?="))
        for eachComponent in components {
            if eachComponent.isValidEmail() {
                return eachComponent
            } else if eachComponent.hasPrefix("lnurl") {
                return eachComponent
            }
        }
        return nil
    }
    
    func extractAmount() -> Int? {
        let components = self.components(separatedBy: CharacterSet(charactersIn: "&:?"))
        for eachComponent in components {
            if eachComponent.contains("amount=") {
                return eachComponent.replacingOccurrences(of: "amount=", with: "").toNumber().inSatoshis()
            }
        }
        return nil
    }
    
    func isValidBitcoinAddress() -> Bool {
        let patterns = [
            "^1[a-km-zA-HJ-NP-Z1-9]{25,34}$",  // P2PKH Mainnet
            "^[mn2][a-km-zA-HJ-NP-Z1-9]{33}$",  // P2PKH or P2SH Testnet
            "^bc1[qzp][a-z0-9]{38,}$",  // Bech32 Mainnet
            "^tb1[qzp][a-z0-9]{38,}$",  // Bech32 Testnet
        ]
        return patterns.contains {
            self.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
    
    func isValidInvoice() -> Bool {
        if self.hasPrefix("ln") {
            let bolt11Invoice = Bolt11Invoice.fromStr(s: self)
            if bolt11Invoice.isOk(), bolt11Invoice.getValue() != nil {
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }
}
