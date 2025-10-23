//
//  AcademyViewController.swift
//  bittr
//
//  Created by Tom Melters on 10/18/25.
//

import UIKit

class AcademyViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    // Table
    @IBOutlet weak var academyTableView: UITableView!
    
    // Variables
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Table view.
        self.academyTableView.delegate = self
        self.academyTableView.dataSource = self
        self.academyTableView.contentInset = UIEdgeInsets(top: 90, left: 0, bottom: 100, right: 0)
        self.academyTableView.rowHeight = UITableView.automaticDimension
        self.academyTableView.estimatedRowHeight = 300
        
        // Get Academy levels.
        self.getLevels()
    }
    
    func getLevels() {
        if self.coreVC?.downloadedAcademy != nil {
            // Levels have already been downloaded.
            self.academyTableView.reloadData()
        } else {
            // Download levels.
            
            // Demo data
            let labelComponent = Component()
            labelComponent.order = 0
            labelComponent.type = .label
            labelComponent.text = "Welcome to Bittr Academy!"
            let firstPage = Page()
            firstPage.order = 0
            firstPage.components = [labelComponent]
            
            let lesson1 = Lesson()
            lesson1.order = 0
            lesson1.pages = [firstPage]
            lesson1.title = "What is bitcoin?"
            let lesson2 = Lesson()
            lesson2.order = 1
            lesson2.pages = [firstPage]
            lesson2.title = "What are satoshis?"
            let lesson3 = Lesson()
            lesson3.order = 2
            lesson3.pages = [firstPage]
            lesson3.title = "The problem with fiat currencies"
            let lesson4 = Lesson()
            lesson4.order = 3
            lesson4.pages = [firstPage]
            lesson4.title = "Why do people invest in bitcoin?"
            let lesson5 = Lesson()
            lesson5.order = 4
            lesson5.pages = [firstPage]
            lesson5.title = "Why is bitcoin volatile?"
            let lesson6 = Lesson()
            lesson6.order = 5
            lesson6.pages = [firstPage]
            lesson6.title = "What is mining?"
            
            let firstLevel = Level()
            firstLevel.order = 0
            firstLevel.lessons = [lesson1, lesson2, lesson3, lesson4, lesson5, lesson6]
            
            let secondLevel = Level()
            secondLevel.order = 1
            secondLevel.lessons = [lesson1, lesson2, lesson3]
            
            self.coreVC!.downloadedAcademy = [firstLevel, secondLevel]
            
            self.academyTableView.reloadData()
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return self.coreVC?.downloadedAcademy?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        if let cell = tableView.dequeueReusableCell(withIdentifier: "LevelCell", for: indexPath) as? LevelTableViewCell {
            
            // Cell Z position.
            cell.layer.zPosition = CGFloat(indexPath.row)
            
            // Level details.
            cell.thisLevel = self.coreVC!.downloadedAcademy![indexPath.row]
            cell.levelLabel.text = "level \(indexPath.row + 1)"
            cell.countLabel.text = "0 of \(self.coreVC!.downloadedAcademy![indexPath.row].lessons.count)"
            cell.lessonsCollectionView.reloadData()
            
            // Set dynamic cell height.
            cell.layoutSubviews()
            cell.cellHeight.constant = cell.lessonsCollectionView.collectionViewLayout.collectionViewContentSize.height + 100
            
            return cell
        } else {
            return UITableViewCell()
        }
    }
    
    
}
