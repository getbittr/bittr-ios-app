//
//  ArticleViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class ArticleViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    // UI elements
    @IBOutlet weak var oneArticleTableView: UITableView!
    @IBOutlet weak var oneArticleHeaderView: UIView!
    @IBOutlet weak var oneArticleImage: UIImageView!
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var imageSpinner: UIActivityIndicatorView!
    
    // Article and image
    var article:Article?
    var headerImage:UIImage?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Sort text
        if article?.category == "faq" {
            article?.text.sort(by: { text1, text2 in
                (text1["order"] as! Int) < (text2["order"] as! Int)
            })
        }

        // Table view
        oneArticleTableView.delegate = self
        oneArticleTableView.dataSource = self
        oneArticleTableView.rowHeight = UITableView.automaticDimension
        
        // Button titles
        downButton.setTitle("", for: .normal)
        
        // Set image
        if let actualHeaderImage = headerImage {
            oneArticleImage.image = actualHeaderImage
        } else {
            if let actualData = CacheManager.getImage(key: self.article?.image ?? "") {
                oneArticleImage.image = UIImage(data: actualData)
            }
        }
        
        // Download image if needed
        if oneArticleImage.image == nil, self.article?.image != "" {
            
            self.imageSpinner.startAnimating()
            let session = URLSession(configuration: .default)
            let downloadPicTask = session.dataTask(with: URL(string: self.article?.image ?? "")!) { (data, response, error) in
                if let e = error {
                    print("Error downloading picture: \(e)")
                } else {
                    if let res = response as? HTTPURLResponse {
                        //print("Downloaded picture with response code \(res.statusCode)")
                        if let imageData = data {
                            let image = UIImage(data: imageData)
                            // Do something with your image.
                            DispatchQueue.main.async {
                                self.imageSpinner.stopAnimating()
                                self.oneArticleImage.image = image
                                
                                // Store image in cache.
                                let imageSize = image!.size.height * image!.size.width
                                let imageDownsize = 1000000 / imageSize
                                var imageData:Data?
                                if imageDownsize < 1 {
                                    imageData = image!.jpegData(compressionQuality: imageDownsize)!
                                } else {
                                    imageData = image!.jpegData(compressionQuality: 1)!
                                }
                                if let actualImageData = imageData {
                                    CacheManager.storeImageInCache(key: self.article!.image, data: actualImageData)
                                }
                            }
                        } else {
                            print("Couldn't get image: Image is nil")
                        }
                    } else {
                        print("Couldn't get response code for some reason")
                    }
                }
            }
            downloadPicTask.resume()
        }
        
        self.changeColors()
    }
    
    override func viewDidLayoutSubviews() {
        
        if let headerView = oneArticleTableView.tableHeaderView {
            let height = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
            var headerFrame = headerView.frame
            if height != headerFrame.size.height {
                headerFrame.size.height = height
                headerView.frame = headerFrame
                oneArticleTableView.tableHeaderView = headerView
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
