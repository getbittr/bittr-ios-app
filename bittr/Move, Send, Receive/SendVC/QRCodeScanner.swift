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

extension SendViewController {
    
    func showScannerView() {
        
        if fixQrScanner() == true {
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
                self.nextLabel.text = Language.getWord(withID: "manualinput")
                
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
        
        var addressType:OnchainOrLightning = .onchain
        
        // Check bitcoin or lightning in code to switch view if needed.
        if code.lowercased().split(separator: "&").first!.contains("bitcoin:"), code.lowercased().split(separator: "&").last!.contains("lightning=") {
            // This is a Bitcoin QR with lightning parameter.
            addressType = .lightning
        } else if code.lowercased().contains("bitcoin:") {
            // This is a regular Bitcoin URI (on-chain).
            addressType = .onchain
        } else if code.lowercased().split(separator: "&").first!.prefix(2) == "ln" {
            // This is a Lightning invoice.
            addressType = .lightning
        } else if code.lowercased().contains("@") {
            // This is an LNURL.
            addressType = .lightning
        } else {
            // Unsure about the code.
            addressType = self.onchainOrLightning
        }
        
        if scanned, !code.contains("bitcoin") && !code.lowercased().contains("ln") {
            // No valid address.
            self.toTextField.text = nil
            self.amountTextField.text = nil
            self.showAlert(presentingController: self, title: Language.getWord(withID: "noaddressfound"), message: Language.getWord(withID: "pleasescan"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        } else if code.lowercased().contains("lnurl") || self.isValidEmail(code.trimmingCharacters(in: .whitespacesAndNewlines)) {
            // Valid LNURL code.
            self.toTextField.text = code
            self.handleLNURL(code: code.replacingOccurrences(of: "lightning:", with: "").trimmingCharacters(in: .whitespacesAndNewlines), sendVC: self, receiveVC: nil)
        } else {
            // Valid address
            
            if code.lowercased().split(separator: "&").first!.contains("bitcoin:"), code.lowercased().split(separator: "&").last!.contains("lightning=") {
                // This is a Bitcoin QR.
                
                // Example QR
                // bitcoin:bc1qhg5nndn8ngrykjun9k7rgczw2x3ywwtcf0hplz?amount=0.00001&lightning=lnbc10u1pnma0z3dqqnp4q0wy5shnpskxc050schq0r5gkkk39e5w89qzfcd5fz9ngejqjwhavpp5vfpx5dwh97vf7wrvcu9mt006mkdft5fjzfnrqakf6288dhj9r2pssp5e64sv4zyf4esy4wgdkdndtne2lxr4lf0ndpy2e0n3qm80kfty77q9qyysgqcqpcxqrrssrzjqd54day770dcv0n0fhp57f9vuxd7zack3gy8p6pletmw0f5rsv439apyqqqqqqqqqvqqqqlgqqqqqqgq2qvw6n7wd6x6ej47u5a2k253jy65js489qvrf36v8mnw79u3hvaz9k3926ypm2d92h7wxlff7gtyen3ny0gp9mqwjhj8kvk3w9kaq5dxqqtqwll6
                
                let codeElements = code.split(separator: "&")
                var bitcoinCode = ""
                var lightningCode = ""
                for eachElement in codeElements {
                    if String(eachElement).contains("bitcoin:") {
                        bitcoinCode = String(eachElement)
                    } else if String(eachElement).contains("lightning=") {
                        lightningCode = String(eachElement)
                    }
                }
                
                if bitcoinCode != "", lightningCode != "" {
                    // Codes have been correctly recognized.
                    
                    // Check if we have sufficient funds in Lightning.
                    if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: lightningCode.replacingOccurrences(of: "lightning=", with: "")).getValue() {
                        if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                            let invoiceAmount = Int(invoiceAmountMilli)/1000
                            if invoiceAmount > (self.coreVC?.bittrWallet.lightningChannels.first?.outboundCapacityMsat ?? 0)/1000 {
                                // We can't send this much in Lightning. Send onchain.
                                self.handleScannedOrPastedString(bitcoinCode, scanned: scanned)
                                return
                            } else {
                                // We have sufficient funds in Lightning.
                                self.bitcoinQR = bitcoinCode.split(separator: "?").first!.replacingOccurrences(of: "bitcoin:", with: "")
                                self.toTextField.text = lightningCode.replacingOccurrences(of: "lightning=", with: "")
                                self.amountTextField.text = "\(invoiceAmount)"
                                self.btcLabel.text = "Sats"
                                self.selectedCurrency = .satoshis
                                addressType = .lightning
                            }
                        } else {
                            // Zero invoice.
                            self.bitcoinQR = bitcoinCode.split(separator: "?").first!.replacingOccurrences(of: "bitcoin:", with: "")
                            self.toTextField.text = lightningCode.replacingOccurrences(of: "lightning=", with: "")
                            addressType = .lightning
                        }
                    }
                }
            } else {
                // This is a normal onchain or lightning QR.
                
                let address = code.lowercased().replacingOccurrences(of: "bitcoin:", with: "").replacingOccurrences(of: "lightning:", with: "").replacingOccurrences(of: "lightning=", with: "")
                let components = address.components(separatedBy: "?")
                if let bitcoinAddress = components.first {
                    // Success.
                    
                    // Switch to the appropriate mode based on addressType
                    if addressType == .onchain {
                        // Switch to regular (on-chain) mode
                        if let regularButton = self.regularButton {
                            regularButton.sendActions(for: .touchUpInside)
                        }
                    } else if addressType == .lightning {
                        // Switch to instant (Lightning) mode
                        if let instantButton = self.instantButton {
                            instantButton.sendActions(for: .touchUpInside)
                        }
                    }
                    
                    // Wait a moment for the mode switch to complete, then set the address and amount
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.toTextField.text = bitcoinAddress
                        
                        if components.count > 1 {
                            if components[1].contains("amount") {
                                let amountString = components[1].components(separatedBy: "&")
                                
                                let numberFormatter = NumberFormatter()
                                numberFormatter.numberStyle = .decimal
                                let bitcoinAmount = (numberFormatter.number(from: amountString[0].replacingOccurrences(of: "amount=", with: "").fixDecimals()) ?? 0).decimalValue as NSNumber
                                
                                // Convert BTC amount to satoshis
                                if let btcAmount = Double("\(bitcoinAmount)") {
                                    let satoshis = Int(btcAmount * 100_000_000) // Convert BTC to satoshis
                                    self.amountTextField.text = "\(satoshis)"
                                    self.btcLabel.text = "Sats"
                                    self.selectedCurrency = .satoshis
                                    print("QR Scanner: Converted Bitcoin URI amount from \(bitcoinAmount) BTC to \(satoshis) satoshis")
                                } else {
                                    // If conversion fails, set the amount as-is
                                    self.amountTextField.text = "\(bitcoinAmount)"
                                    print("QR Scanner: Could not convert Bitcoin URI amount, setting as-is: \(bitcoinAmount)")
                                }
                            } else {
                                self.amountTextField.text = nil
                            }
                        } else {
                            self.amountTextField.text = nil
                        }
                        
                        // Handle Lightning invoice if it's a direct ln... address
                        if bitcoinAddress.prefix(2) == "ln" {
                            if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: bitcoinAddress).getValue() {
                                if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                                    let invoiceAmount = Int(invoiceAmountMilli)/1000
                                    self.amountTextField.text = "\(invoiceAmount)"
                                    self.btcLabel.text = "Sats"
                                    self.selectedCurrency = .satoshis
                                } else {
                                    self.amountTextField.text = nil
                                }
                            }
                        }
                    }
                } else {
                    self.toTextField.text = nil
                    self.amountTextField.text = nil
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "nobitcoinaddressfound"), message: Language.getWord(withID: "pleasescan2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            }
        }
        
        self.onchainOrLightning = addressType
        
        self.hideScannerView(forView: self.onchainOrLightning)
    }
}
