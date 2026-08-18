//
//  ScannerViewController.swift
//  bittr
//
//  Created by Tom Melters on 3/9/26.
//

import UIKit
import CodeScanner
import AVFoundation

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    // UI elements
    @IBOutlet weak var scannerView: UIView!
    @IBOutlet weak var closeView: UIView!
    @IBOutlet weak var closeLabel: UILabel!
    @IBOutlet weak var closeButton: UIButton!
    
    // Variables
    var sendVC:SendViewController?
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var scannerWorks = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Button titles
        self.closeButton.setTitle("", for: .normal)

        self.scannerView.accessibilityIdentifier = TestID.Scanner.scannerView
        self.closeButton.accessibilityIdentifier = TestID.Scanner.closeButton
        
        // Corner radii
        self.closeView.layer.cornerRadius = 8
        self.scannerView.layer.cornerRadius = 13

        // Basics
        self.changeColors()
        self.setLanguage()
        self.addHeader(iconLight: "qrcode", iconDark: "qrcode", title: Language.getWord(withID: "scanner"))
    }
    
    override func viewDidAppear(_ animated: Bool) {
        if self.fixQrScanner() {
            if (self.captureSession?.isRunning == false) {
                DispatchQueue.global(qos: .background).async {
                    self.captureSession.startRunning()
                }
            }
        } else {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "scanningnotsupported"), message: Language.getWord(withID: "scanningnotavailable"), buttons: [.action(Language.getWord(withID: "okay")) { self.closeScannerView() }])
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        if (self.captureSession?.isRunning == true) {
            self.captureSession.stopRunning()
        }
    }
    
    func closeScannerView() {
        self.dismiss(animated: true)
    }
    
    func fixQrScanner() -> Bool {
        
        self.captureSession = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            self.scannerWorks = false
            return false
        }
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            SentryManager.capture(error, context: "QRCodeScanner row 61")
            self.scannerWorks = false
            return false
        }
        
        if (self.captureSession.canAddInput(videoInput)) {
            self.captureSession.addInput(videoInput)
        } else {
            return false
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (self.captureSession.canAddOutput(metadataOutput)) {
            self.captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return false
        }
        
        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        self.previewLayer.frame = self.scannerView.layer.bounds
        self.previewLayer.videoGravity = .resizeAspectFill
        self.scannerView.layer.addSublayer(self.previewLayer)
        
        self.scannerWorks = true
        return true
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        
        if self.captureSession != nil {
            self.captureSession.stopRunning()
        }

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            self.sendVC?.handleScannedOrPastedString(stringValue)
            self.dismiss(animated: true)
        }
    }
    
    @IBAction func closeButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    func changeColors() {
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
    }
    
    func setLanguage() {
        self.closeLabel.text = Language.getWord(withID: "close")
    }
}
