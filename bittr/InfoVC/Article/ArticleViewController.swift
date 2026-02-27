//
//  ArticleViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit
import Sentry

class ArticleViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    // UI elements
    @IBOutlet weak var oneArticleTableView: UITableView!
    @IBOutlet weak var oneArticleHeaderView: UIView!
    @IBOutlet weak var oneArticleImage: UIImageView!
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var imageSpinner: UIActivityIndicatorView!
    
    // Article and image
    var article:Article?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Sort text
        if self.article?.category == "faq" {
            self.article!.text.sort(by: { text1, text2 in
                (text1["order"] as! Int) < (text2["order"] as! Int)
            })
        }

        // Table view
        self.oneArticleTableView.delegate = self
        self.oneArticleTableView.dataSource = self
        self.oneArticleTableView.rowHeight = UITableView.automaticDimension
        self.oneArticleTableView.isPrefetchingEnabled = false
        
        // Button titles
        self.downButton.setTitle("", for: .normal)
        
        // Set image
        if let actualData = CacheManager.getImage(key: self.article?.image ?? "") {
            self.oneArticleImage.image = UIImage(data: actualData)
        }
        
        // Download image if needed
        if self.oneArticleImage.image == nil, self.article?.image != "" {
            
            self.imageSpinner.startAnimating()
            
            Task {
                if let imageData = await self.getImage(urlString: self.article?.image ?? "") {
                    let image = UIImage(data: imageData)
                    DispatchQueue.main.async {
                        self.imageSpinner.stopAnimating()
                        self.oneArticleImage.image = image
                    }
                }
            }
        }
        
        self.changeColors()
    }
    
    override func viewDidLayoutSubviews() {
        
        if let headerView = self.oneArticleTableView.tableHeaderView {
            let height = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
            var headerFrame = headerView.frame
            if height != headerFrame.size.height {
                headerFrame.size.height = height
                headerView.frame = headerFrame
                self.oneArticleTableView.tableHeaderView = headerView
            }
        }
        
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.article?.text.count ?? 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "OneArticleCell", for: indexPath) as? OneArticleTableViewCell
        
        if let actualCell = cell {
            
            actualCell.setText(cellText: self.article?.text[indexPath.row]["text"] as? String ?? "")
            
            return actualCell
        }
        
        return UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    func changeColors() {
        
        if CacheManager.darkModeIsOn() {
            self.view.backgroundColor = Colors.getColor("grey3orblue1")
        }
    }
    
}

extension UIViewController {
    
    func getImage(urlString:String) async -> Data? {
        
        do {
            var request = URLRequest(url: URL(string: urlString)!)
            request.httpMethod = "GET"
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard response is HTTPURLResponse else {
                return nil
            }
            
            // Store image in cache.
            let image = UIImage(data: data)!
            CacheManager.storeImageInCache(key: urlString, data: image.resizeImage())
            
            return image.resizeImage()
        } catch {
            Log.info("Some error occurred fetching image. \(error.localizedDescription)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "InfoViewController row 294", key: "context")
                }
            }
            if let actualData = CacheManager.getImage(key: urlString) {
                return actualData
            } else {
                return nil
            }
        }
    }
    
}

extension UIImage {
    
    func resizeImage() -> Data {
        
        // Don't enlarge the image.
        if 1080 > self.size.width {
            Log.info("Image is narrower than 1080 pixels. No need to resize.")
            return self.jpegData(compressionQuality: 1)!
        }
        
        // Check the current ratio.
        let widthRatio = 1080 / self.size.width
        
        // Calculate new size.
        let newSize = CGSize(width: self.size.width * widthRatio, height: self.size.height * widthRatio)
        
        // This is the rect that we've calculated out and this is what is actually used below
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        // Actually do the resizing to the rect using the ImageContext stuff
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: rect)
        var newImage = UIGraphicsGetImageFromCurrentImageContext()
        if newImage == nil {
            Log.info("Image could not be downsized.")
            newImage = self
        }
        UIGraphicsEndImageContext()
        
        return newImage!.jpegData(compressionQuality: 1)!
    }
}
