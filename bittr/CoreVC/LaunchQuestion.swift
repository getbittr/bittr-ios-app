//
//  LaunchQuestion.swift
//  bittr
//
//  Created by Tom Melters on 23/02/2024.
//

import UIKit

extension CoreViewController {

    @objc func launchQuestion(notification:NSNotification) {
        
        // Launch QuestionVC.
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let notificationQuestion = userInfo["question"] as? String, let notificationAnswer = userInfo["answer"] as? String {
                self.tappedQuestion = notificationQuestion
                self.tappedAnswer = notificationAnswer
                if let notificationType = userInfo["type"] as? String {
                    self.tappedType = notificationType
                } else {
                    self.tappedType = nil
                }
                self.performSegue(withIdentifier: "CoreToQuestion", sender: self)
            }
        }
    }
    
}
