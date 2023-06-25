//
//  TransactionViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class TransactionViewController: UIViewController {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var bodyView: UIView!
    @IBOutlet weak var dateView: UIView!
    @IBOutlet weak var headerView: UIView!
    
    @IBOutlet weak var amountView: UIView!
    @IBOutlet weak var toView: UIView!
    @IBOutlet weak var idView: UIView!
    @IBOutlet weak var thenView: UIView!
    @IBOutlet weak var nowView: UIView!
    @IBOutlet weak var profitView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        downButton.setTitle("", for: .normal)
        
        headerView.layer.cornerRadius = 13
        bodyView.layer.cornerRadius = 13
        dateView.layer.cornerRadius = 7
        amountView.layer.cornerRadius = 7
        toView.layer.cornerRadius = 7
        idView.layer.cornerRadius = 7
        thenView.layer.cornerRadius = 7
        nowView.layer.cornerRadius = 7
        profitView.layer.cornerRadius = 7
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
}
