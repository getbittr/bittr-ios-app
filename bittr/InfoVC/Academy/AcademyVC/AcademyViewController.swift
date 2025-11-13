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
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerLabel: UILabel!
    
    // Variables
    var coreVC:CoreViewController?
    var tappedLesson:Lesson?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Table view.
        self.academyTableView.delegate = self
        self.academyTableView.dataSource = self
        self.academyTableView.contentInset = UIEdgeInsets(top: 80, left: 0, bottom: 100, right: 0)
        self.academyTableView.rowHeight = UITableView.automaticDimension
        self.academyTableView.estimatedRowHeight = 300
        
        // Get Academy levels.
        self.getLevels()
        self.changeColors()
        self.setLanguage()
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
    
    override func viewDidLayoutSubviews() {
        
        // Set header view.
        if let newHeaderView = self.academyTableView.tableHeaderView {
            let height = newHeaderView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
            var headerFrame = newHeaderView.frame
            if height != headerFrame.size.height {
                headerFrame.size.height = height
                newHeaderView.frame = headerFrame
                self.academyTableView.tableHeaderView = newHeaderView
            }
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
            
            // Count completed lessons per level.
            var completedLessons = 0
            for eachLesson in cell.thisLevel.lessons {
                if CacheManager.getCompletedLessons().contains(eachLesson.id) {
                    completedLessons += 1
                }
            }
            cell.countLabel.text = "\(completedLessons) of \(cell.thisLevel.lessons.count)"
            
            // Set previous level.
            cell.previousLevel = {
                if indexPath.row > 0 {
                    return self.coreVC!.downloadedAcademy![indexPath.row - 1]
                } else {
                    return nil
                }
            }()
            
            // Reload level lessons.
            cell.reloadLessons()
            cell.layoutIfNeeded()
            
            return cell
        } else {
            return UITableViewCell()
        }
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setupblur"), object: nil, userInfo: nil) as Notification)
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
                oneLessonVC.academyVC = self
            }
        }
    }
    
    func changeColors() {
        self.view.backgroundColor = Colors.getColor("yelloworblue3")
        self.headerLabel.textColor = Colors.getColor("blackorwhite")
    }
    
    func setLanguage() {
        self.headerLabel.text = Language.getWord(withID: "academyheader")
    }
    
}
