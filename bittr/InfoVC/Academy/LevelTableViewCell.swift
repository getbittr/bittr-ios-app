//
//  LevelTableViewCell.swift
//  bittr
//
//  Created by Tom Melters on 10/21/25.
//

import UIKit

class LevelTableViewCell: UITableViewCell, UICollectionViewDelegate, UICollectionViewDataSource {
    
    // UI elements
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var levelIcon: UIImageView!
    @IBOutlet weak var levelLabel: UILabel!
    @IBOutlet weak var countLabel: UILabel!
    @IBOutlet weak var lessonsCollectionView: UICollectionView!
    @IBOutlet weak var lessonsCollectionViewHeight: NSLayoutConstraint!
    
    // Variables
    var thisLevel = Level()
    
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
    
    override func layoutSubviews() {
        super.layoutSubviews()

        self.lessonsCollectionView.collectionViewLayout.invalidateLayout()
        self.lessonsCollectionView.layoutIfNeeded()
        
        let newHeight = self.lessonsCollectionView.collectionViewLayout.collectionViewContentSize.height
        if newHeight.isFinite && newHeight != self.lessonsCollectionViewHeight.constant {
            self.lessonsCollectionViewHeight.constant = newHeight
            // Tell Auto Layout this cell’s constraints changed
            self.setNeedsLayout()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        return self.thisLevel.lessons.count
    }
    
    func calculateCellWidth() -> CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let collectionViewWidth = screenWidth - 70
        let cellWidth = (collectionViewWidth - 10)/3
        return cellWidth
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "LessonCell", for: indexPath) as? LessonCollectionViewCell {
            
            //cell.cardWidth.constant = self.calculateCellWidth() - 40
            //cell.cardHeight.constant = self.calculateCellWidth() - 40
            cell.lessonTitle.text = self.thisLevel.lessons[indexPath.row].title
            
            return cell
        } else {
            return UICollectionViewCell()
        }
    }
    
    
}
