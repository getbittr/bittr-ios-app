//
//  InfoVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension InfoViewController {
    
    func setWords() {
        
        self.newsLabel.text = Language.getWord(withID: "news")
        self.questionsLabel.text = Language.getWord(withID: "questions")
        self.noArticles.text = Language.getWord(withID: "noarticles")
    }
}
