//
//  LaunchQuestion.swift
//  bittr
//
//  Created by Tom Melters on 23/02/2024.
//

import UIKit

extension CoreViewController {

    @objc func launchQuestion(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let notificationQuestion = userInfo["question"] as? String, let notificationAnswer = userInfo["answer"] as? String {
                self.tappedQuestion = notificationQuestion
                self.tappedAnswer = notificationAnswer
                self.performSegue(withIdentifier: "CoreToQuestion", sender: self)
            }
        }
    }
    
}
