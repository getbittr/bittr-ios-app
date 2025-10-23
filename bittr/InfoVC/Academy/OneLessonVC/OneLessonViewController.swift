//
//  OneLessonViewController.swift
//  bittr
//
//  Created by Tom Melters on 10/23/25.
//

import UIKit

class OneLessonViewController: UIViewController {
    
    // UI elements
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var mainScrollView: UIScrollView!
    @IBOutlet weak var mainContentView: UIView!
    @IBOutlet weak var mainContentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var centerView: UIView!
    
    // Variables
    var thisLesson:Lesson?
    var coreVC:CoreViewController?
    var currentPage = 0
    var heightFromTop:CGFloat = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Button titles
        self.downButton.setTitle("", for: .normal)
        
        // Color management
        self.changeColors()
        
        if self.thisLesson != nil {
            
            self.headerLabel.text = self.thisLesson!.title
            self.loadPage(0)
        }
        
    }
    
    func loadPage(_ pageNumber:Int) {
        
        self.heightFromTop = 0
        for eachSubview in self.centerView.subviews {
            eachSubview.removeFromSuperview()
        }
        
        var addedComponents = 0
        while addedComponents < self.thisLesson!.pages[pageNumber].components.count {
            
            let thisComponent = self.thisLesson!.pages[pageNumber].components[addedComponents]
            let previousComponentType:ComponentType? = {
                if addedComponents == 0 {
                    return nil
                } else {
                    return self.thisLesson!.pages[pageNumber].components[addedComponents - 1].type
                }
            }()
            
            switch thisComponent.type {
            case .label:
                self.addLabel(withText: thisComponent.text, previousComponent: previousComponentType)
            }
            
            addedComponents += 1
        }
        
        let firstPage:Bool = {
            if self.currentPage == 0 {
                return true
            } else {
                return false
            }
        }()
        self.addButton(previousComponent: self.thisLesson!.pages[pageNumber].components.last?.type, firstPage: firstPage)
    }
    
    @objc func previousPage() {
        // Go to previous page.
        
        self.currentPage -= 1
        self.loadPage(self.currentPage)
    }
    
    @objc func nextPage() {
        // Go to next page.
        
        if self.currentPage < (self.thisLesson!.pages.count - 1) {
            // There are more pages.
            self.currentPage += 1
            self.loadPage(self.currentPage)
        } else {
            // This is the final page.
            self.dismiss(animated: true)
        }
    }
    
    @IBAction func downTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue2")
    }
    
}
