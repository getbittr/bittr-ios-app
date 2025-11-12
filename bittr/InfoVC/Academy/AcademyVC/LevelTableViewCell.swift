//
//  LevelTableViewCell.swift
//  bittr
//
//  Created by Tom Melters on 10/21/25.
//

import UIKit

class LevelTableViewCell: UITableViewCell, UICollectionViewDelegate, UICollectionViewDataSource {
    
    // UI elements
    @IBOutlet weak var cellHeight: NSLayoutConstraint!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var levelIcon: UIImageView!
    @IBOutlet weak var levelLabel: UILabel!
    @IBOutlet weak var countLabel: UILabel!
    @IBOutlet weak var lessonsCollectionView: UICollectionView!
    @IBOutlet weak var lessonsCollectionViewHeight: NSLayoutConstraint!
    
    // Variables
    var thisLevel = Level()
    var previousLevel: Level?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        // Style card.
        self.cardView.layer.cornerRadius = 13
        self.cardView.setShadow()
        
        // Collection view.
        self.lessonsCollectionView.delegate = self
        self.lessonsCollectionView.dataSource = self
        self.lessonsCollectionView.collectionViewLayout = self.createCompositionalLayout()
        self.lessonsCollectionView.isScrollEnabled = false
        
        // Color management.
        self.changeColors()
    }
    
    func createCompositionalLayout() -> UICollectionViewCompositionalLayout {
        
        // Identify individual cell size.
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(100)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        // Identify that there should be 3 cells in each row, with spacing 5.
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(100)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: 3)
        group.interItemSpacing = .fixed(5)

        // Identify that the spacing between rows is 20.
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 20

        let layout = UICollectionViewCompositionalLayout(section: section)
        return layout
    }
    
    func reloadLessons() {
        self.lessonsCollectionView.reloadData()
        self.lessonsCollectionView.collectionViewLayout.invalidateLayout()
        self.lessonsCollectionView.layoutIfNeeded()

        let height = self.lessonsCollectionView.collectionViewLayout.collectionViewContentSize.height
        if height > 0 {
            self.lessonsCollectionViewHeight.constant = height
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        self.lessonsCollectionViewHeight.constant = 0
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        self.lessonsCollectionView.collectionViewLayout.invalidateLayout()
        self.lessonsCollectionView.layoutIfNeeded()
        
        let newHeight = self.lessonsCollectionView.collectionViewLayout.collectionViewContentSize.height
        if newHeight.isFinite && newHeight != self.lessonsCollectionViewHeight.constant {
            self.lessonsCollectionViewHeight.constant = newHeight
            
            self.setNeedsLayout()
            self.contentView.layoutIfNeeded()
        }
        
        self.cellHeight.constant = newHeight + 100
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        return self.thisLevel.lessons.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "LessonCell", for: indexPath) as? LessonCollectionViewCell {
            
            // Set lesson, title, and button.
            let thisLesson = self.thisLevel.lessons[indexPath.row]
            cell.lessonTitle.text = thisLesson.title
            cell.lessonButton.accessibilityElements = [thisLesson]
            
            // Set lesson image.
            cell.lessonImage.image = nil
            if thisLesson.image != nil {
                cell.lessonImage.image = UIImage(named: thisLesson.image!)
            }
            
            // Check previous lesson.
            let previousLesson:Lesson? = {
                if indexPath.row > 0 {
                    return self.thisLevel.lessons[indexPath.row - 1]
                } else if self.previousLevel != nil {
                    return self.previousLevel!.lessons.last!
                } else {
                    return nil
                }
            }()
            
            // Check if lesson is available.
            if CacheManager.getCompletedLessons().contains(thisLesson.id) || previousLesson == nil || (previousLesson != nil && CacheManager.getCompletedLessons().contains(previousLesson!.id)) {
                // Lesson is available to user.
                cell.removeBlur()
                cell.lessonButton.alpha = 1
                
                if CacheManager.getCompletedLessons().contains(thisLesson.id) {
                    // Lesson has been completed.
                    cell.iconCheck.alpha = 1
                } else {
                    // Lesson has not yet been completed.
                    cell.iconCheck.alpha = 0
                }
            } else {
                // Lesson is not yet available to user.
                cell.addBlur()
                cell.lessonButton.alpha = 0
                cell.iconCheck.alpha = 0
            }
            
            return cell
        } else {
            return UICollectionViewCell()
        }
    }
    
    func changeColors() {
        
        self.cardView.backgroundColor = Colors.getColor("yelloworblue2")
        self.levelLabel.textColor = Colors.getColor("whiteoryellow")
        self.countLabel.textColor = Colors.getColor("whiteoryellow")
        
        if CacheManager.darkModeIsOn() {
            self.levelIcon.image = UIImage(named: "iconacademyyellow")
        } else {
            self.levelIcon.image = UIImage(named: "iconacademy")
        }
    }
    
    
}
