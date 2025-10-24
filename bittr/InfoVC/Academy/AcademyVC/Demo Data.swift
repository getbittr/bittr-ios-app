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
        firstLabel.type = .label
        firstLabel.text = "Bitcoin was introduced by <b>Satoshi Nakamoto</b> to create a new kind of digital money."
        let secondLabel = Component()
        secondLabel.type = .label
        secondLabel.text = "The idea was for people to send payments directly to each other without using a bank or other middleman."
        
        let firstPage = Page()
        firstPage.components = [firstLabel, secondLabel]
        
        let page2label1 = Component()
        page2label1.type = .label
        page2label1.text = "Unlike fiat money, bitcoin isn’t controlled by any one group or government. It’s <b>decentralized</b> and follows strict rules that keep it running."
        
        let page2label2 = Component()
        page2label2.type = .label
        page2label2.text = "This means no one owns or can manipulate bitcoin on their own."
        
        let page2 = Page()
        page2.components = [page2label1, page2label2]
        
        let page3label1 = Component()
        page3label1.type = .label
        page3label1.text = "Just like other money, bitcoin can be used to pay for products and services."
        
        let page3label2 = Component()
        page3label2.type = .label
        page3label2.text = "To send bitcoin, all you need is the recipient’s address."
        
        let page3 = Page()
        page3.components = [page3label1, page3label2]
        
        let page4label1 = Component()
        page4label1.type = .label
        page4label1.text = "Transactions are stored in blocks on the <b>blockchain</b>; a public ledger everyone can see."
        
        let page4label2 = Component()
        page4label2.type = .label
        page4label2.text = "Transactions are usually confirmed within 10 minutes - significantly faster than traditional systems."
        
        let page4 = Page()
        page4.components = [page4label1, page4label2]
        
        let page5label1 = Component()
        page5label1.type = .label
        page5label1.text = "Supply is limited: only <b>21 million</b> bitcoin will ever exist. That makes it scarce and valuable."
        
        let page5label2 = Component()
        page5label2.type = .label
        page5label2.text = "New bitcoin gets <b>mined</b> through the process of helping add new transactions to the blockchain."
        
        let page5 = Page()
        page5.components = [page5label1, page5label2]
        
        let lesson1 = Lesson()
        lesson1.pages = [firstPage, page2, page3, page4, page5]
        lesson1.title = "What is bitcoin?"
        lesson1.id = "whatisbitcoin"
        
        let l2p1c1 = Component()
        l2p1c1.type = .label
        l2p1c1.text = "A bitcoin can be broken down into <b>100 million</b> units called <b>satoshis</b>."
        
        let l2p1c2 = Component()
        l2p1c2.type = .label
        l2p1c2.text = "They're named after bitcoin’s creator, Satoshi Nakamoto."
        
        let l2p1c3 = Component()
        l2p1c3.type = .label
        l2p1c3.text = "So 1 bitcoin equals 100,000,000 satoshis (or sats)."
        
        let lesson2page1 = Page()
        lesson2page1.components = [l2p1c1, l2p1c2, l2p1c3]
        
        
        let l2p2c1 = Component()
        l2p2c1.type = .label
        l2p2c1.text = "For a transaction of 0.000021453 bitcoin, we speak of 21,453 sats."
        
        let l2p2c2 = Component()
        l2p2c2.type = .label
        l2p2c2.text = "This makes bitcoin more practical for everyday use, like coffee purchases or online microtransactions."
        
        let l2p2c3 = Component()
        l2p2c3.type = .label
        l2p2c3.text = "With a bitcoin being worth over 100,000 €, the satoshi allows you to send or receive tiny amounts."
        
        let l2p2 = Page()
        l2p2.components = [l2p2c1, l2p2c2, l2p2c3]
        
        
        let l2p3c1 = Component()
        l2p3c1.type = .image
        l2p3c1.url = "https://bittr-notion-bucket.s3.eu-central-2.amazonaws.com/notion-media/22dd2c8de1aa8092b970daaebb69ad2d.png"
        
        let l2p3c2 = Component()
        l2p3c2.type = .label
        l2p3c2.text = "Satoshis are increasingly becoming the standard when speaking of bitcoin amounts. Thanks to their simplicity and intuitiveness."
        
        let l2p3 = Page()
        l2p3.components = [l2p3c1, l2p3c2]
        
        let lesson2 = Lesson()
        lesson2.pages = [lesson2page1, l2p2, l2p3]
        lesson2.title = "What are satoshis?"
        lesson2.id = "whataresatoshis"
        
        
        let l3p1c1 = Component()
        l3p1c1.type = .label
        l3p1c1.text = "A <b>fiat currency</b> is a type of money issued by a government, which isn't backed by a physical commodity like gold."
        
        let l3p1c2 = Component()
        l3p1c2.type = .label
        l3p1c2.text = "Its stability and value depend on the issuing government’s policies and the economy’s health."
        
        let l3p1c3 = Component()
        l3p1c3.type = .label
        l3p1c3.text = "Most widely used currencies today - like the Euro and USD - are forms of fiat currency."
        
        let l3p1 = Page()
        l3p1.components = [l3p1c1, l3p1c2, l3p1c3]
        
        
        let l3p2c1 = Component()
        l3p2c1.type = .label
        l3p2c1.text = "With fiat currency, governments can <b>influence economic activity</b> through monetary policies - like adjusting interest rates and setting reserve requirements for banks."
        
        let l3p2c2 = Component()
        l3p2c2.type = .label
        l3p2c2.text = "Governments can <b>print money</b> as needed - to fund new spending, manage debt, or respond to crises."
        
        let l3p2 = Page()
        l3p2.components = [l3p2c1, l3p2c2]
        
        
        let l3p3c1 = Component()
        l3p3c1.type = .label
        l3p3c1.text = "A main characteristic is that fiat currencies tend toward <b>inflation</b>."
        
        let l3p3c2 = Component()
        l3p3c2.type = .label
        l3p3c2.text = "With governments printing more currency, the money devalues over time."
        
        let l3p3c3 = Component()
        l3p3c3.type = .label
        l3p3c3.text = "External events, like COVID-19, can cause high inflation rates. In extreme cases, fiat currencies can experience <b>hyperinflation</b>."
        
        let l3p3 = Page()
        l3p3.components = [l3p3c1, l3p3c2, l3p3c3]
        
        
        let l3p4c1 = Component()
        l3p4c1.type = .label
        l3p4c1.text = "Fiat currencies are easily portable, divisible, and widely accepted."
        
        let l3p4c2 = Component()
        l3p4c2.type = .label
        l3p4c2.text = "However, the legacy financial systems that underpin them, can create <b>slow processing times</b>, <b>limited availability</b> during weekends or holidays, and <b>chargeback risks</b> for merchants."
        
        let l3p4 = Page()
        l3p4.components = [l3p4c1, l3p4c2]
        
        
        let l3p5c1 = Component()
        l3p5c1.type = .label
        l3p5c1.text = "Bitcoin is an alternative to fiat currency - retaining its useful properties while addressing its limitations."
        
        let l3p5c2 = Component()
        l3p5c2.type = .label
        l3p5c2.text = "It's <b>highly portable and divisible</b>. It has a <b>finite, predictable supply</b>, offering protection against inflation. Its value isn’t tied to the economic stability of any country."
        
        let l3p5c3 = Component()
        l3p5c3.type = .label
        l3p5c3.text = "Though, its utility as a payment method is still limited by factors such as a lack of merchant acceptance."
        
        let l3p5 = Page()
        l3p5.components = [l3p5c1, l3p5c2, l3p5c3]
        
        
        let l3p6c1 = Component()
        l3p6c1.type = .label
        l3p6c1.text = "Here's a chart that compares bitcoin's characteristics to fiat currency and gold."
        
        let l3p6c2 = Component()
        l3p6c2.type = .image
        l3p6c2.url = "https://bittr-notion-bucket.s3.eu-central-2.amazonaws.com/notion-media/1fbd2c8de1aa81a89978e610bbcdd8fd.webp"
        
        let l3p6 = Page()
        l3p6.components = [l3p6c1, l3p6c2]
        
        
        let lesson3 = Lesson()
        lesson3.order = 2
        lesson3.pages = [l3p1, l3p2, l3p3, l3p4, l3p5, l3p6]
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
