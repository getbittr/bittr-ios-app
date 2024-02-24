//
//  QuestionViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/02/2024.
//

import UIKit

class QuestionViewController: UIViewController {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var answerLabel: UILabel!
    
    var headerText:String?
    var answerText:String?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        downButton.setTitle("", for: .normal)
        headerView.layer.cornerRadius = 13
        
        if let actualHeader = headerText, let actualAnswer = answerText {
            self.headerLabel.text = actualHeader
            self.answerLabel.text = actualAnswer
        }
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
}
