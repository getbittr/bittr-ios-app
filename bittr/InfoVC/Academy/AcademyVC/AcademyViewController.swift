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
            self.coreVC!.downloadedAcademy = self.getDemoData()
            
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
