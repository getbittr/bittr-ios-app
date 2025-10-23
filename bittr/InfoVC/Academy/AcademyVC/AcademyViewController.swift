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
    var tappedLesson:Lesson?
    
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
        self.changeColors()
    }
    
    func getLevels() {
        if self.coreVC?.downloadedAcademy != nil {
            // Levels have already been downloaded.
            self.academyTableView.reloadData()
        } else {
            // Download levels.
            
            // Demo data
            let firstLabel = Component()
            firstLabel.order = 0
            firstLabel.type = .label
            firstLabel.text = "Bitcoin was introduced by Satoshi Nakamoto, to create a new kind of digital money."
            let secondLabel = Component()
            secondLabel.order = 1
            secondLabel.type = .label
            secondLabel.text = "The idea was simple: people could send payments directly to each other without using a bank or any other middleman."
            let firstPage = Page()
            firstPage.order = 0
            firstPage.components = [firstLabel, secondLabel]
            
            let page2label1 = Component()
            page2label1.order = 0
            page2label1.type = .label
            page2label1.text = "Unlike fiat money, Bitcoin isn’t controlled by any one group or government. It’s decentralized and follows strict rules that keep it running. This means no one owns or can manipulate Bitcoin on their own."
            let page2 = Page()
            page2.order = 1
            page2.components = [page2label1]
            
            let lesson1 = Lesson()
            lesson1.order = 0
            lesson1.pages = [firstPage, page2]
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
    
    @IBAction func lessonTapped(_ sender: UIButton) {
        
        if let thisTappedLesson = sender.accessibilityElements?.first as? Lesson {
            
            self.tappedLesson = thisTappedLesson
            self.performSegue(withIdentifier: "AcademyToOneLesson", sender: self)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "AcademyToOneLesson" {
            if let oneLessonVC = segue.destination as? OneLessonViewController {
                oneLessonVC.thisLesson = self.tappedLesson
                oneLessonVC.coreVC = self.coreVC
            }
        }
    }
    
    func changeColors() {
        self.view.backgroundColor = Colors.getColor("yelloworblue3")
    }
    
}
