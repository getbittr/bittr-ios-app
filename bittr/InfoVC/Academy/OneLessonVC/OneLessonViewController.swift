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
    @IBOutlet weak var centerSpinner: UIActivityIndicatorView!
    
    // Variables
    var thisLesson:Lesson?
    var coreVC:CoreViewController?
    var academyVC:AcademyViewController?
    var currentPage = 0
    var heightFromTop:CGFloat = 0
    var addedComponents = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Button titles
        self.downButton.setTitle("", for: .normal)
        
        // Color management
        self.changeColors()
        
        if self.thisLesson != nil {
            
            self.headerLabel.text = self.thisLesson!.title
            self.loadPage()
        }
        
    }
    
    func loadPage() {
        
        self.heightFromTop = 0
        self.addedComponents = 0
        for eachSubview in self.centerView.subviews {
            eachSubview.removeFromSuperview()
        }
        self.centerView.alpha = 0
        self.centerSpinner.startAnimating()
        
        self.addNextComponent()
    }
    
    func addNextComponent() {
        
        if self.addedComponents == self.thisLesson!.pages[self.currentPage].components.count {
            // All components have been loaded. Add Next button.
            
            let firstPage = self.currentPage == 0 ? true : false
            let lastPage = self.currentPage == (self.thisLesson!.pages.count - 1) ? true : false
            self.addButton(previousComponent: self.thisLesson!.pages[self.currentPage].components.last?.type, firstPage: firstPage, lastPage: lastPage)
            self.centerSpinner.stopAnimating()
            self.centerView.alpha = 1
        } else {
            // Load next component.
            
            let thisComponent = self.thisLesson!.pages[self.currentPage].components[self.addedComponents]
            let previousComponentType:ComponentType? = {
                if addedComponents == 0 {
                    return nil
                } else {
                    return self.thisLesson!.pages[self.currentPage].components[self.addedComponents - 1].type
                }
            }()
            
            self.addedComponents += 1
            
            switch thisComponent.type {
            case .label:
                self.addLabel(withText: thisComponent.text, previousComponent: previousComponentType)
            case .image:
                self.addImage(url: thisComponent.url, previousComponent: previousComponentType)
            }
        }
    }
    
    @objc func previousPage() {
        // Go to previous page.
        
        self.currentPage -= 1
        self.loadPage()
    }
    
    @objc func nextPage() {
        // Go to next page.
        
        if self.currentPage < (self.thisLesson!.pages.count - 1) {
            // There are more pages.
            self.currentPage += 1
            self.loadPage()
        } else {
            // This is the final page.
            CacheManager.addCompletedLesson(self.thisLesson!.id)
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "reloadcollectionview"), object: nil, userInfo: nil) as Notification)
            self.dismiss(animated: true)
        }
    }
    
    @IBAction func downTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue2")
        self.centerSpinner.color = Colors.getColor("blackorwhite")
    }
    
}
