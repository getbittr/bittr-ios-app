//
//  ReceiveViewController.swift
//  bittr
//
//  Created by Tom Melters on 05/05/2023.
//

import UIKit

class ReceiveViewController: UIViewController {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var qrView: UIView!
    @IBOutlet weak var addressView: UIView!
    @IBOutlet weak var refreshView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        downButton.setTitle("", for: .normal)
        headerView.layer.cornerRadius = 13
        qrView.layer.cornerRadius = 13
        addressView.layer.cornerRadius = 13
        refreshView.layer.cornerRadius = 13
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
}
