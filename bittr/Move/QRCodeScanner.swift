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
                self.amountLabel.alpha = 0
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
            self.showAlert(title: Language.getWord(withID: "scanningnotsupported"), message: Language.getWord(withID: "scanningnotavailable"), buttons: [Language.getWord(withID: "okay")])
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
            found(code: stringValue)
        }
    }
    
    func found(code: String) {
        
        print("Code: " + code)
        
        // Check bitcoin or lightning in code to switch view if needed.
        var addressType = "onchain"
        if code.lowercased().contains("bitcoin") && code.lowercased().contains("ln") {
            addressType = self.onchainOrLightning
        } else if code.lowercased().contains("ln") || code.contains("lightning") {
            addressType = "lightning"
        } else if !code.contains("bitcoin") && !code.lowercased().contains("ln") {
            addressType = self.onchainOrLightning
        }
        
        if !code.contains("bitcoin") && !code.lowercased().contains("ln") {
            // No valid address.
            self.toTextField.text = nil
            self.amountTextField.text = nil
            self.showAlert(title: Language.getWord(withID: "noaddressfound"), message: Language.getWord(withID: "pleasescan"), buttons: [Language.getWord(withID: "okay")])
        } else if code.lowercased().contains("lnurl") || self.isValidEmail(code.trimmingCharacters(in: .whitespacesAndNewlines)) {
            // Valid LNURL code.
            self.handleLNURL(code: code.replacingOccurrences(of: "lightning:", with: "").trimmingCharacters(in: .whitespacesAndNewlines), sendVC: self, receiveVC: nil)
        } else {
            // Valid address
            
            if code.lowercased().contains("bitcoin:"), code.lowercased().contains("lightning=") {
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
                            if invoiceAmount > self.maximumSendableLNSats ?? 0 {
                                // We can't send this much in Lightning. Send onchain.
                                self.found(code: bitcoinCode)
                                return
                            } else {
                                // We have sufficient funds in Lightning.
                                //self.bitcoinQR = bitcoinCode
                                self.toTextField.text = lightningCode.replacingOccurrences(of: "lightning=", with: "")
                                addressType = "lightning"
                                self.confirmLightningTransaction(lnurlinvoice: nil, sendVC: self, receiveVC: nil)
                            }
                        }
                    }
                }
            } else {
                // This is a normal onchain or lightning QR.
                
                let address = code.lowercased().replacingOccurrences(of: "bitcoin:", with: "").replacingOccurrences(of: "lightning:", with: "").replacingOccurrences(of: "lightning=", with: "")
                let components = address.components(separatedBy: "?")
                if let bitcoinAddress = components.first {
                    // Success.
                    self.toTextField.text = bitcoinAddress
                    
                    if components.count > 1 {
                        if components[1].contains("amount") {
                            let amountString = components[1].components(separatedBy: "&")
                            
                            let numberFormatter = NumberFormatter()
                            numberFormatter.numberStyle = .decimal
                            let bitcoinAmount = (numberFormatter.number(from: amountString[0].replacingOccurrences(of: "amount=", with: "").fixDecimals()) ?? 0).decimalValue as NSNumber
                            
                            self.amountTextField.text = "\(bitcoinAmount)"
                        } else {
                            self.amountTextField.text = nil
                        }
                    } else {
                        self.amountTextField.text = nil
                    }
                } else {
                    self.toTextField.text = nil
                    self.amountTextField.text = nil
                    self.showAlert(title: Language.getWord(withID: "nobitcoinaddressfound"), message: Language.getWord(withID: "pleasescan2"), buttons: [Language.getWord(withID: "okay")])
                }
            }
        }
        
        self.onchainOrLightning = addressType
        
        self.hideScannerView(forView: self.onchainOrLightning)
    }
}
