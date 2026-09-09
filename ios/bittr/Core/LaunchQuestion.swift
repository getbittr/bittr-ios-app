//
//  LaunchQuestion.swift
//  bittr
//
//  Created by Tom Melters on 23/02/2024.
//

import UIKit

extension CoreViewController {

    func launchQuestion(question:String, answer:String, type:String?) {
        guard let presenter = Self.topMostViewController() else {
            Log.info("launchQuestion: no view controller available to present from.")
            return
        }
        
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        guard let questionVC = storyboard.instantiateViewController(withIdentifier: "Question") as? QuestionViewController else { return }
        questionVC.headerText = question
        questionVC.answerText = answer
        questionVC.questionType = type
        questionVC.coreVC = self
        
        Log.info("launchQuestion presenting from \(presenter), app active: \(UIApplication.shared.applicationState == .active)")
        
        presenter.present(questionVC, animated: true)
    }
    
    private static func topMostViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
    
}
