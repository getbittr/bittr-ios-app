//
//  Demo Data.swift
//  bittr
//
//  Created by Tom Melters on 10/23/25.
//

import UIKit

extension AcademyViewController {
    
    func getDemoData() -> [Level] {
        
        // Demo data
        let firstLabel = Component()
        firstLabel.order = 0
        firstLabel.type = .label
        firstLabel.text = "Bitcoin was introduced by <b>Satoshi Nakamoto</b> to create a new kind of digital money."
        let secondLabel = Component()
        secondLabel.order = 1
        secondLabel.type = .label
        secondLabel.text = "The idea was for people to send payments directly to each other without using a bank or any other middleman."
        let firstPage = Page()
        firstPage.order = 0
        firstPage.components = [firstLabel, secondLabel]
        
        let page2label1 = Component()
        page2label1.order = 0
        page2label1.type = .label
        page2label1.text = "Unlike fiat money, bitcoin isn’t controlled by any one group or government. It’s <b>decentralized</b> and follows strict rules that keep it running."
        
        let page2label2 = Component()
        page2label2.order = 1
        page2label2.type = .label
        page2label2.text = "This means no one owns or can manipulate bitcoin on their own."
        
        let page2 = Page()
        page2.order = 1
        page2.components = [page2label1, page2label2]
        
        let page3label1 = Component()
        page3label1.order = 0
        page3label1.type = .label
        page3label1.text = "Just like other money, bitcoin can be used to pay for products and services."
        
        let page3label2 = Component()
        page3label2.order = 1
        page3label2.type = .label
        page3label2.text = "To send Bitcoin, all you need is the recipient’s address."
        
        let page3 = Page()
        page3.order = 2
        page3.components = [page3label1, page3label2]
        
        let page4label1 = Component()
        page4label1.order = 0
        page4label1.type = .label
        page4label1.text = "Transactions are stored in blocks on the <b>blockchain</b>; a public ledger everyone can see."
        
        let page4label2 = Component()
        page4label2.order = 1
        page4label2.type = .label
        page4label2.text = "Transactions are usually confirmed in about 10 minutes. That's significantly faster than traditional systems."
        
        let page4 = Page()
        page4.order = 3
        page4.components = [page4label1, page4label2]
        
        let page5label1 = Component()
        page5label1.order = 0
        page5label1.type = .label
        page5label1.text = "Supply is limited: only <b>21 million</b> bitcoin will ever exist. That makes it scarce and valuable."
        
        let page5label2 = Component()
        page5label2.order = 1
        page5label2.type = .label
        page5label2.text = "New bitcoin gets <b>mined</b> through the process of helping add new transactions to the blockchain."
        
        let page5 = Page()
        page5.order = 4
        page5.components = [page5label1, page5label2]
        
        let lesson1 = Lesson()
        lesson1.order = 0
        lesson1.pages = [firstPage, page2, page3, page4, page5]
        lesson1.title = "What is bitcoin?"
        lesson1.id = "whatisbitcoin"
        
        let l2p1c1 = Component()
        l2p1c1.order = 0
        l2p1c1.type = .label
        l2p1c1.text = "A bitcoin can be broken down into <b>100 million</b> smaller units called <b>satoshis</b>."
        
        let l2p1c2 = Component()
        l2p1c2.order = 1
        l2p1c2.type = .label
        l2p1c2.text = "This is named after bitcoin’s creator, Satoshi Nakamoto."
        
        let l2p1c3 = Component()
        l2p1c3.order = 1
        l2p1c3.type = .label
        l2p1c3.text = "So 1 bitcoin equals exactly 100,000,000 satoshis (or sats)."
        
        let lesson2page1 = Page()
        lesson2page1.order = 0
        lesson2page1.components = [l2p1c1, l2p1c2, l2p1c3]
        
        
        let l2p2c1 = Component()
        l2p2c1.order = 0
        l2p2c1.type = .label
        l2p2c1.text = "For a transaction of 0.000021453 bitcoin, it’s much easier to speak of 21,453 sats."
        
        let l2p2c2 = Component()
        l2p2c2.order = 1
        l2p2c2.type = .label
        l2p2c2.text = "This makes bitcoin more practical for everyday use, like coffee purchases or online microtransactions."
        
        let l2p2c3 = Component()
        l2p2c3.order = 1
        l2p2c3.type = .label
        l2p2c3.text = "With one bitcoin being worth over 100,000 €, the satoshi allows you to send or receive tiny amounts."
        
        let l2p2 = Page()
        l2p2.order = 1
        l2p2.components = [l2p2c1, l2p2c2, l2p2c3]
        
        
        let l2p3c1 = Component()
        l2p3c1.order = 0
        l2p3c1.type = .image
        l2p3c1.url = "https://bittr-notion-bucket.s3.eu-central-2.amazonaws.com/notion-media/22dd2c8de1aa8092b970daaebb69ad2d.png"
        
        let l2p3 = Page()
        l2p3.order = 2
        l2p3.components = [l2p3c1]
        
        
        let lesson2 = Lesson()
        lesson2.order = 1
        lesson2.pages = [lesson2page1, l2p2, l2p3]
        lesson2.title = "What are satoshis?"
        lesson2.id = "whataresatoshis"
        
        let lesson3 = Lesson()
        lesson3.order = 2
        lesson3.pages = [firstPage]
        lesson3.title = "The problem with fiat currencies"
        lesson3.id = "theproblemwithfiatcurrencies"
        let lesson4 = Lesson()
        lesson4.order = 3
        lesson4.pages = [firstPage]
        lesson4.title = "Why do people invest in bitcoin?"
        lesson4.id = "whydopeopleinvestinbitcoin"
        let lesson5 = Lesson()
        lesson5.order = 4
        lesson5.pages = [firstPage]
        lesson5.title = "Why is bitcoin volatile?"
        lesson5.id = "whyisbitcoinvolatile"
        let lesson6 = Lesson()
        lesson6.order = 5
        lesson6.pages = [firstPage]
        lesson6.title = "What is mining?"
        lesson6.id = "whatismining"
        
        let firstLevel = Level()
        firstLevel.order = 0
        firstLevel.lessons = [lesson1, lesson2, lesson3, lesson4, lesson5, lesson6]
        
        return [firstLevel]
    }
}
