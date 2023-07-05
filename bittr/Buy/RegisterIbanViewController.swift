//
//  RegisterIbanViewController.swift
//  bittr
//
//  Created by Tom Melters on 15/06/2023.
//

import UIKit

class RegisterIbanViewController: UIViewController {
    
    @IBOutlet weak var downButton: UIButton!
    var currentPage = 0
    
    @IBOutlet weak var transfer1ContainerViewLeading: NSLayoutConstraint!
    
    var currentClientID = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        downButton.setTitle("", for: .normal)
        
        NotificationCenter.default.addObserver(self, selector: #selector(nextPageTapped), name: NSNotification.Name(rawValue: "signupnext"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(downButtonTapped), name: NSNotification.Name(rawValue: "restorewallet"), object: nil)
    }
    
    @objc func nextPageTapped(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let pageNumber = userInfo["page"] as? String {
                
                let viewWidth = self.view.safeAreaLayoutGuide.layoutFrame.size.width
                var leadingConstant:CGFloat = 0
                
                switch pageNumber {
                case "7":
                    leadingConstant = -1 * viewWidth
                    currentPage = 9
                case "8":
                    leadingConstant = -2 * viewWidth
                    currentPage = 10
                case "9":
                    leadingConstant = -3 * viewWidth
                    currentPage = 11
                default:
                    leadingConstant = -viewWidth
                }
                
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                    
                    self.transfer1ContainerViewLeading.constant = leadingConstant
                    self.view.layoutIfNeeded()
                }
            }
        }
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        
        self.dismiss(animated: true, completion: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "RegisterToTransfer1" {
            
            let transfer1VC = segue.destination as? Transfer1ViewController
            if let actualTransfer1VC = transfer1VC {
                
                actualTransfer1VC.currentClientID = self.currentClientID
            }
        }
    }
    
}
