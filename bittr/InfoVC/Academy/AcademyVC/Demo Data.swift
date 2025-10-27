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
        lesson1.image = "whatisbitcoin"
        
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
        lesson2.image = "whataresatoshis"
        
        
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
        lesson3.image = "theproblemwithfiatcurrencies"
        
        
        let l4p1c1 = Component()
        l4p1c1.type = .label
        l4p1c1.text = "Bitcoin has grown from a niche idea into a <b>standalone asset class</b>."
        
        let l4p1c2 = Component()
        l4p1c2.type = .label
        l4p1c2.text = "Why do private investors, family offices, and institutions now look at bitcoin?"
        
        let l4p1 = Page()
        l4p1.components = [l4p1c1, l4p1c2]
        
        
        let l4p2c1 = Component()
        l4p2c1.type = .label
        l4p2c1.text = "<b>Diversification</b>"
        
        let l4p2c2 = Component()
        l4p2c2.type = .label
        l4p2c2.text = "Long-term data shows that bitcoin often moves differently from traditional assets."
        
        let l4p2c3 = Component()
        l4p2c3.type = .label
        l4p2c3.text = "That’s what many investors want - building blocks that don’t rise and fall at the same time."
        
        let l4p2 = Page()
        l4p2.components = [l4p2c1, l4p2c2, l4p2c3]
        
        
        let l4p3c1 = Component()
        l4p3c1.type = .label
        l4p3c1.text = "<b>Preserving value long-term</b>"
        
        let l4p3c2 = Component()
        l4p3c2.type = .label
        l4p3c2.text = "Bitcoin's predictable scarcity protects against inflation. This makes it interesting for retirement and intergenerational wealth."
        
        let l4p3c3 = Component()
        l4p3c3.type = .label
        l4p3c3.text = "Bitcoin is volatile in the short term. The long-term case is measured in years and decades, not weeks."
        
        let l4p3 = Page()
        l4p3.components = [l4p3c1, l4p3c2, l4p3c3]
        
        
        let l4p4c1 = Component()
        l4p4c1.type = .label
        l4p4c1.text = "<b>Future utility</b>"
        
        let l4p4c2 = Component()
        l4p4c2.type = .label
        l4p4c2.text = "As more infrastructure appears, practical use of bitcoin is growing. This gives more reasons to get in early."
        
        let l4p4c3 = Component()
        l4p4c3.type = .label
        l4p4c3.text = "You can transfer value without a middleman, globally, 24/7. And more lenders now accept bitcoin as collateral."
        
        let l4p4 = Page()
        l4p4.components = [l4p4c1, l4p4c2, l4p4c3]
        
        
        let l4p5c1 = Component()
        l4p5c1.type = .label
        l4p5c1.text = "<b>Skepticism of centralized finance</b>"
        
        let l4p5c2 = Component()
        l4p5c2.type = .label
        l4p5c2.text = "Many investors want less dependency on third parties. With bitcoin, you hold your own keys and control your own coins."
        
        let l4p5c3 = Component()
        l4p5c3.type = .label
        l4p5c3.text = "Transactions are hard to block or reverse. And the decentralized, global system is much harder to compromise in hacking attempts."
        
        let l4p5 = Page()
        l4p5.components = [l4p5c1, l4p5c2, l4p5c3]
        
        
        let l4p6c1 = Component()
        l4p6c1.type = .label
        l4p6c1.text = "Bitcoin isn’t for everyone. If you need perfect peace of mind and hate price swings, keep the allocation small."
        
        let l4p6c2 = Component()
        l4p6c2.type = .label
        l4p6c2.text = "If you do invest, you’ll need a long time horizon, the ability to stay calm during drawdowns, and clear rules for security and risk management."
        
        let l4p6 = Page()
        l4p6.components = [l4p6c1, l4p6c2]
        
        let lesson4 = Lesson()
        lesson4.order = 3
        lesson4.pages = [l4p1, l4p2, l4p3, l4p4, l4p5, l4p6]
        lesson4.title = "Why do people invest in bitcoin?"
        lesson4.id = "whydopeopleinvestinbitcoin"
        lesson4.image = "whydopeopleinvest"
        
        
        let l5p1c1 = Component()
        l5p1c1.type = .label
        l5p1c1.text = "Volatility measures how much an asset’s price varies around its average over time."
        
        let l5p1c2 = Component()
        l5p1c2.type = .label
        l5p1c2.text = "Assets with frequent, significant price fluctuations are considered more volatile."
        
        let l5p1 = Page()
        l5p1.components = [l5p1c1, l5p1c2]
        
        
        let l5p2c1 = Component()
        l5p2c1.type = .label
        l5p2c1.text = "Bitcoin has grown enormously over the years, but is also known for rapid price swings."
        
        let l5p2c2 = Component()
        l5p2c2.type = .label
        l5p2c2.text = "This volatility offers potential for impressive returns, but also poses risks associated with short-term price unpredictability."
        
        let l5p2c3 = Component()
        l5p2c3.type = .label
        l5p2c3.text = "What drives this volatility and what could it mean for bitcoin’s future?"
        
        let l5p2 = Page()
        l5p2.components = [l5p2c1, l5p2c2, l5p2c3]
        
        
        let l5p3c1 = Component()
        l5p3c1.type = .label
        l5p3c1.text = "As a relatively new asset, bitcoin’s markets react sharply to changes in demand."
        
        let l5p3c2 = Component()
        l5p3c2.type = .label
        l5p3c2.text = "The role bitcoin will ultimately play in the global financial system is still being defined."
        
        let l5p3c3 = Component()
        l5p3c3.type = .label
        l5p3c3.text = "Each new regulation, company adoption, or economic event can influence its perceived value."
        
        let l5p3 = Page()
        l5p3.components = [l5p3c1, l5p3c2, l5p3c3]
        
        
        let l5p4c1 = Component()
        l5p4c1.type = .label
        l5p4c1.text = "As a currency, bitcoin's value isn’t tied to any cash flows. Its price is based solely on demand."
        
        let l5p4c2 = Component()
        l5p4c2.type = .label
        l5p4c2.text = "For traditional assets, future cash flows offer a way to predict their value - creating a perception of stability."
        
        let l5p4c3 = Component()
        l5p4c3.type = .label
        l5p4c3.text = "Bitcoin’s value depends on its acceptance as part of the global economy, which is harder to model."
        
        let l5p4 = Page()
        l5p4.components = [l5p4c1, l5p4c2, l5p4c3]
        
        
        let l5p5c1 = Component()
        l5p5c1.type = .label
        l5p5c1.text = "Bitcoin’s market cap is around 2 trillion USD - a mere fraction of gold’s market cap."
        
        let l5p5c2 = Component()
        l5p5c2.type = .label
        l5p5c2.text = "As such, it takes less buying or selling power to move its price."
        
        let l5p5c3 = Component()
        l5p5c3.type = .label
        l5p5c3.text = "Additionally, some individuals hold large amounts. A single sale by one of these holders can create noticeable price changes."
        
        let l5p5 = Page()
        l5p5.components = [l5p5c1, l5p5c2, l5p5c3]
        
        
        let l5p6c1 = Component()
        l5p6c1.type = .label
        l5p6c1.text = "Finally, unlike assets traded on major centralized exchanges, bitcoin liquidity is spread across many exchanges."
        
        let l5p6c2 = Component()
        l5p6c2.type = .label
        l5p6c2.text = "This leads to price differences and increased price sensitivity on individual platforms."
        
        let l5p6 = Page()
        l5p6.components = [l5p6c1, l5p6c2]
        
        
        let l5p7c1 = Component()
        l5p7c1.type = .label
        l5p7c1.text = "As bitcoin matures, factors causing its volatility today may fade."
        
        let l5p7c2 = Component()
        l5p7c2.type = .label
        l5p7c2.text = "Regulatory clarity is likely to improve over time, reducing uncertainty. As bitcoin’s market cap grows, the impact of individual transactions decreases."
        
        let l5p7c3 = Component()
        l5p7c3.type = .label
        l5p7c3.text = "The development of a more efficient market will allow investors to trade with less price disruption."
        
        let l5p7 = Page()
        l5p7.components = [l5p7c1, l5p7c2, l5p7c3]
        
        
        let lesson5 = Lesson()
        lesson5.order = 4
        lesson5.pages = [l5p1, l5p2, l5p3, l5p4, l5p5, l5p6, l5p7]
        lesson5.title = "Why is bitcoin volatile?"
        lesson5.id = "whyisbitcoinvolatile"
        lesson5.image = "whyisbitcoinvolatile"
        
        
        let l6p1c1 = Component()
        l6p1c1.type = .label
        l6p1c1.text = "<b>Mining</b> is the process through which <b>new bitcoins</b> are generated and added to circulation."
        
        let l6p1c2 = Component()
        l6p1c2.type = .label
        l6p1c2.text = "It’s a digital competition where powerful computers work to <b>confirm bitcoin transactions</b>."
        
        let l6p1c3 = Component()
        l6p1c3.type = .label
        l6p1c3.text = "As miners commit resources (electricity, time, computing power), they make bitcoin highly <b>resistant to attacks</b>."
        
        let l6p1 = Page()
        l6p1.components = [l6p1c1, l6p1c2, l6p1c3]
        
        
        let l6p2c1 = Component()
        l6p2c1.type = .label
        l6p2c1.text = "Every 10 minutes, a new block of bitcoin transactions gets confirmed and added to the blockchain."
        
        let l6p2c2 = Component()
        l6p2c2.type = .label
        l6p2c2.text = "The creation of each block requires the identification of a specific number resulting from a complex mathematical puzzle."
        
        let l6p2c3 = Component()
        l6p2c3.type = .label
        l6p2c3.text = "The first miner to guess the correct number, receives <b>3.125 bitcoin</b> plus all transaction fees paid in the block."
        
        let l6p2 = Page()
        l6p2.components = [l6p2c1, l6p2c2, l6p2c3]
        
        
        let l6p3c1 = Component()
        l6p3c1.type = .label
        l6p3c1.text = "As a miner, you need hardware (called ASICs) specifically designed to mine bitcoin."
        
        let l6p3c2 = Component()
        l6p3c2.type = .label
        l6p3c2.text = "The more computing power you control, the more numbers per second you can guess, the more likely you are to be the first to guess correctly."
        
        let l6p3 = Page()
        l6p3.components = [l6p3c1, l6p3c2]
        
        
        let l6p4c1 = Component()
        l6p4c1.type = .label
        l6p4c1.text = "Through <b>hosted mining</b>, newcomers can participate without handling hardware. A hosting service manages the operations, charging a fee in return."
        
        let l6p4c2 = Component()
        l6p4c2.type = .label
        l6p4c2.text = "Joining a <b>mining pool</b> is another common strategy. Here, multiple miners combine their computational power, and share the rewards proportionally."
        
        let l6p4 = Page()
        l6p4.components = [l6p4c1, l6p4c2]
        
        
        let l6p5c1 = Component()
        l6p5c1.type = .label
        l6p5c1.text = "Each block is linked to the previous one, forming a chain that would be extremely costly to change."
        
        let l6p5c2 = Component()
        l6p5c2.type = .label
        l6p5c2.text = "Hacking the system means you'd need to forever win each block."
        
        let l6p5c3 = Component()
        l6p5c3.type = .label
        l6p5c3.text = "The high reward, extreme complexity, and randomness make the network’s security very strong."
        
        let l6p5 = Page()
        l6p5.components = [l6p5c1, l6p5c2, l6p5c3]
        
        
        let l6p6c1 = Component()
        l6p6c1.type = .label
        l6p6c1.text = "Every four years, the reward per block is halved - in an event called the <b>halving</b>."
        
        let l6p6c2 = Component()
        l6p6c2.type = .label
        l6p6c2.text = "The last satoshi will be mined in 2140, upon which all 21,000,000 bitcoin will be in existence."
        
        let l6p6 = Page()
        l6p6.components = [l6p6c1, l6p6c2]
        
        
        let lesson6 = Lesson()
        lesson6.order = 5
        lesson6.pages = [l6p1, l6p2, l6p3, l6p4, l6p5, l6p6]
        lesson6.title = "What is mining?"
        lesson6.id = "whatismining"
        lesson6.image = "whatismining"
        
        let firstLevel = Level()
        firstLevel.order = 0
        firstLevel.lessons = [lesson1, lesson2, lesson3, lesson4, lesson5, lesson6]
        
        return [firstLevel]
    }
}
