//
//  QRCodeScanner.swift
//  bittr
//
//  Created by Tom Melters on 02/07/2024.
//

import UIKit
import AVFoundation
import LNURLDecoder

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
            self.showAlert(Language.getWord(withID: "scanningnotsupported"), Language.getWord(withID: "scanningnotavailable"), Language.getWord(withID: "okay"))
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
            self.showAlert(Language.getWord(withID: "noaddressfound"), Language.getWord(withID: "pleasescan"), Language.getWord(withID: "okay"))
        } else if code.lowercased().contains("lnurl") || self.isValidEmail(code.trimmingCharacters(in: .whitespacesAndNewlines)) {
            // Valid LNURL code.
            self.handleLNURL(code: code.replacingOccurrences(of: "lightning:", with: "").trimmingCharacters(in: .whitespacesAndNewlines), sendVC: self, receiveVC: nil)
        } else {
             // Valid address
             let address = code.lowercased().replacingOccurrences(of: "bitcoin:", with: "").replacingOccurrences(of: "lightning:", with: "")
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
                 self.showAlert(Language.getWord(withID: "nobitcoinaddressfound"), Language.getWord(withID: "pleasescan2"), Language.getWord(withID: "okay"))
             }
        }
        
        self.onchainOrLightning = addressType
        
        self.hideScannerView(forView: self.onchainOrLightning)
    }
}
