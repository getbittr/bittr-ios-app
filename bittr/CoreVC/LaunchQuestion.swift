//
//  LaunchQuestion.swift
//  bittr
//
//  Created by Tom Melters on 23/02/2024.
//

import UIKit

extension CoreViewController {

    func launchQuestion(question:String, answer:String, type:String?) {
        
        // Launch QuestionVC.
        self.tappedQuestion = question
        self.tappedAnswer = answer
        self.tappedType = type
        
        self.performSegue(withIdentifier: "CoreToQuestion", sender: self)
    }
    
}
