//
//  QRCodeScanner.swift
//  bittr
//
//  Created by Tom Melters on 02/07/2024.
//

import UIKit
import AVFoundation

extension SendViewController {
    
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
            addressType = ""
        } else if code.lowercased().contains("ln") || code.contains("lightning") {
            addressType = "lightning"
        } else if !code.contains("bitcoin") && !code.lowercased().contains("ln") {
            addressType = ""
        }
        
        if !code.contains("bitcoin") && !code.lowercased().contains("ln") {
             // No valid address.
             self.toTextField.text = nil
             self.amountTextField.text = nil
             let ac = UIAlertController(title: "No address found.", message: "Please scan a bitcoin or lightning address QR code or input the address manually.", preferredStyle: .alert)
             ac.addAction(UIAlertAction(title: "Okay", style: .default))
             present(ac, animated: true)
         } else {
             
            let address = code.lowercased().replacingOccurrences(of: "bitcoin:", with: "").replacingOccurrences(of: "lightning:", with: "")
            let components = address.components(separatedBy: "?")
            if let bitcoinAddress = components.first {
                // Success.
                self.toTextField.alpha = 0
                self.invoiceLabel.text = bitcoinAddress
                self.invoiceLabel.alpha = 1
                self.invoiceLabelTop.constant = 20
                
                if components.count > 1 {
                    if components[1].contains("amount") {
                        //let bitcoinAmount = components[1].replacingOccurrences(of: "amount=", with: "")
                        
                        let amountString = components[1].components(separatedBy: "&")
                        
                        let numberFormatter = NumberFormatter()
                        numberFormatter.numberStyle = .decimal
                        let bitcoinAmount = (numberFormatter.number(from: amountString[0].replacingOccurrences(of: "amount=", with: "").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)) ?? 0).decimalValue as NSNumber
                        
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
                let ac = UIAlertController(title: "No bitcoin address found.", message: "Please scan a bitcoin address QR code or input the address manually.", preferredStyle: .alert)
                ac.addAction(UIAlertAction(title: "Okay", style: .default))
                present(ac, animated: true)
            }
        }
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            
            self.scannerView.alpha = 0
            self.toLabel.alpha = 1
            self.toView.alpha = 1
            
            if addressType == "onchain" {
                
                self.onchainOrLightning = "onchain"
                self.regularView.backgroundColor = UIColor(white: 1, alpha: 1)
                self.instantView.backgroundColor = UIColor(white: 1, alpha: 0.7)
                self.topLabel.text = "Send bitcoin from your bitcoin wallet to another bitcoin wallet. Scan a QR code or input manually."
                self.toLabel.text = "Address"
                self.toTextField.placeholder = "Enter address"
                
                self.pasteButton.alpha = 1
                self.amountLabel.alpha = 1
                self.amountView.alpha = 1
                self.availableAmount.alpha = 1
                self.availableButton.alpha = 1
                self.nextLabel.text = "Next"
                //self.nextViewTop.constant = -30
                
                NSLayoutConstraint.deactivate([self.nextViewTop])
                self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.availableAmount, attribute: .bottom, multiplier: 1, constant: 30)
                NSLayoutConstraint.activate([self.nextViewTop])
                
                self.setSendAllLabel()
                self.availableAmountTop.constant = 10
                self.availableButtonTop.constant = 0
                self.availableAmountCenterX.constant = 0
                self.questionCircle.alpha = 0
                
            } else if addressType == "lightning" {
                
                self.onchainOrLightning = "lightning"
                self.regularView.backgroundColor = UIColor(white: 1, alpha: 0.7)
                self.instantView.backgroundColor = UIColor(white: 1, alpha: 1)
                self.topLabel.text = "Send bitcoin from your bitcoin lightning wallet to another bitcoin lightning wallet."
                self.toLabel.text = "Invoice"
                self.toTextField.placeholder = "Enter invoice"
                
                self.pasteButton.alpha = 1
                self.amountView.alpha = 0
                self.amountLabel.alpha = 0
                self.availableAmount.alpha = 1
                self.availableButton.alpha = 1
                self.nextLabel.text = "Next"
                self.nextViewTop.constant = -120
                self.availableAmountTop.constant = -75
                self.availableButtonTop.constant = -85
                self.availableAmountCenterX.constant = -10
                self.questionCircle.alpha = 1
                
                if let actualMaxAmount = self.maximumSendableLNSats {
                    self.availableAmount.text = "You can send \(actualMaxAmount) satoshis."
                } else {
                    self.availableAmount.text = "You can send 0 satoshis."
                }
                
                NSLayoutConstraint.deactivate([self.nextViewTop])
                self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.availableAmount, attribute: .bottom, multiplier: 1, constant: 30)
                NSLayoutConstraint.activate([self.nextViewTop])
            } else if addressType == "" && self.onchainOrLightning == "onchain" {
                
                self.pasteButton.alpha = 1
                self.amountLabel.alpha = 1
                self.amountView.alpha = 1
                self.availableAmount.alpha = 1
                self.availableButton.alpha = 1
                self.nextLabel.text = "Next"
                //self.nextViewTop.constant = -30
                
                NSLayoutConstraint.deactivate([self.nextViewTop])
                self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.availableAmount, attribute: .bottom, multiplier: 1, constant: 30)
                NSLayoutConstraint.activate([self.nextViewTop])
                
                self.setSendAllLabel()
                self.availableAmountTop.constant = 10
                self.availableButtonTop.constant = 0
                self.availableAmountCenterX.constant = 0
                self.questionCircle.alpha = 0
            } else if addressType == "" && self.onchainOrLightning == "lightning" {
                
                self.pasteButton.alpha = 1
                self.amountView.alpha = 0
                self.amountLabel.alpha = 0
                self.availableAmount.alpha = 1
                self.availableButton.alpha = 1
                self.nextLabel.text = "Next"
                self.nextViewTop.constant = -120
                self.availableAmountTop.constant = -75
                self.availableButtonTop.constant = -85
                self.availableAmountCenterX.constant = -10
                self.questionCircle.alpha = 1
                
                if let actualMaxAmount = self.maximumSendableLNSats {
                    self.availableAmount.text = "You can send \(actualMaxAmount) satoshis."
                } else {
                    self.availableAmount.text = "You can send 0 satoshis."
                }
                
                NSLayoutConstraint.deactivate([self.nextViewTop])
                self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.availableAmount, attribute: .bottom, multiplier: 1, constant: 30)
                NSLayoutConstraint.activate([self.nextViewTop])
            }
            
            self.view.layoutIfNeeded()
        }
    }
}
