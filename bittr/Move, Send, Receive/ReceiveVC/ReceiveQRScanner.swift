//
//  ReceiveQRScanner.swift
//  bittr
//
//  Created by Tom Melters on 23/10/2024.
//

import UIKit
import AVFoundation
import LNURLDecoder
import Sentry

extension ReceiveViewController {
    
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
                    scope.setExtra(value: "ReceiveQRScanner row 28", key: "context")
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
    
    func showScannerView() {
        
        if fixQrScanner() {
            if (self.captureSession?.isRunning == false) {
                DispatchQueue.global(qos: .background).async {
                    self.captureSession.startRunning()
                }
            }
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        
        if let actualCaptureSession = captureSession {
            actualCaptureSession.stopRunning()
        }
        
        self.qrScannerView.alpha = 0

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            found(code: stringValue)
        }
    }
    
    func found(code: String) {
        
        print("Code: " + code)
        
        if code.lowercased().contains("lnurl") || self.isValidEmail(code.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))  {
            // Valid LNURL code.
            self.handleLNURL(code: code.replacingOccurrences(of: "lightning:", with: ""), sendVC: nil, receiveVC: self)
        }
    }
    
}
