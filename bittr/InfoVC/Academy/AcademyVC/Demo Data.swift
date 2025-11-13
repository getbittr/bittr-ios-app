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
        l6p4c1.text = "How can you start mining bitcoin?"
        
        let l6p4c2 = Component()
        l6p4c2.type = .label
        l6p4c2.text = "A popular option for newcomers is <b>hosted mining</b>. A hosting service manages the hardware for you, charging a fee in return."
        
        let l6p4c3 = Component()
        l6p4c3.type = .label
        l6p4c3.text = "Joining a <b>mining pool</b> is another common strategy. Here, multiple miners combine their computational power, and share the rewards proportionally."
        
        let l6p4 = Page()
        l6p4.components = [l6p4c1, l6p4c2, l6p4c3]
        
        
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
        lesson6.pages = [l6p1, l6p2, l6p3, l6p5, l6p6, l6p4]
        lesson6.title = "What is mining?"
        lesson6.id = "whatismining"
        lesson6.image = "whatismining"
        
        let level1 = Level()
        level1.order = 0
        level1.lessons = [lesson1, lesson2, lesson3, lesson4, lesson5, lesson6]
        
        
        let l2l1p1c1 = Component()
        l2l1p1c1.type = .label
        l2l1p1c1.text = "A <b>seed or recovery phrase</b> is a sequence of <b>12 or 24 words</b> used to recover your bitcoin wallet."
        
        let l2l1p1c2 = Component()
        l2l1p1c2.type = .label
        l2l1p1c2.text = "You can use it to regain access to your bitcoin if your wallet is lost, damaged, or otherwise compromised."
        
        let l2l1p1c3 = Component()
        l2l1p1c3.type = .label
        l2l1p1c3.text = "It should be stored <b>offline</b> and <b>never be shared</b> with anyone."
        
        let l2l1p1 = Page()
        l2l1p1.components = [l2l1p1c1, l2l1p1c2, l2l1p1c3]
        
        
        let l2l1p2c1 = Component()
        l2l1p2c1.type = .image
        l2l1p2c1.url = "https://bittr-notion-bucket.s3.eu-central-2.amazonaws.com/notion-media/1fbd2c8de1aa814992bedf45012b0a72.png"
        
        let l2l1p2c2 = Component()
        l2l1p2c2.type = .label
        l2l1p2c2.text = "You receive the seed phrase when creating a <b>self-custodial</b> wallet."
        
        let l2l1p2c3 = Component()
        l2l1p2c3.type = .label
        l2l1p2c3.text = "Since there's no third party, losing your seed phrase means losing access to your bitcoin permanently."
        
        let l2l1p2 = Page()
        l2l1p2.components = [l2l1p2c1, l2l1p2c2, l2l1p2c3]
        
        
        let l2l1p3c1 = Component()
        l2l1p3c1.type = .label
        l2l1p3c1.text = "The most common type of seed phrase is <b>BIP 39</b>, which is made up from a predefined list of <b>2048 English words</b>."
        
        let l2l1p3c2 = Component()
        l2l1p3c2.type = .label
        l2l1p3c2.text = "This provides compatibility across most wallets."
        
        let l2l1p3 = Page()
        l2l1p3.components = [l2l1p3c1, l2l1p3c2]
        
        
        let l2l1p4c1 = Component()
        l2l1p4c1.type = .image
        l2l1p4c1.url = "https://bittr-notion-bucket.s3.eu-central-2.amazonaws.com/notion-media/1fbd2c8de1aa81dea5cfc3c4ea6f03df.webp"
        
        let l2l1p4c2 = Component()
        l2l1p4c2.type = .label
        l2l1p4c2.text = "Keep your seed phrase <b>offline</b> in a physical format, like on paper. Never store it online."
        
        let l2l1p4c3 = Component()
        l2l1p4c3.type = .label
        l2l1p4c3.text = "You could create multiple copies and store them in secure locations, like safes."
        
        let l2l1p4 = Page()
        l2l1p4.components = [l2l1p4c1, l2l1p4c2, l2l1p4c3]
        
        
        let l2l1p5c1 = Component()
        l2l1p5c1.type = .label
        l2l1p5c1.text = "While seed phrases are a powerful self-custody tool, mishandling them can lead to loss."
        
        let l2l1p5c2 = Component()
        l2l1p5c2.type = .label
        l2l1p5c2.text = "Transfer your bitcoin to a new wallet if you suspect your seed phrase is compromised."
        
        let l2l1p5 = Page()
        l2l1p5.components = [l2l1p5c1, l2l1p5c2]
        
        
        let l2l1 = Lesson()
        l2l1.title = "What is a seedphrase?"
        l2l1.id = "whatisaseedphrase"
        l2l1.image = "seedphrase"
        l2l1.pages = [l2l1p1, l2l1p2, l2l1p3, l2l1p4, l2l1p5]
        
        
        let l2l2p1c1 = Component()
        l2l2p1c1.type = .label
        l2l2p1c1.text = "Almost <b>20 million</b> bitcoin (95 % of the total supply) have already been mined."
        
        let l2l2p1c2 = Component()
        l2l2p1c2.type = .label
        l2l2p1c2.text = "Though bitcoin is not a company and has no owner, it’s fairly possible to estimate who holds how much."
        
        let l2l2p1 = Page()
        l2l2p1.components = [l2l2p1c1, l2l2p1c2]
        
        
        let l2l2p2c1 = Component()
        l2l2p2c1.type = .label
        l2l2p2c1.text = "Around 66 % of bitcoin is held by <b>individuals</b>."
        
        let l2l2p2c2 = Component()
        l2l2p2c2.type = .label
        l2l2p2c2.text = "The largest one is <b>Coinbase</b>, which holds almost 3 million bitcoin (15 %) on behalf of its customers."
        
        let l2l2p2 = Page()
        l2l2p2.components = [l2l2p2c1, l2l2p2c2]
        
        
        let l2l2p3c1 = Component()
        l2l2p3c1.type = .label
        l2l2p3c1.text = "With around 968,452 bitcoin (4.6 %), <b>Satoshi Nakamoto</b> is considered the largest individual holder."
        
        let l2l2p3c2 = Component()
        l2l2p3c2.type = .label
        l2l2p3c2.text = "These coins have remained untouched since 2010, and are considered permanently inactive."
        
        let l2l2p3 = Page()
        l2l2p3.components = [l2l2p3c1, l2l2p3c2]
        
        
        let l2l2p4c1 = Component()
        l2l2p4c1.type = .label
        l2l2p4c1.text = "Investment funds count for around 7.8 % of total bitcoin, the largest holder being <b>BlackRock iShares Bitcoin Trust</b>."
        
        let l2l2p4c2 = Component()
        l2l2p4c2.type = .label
        l2l2p4c2.text = "Companies hold around 6.2 % of the supply. Tesla, for example, holds around 11,500 bitcoin (0.06 %)."
        
        let l2l2p4 = Page()
        l2l2p4.components = [l2l2p4c1, l2l2p4c2]
        
        
        let l2l2p5c1 = Component()
        l2l2p5c1.type = .label
        l2l2p5c1.text = "Governments are estimated to hold a total of 1.5 % of all bitcoin."
        
        let l2l2p5c2 = Component()
        l2l2p5c2.type = .label
        l2l2p5c2.text = "The <b>U.S. government</b> holds around 213,000 bitcoin, mostly seized."
        
        let l2l2p5 = Page()
        l2l2p5.components = [l2l2p5c1, l2l2p5c2]
        
        
        let l2l2p6c1 = Component()
        l2l2p6c1.type = .label
        l2l2p6c1.text = "Large holdings do not confer power over the protocol. Rules are enforced by bitcoin nodes."
        
        let l2l2p6c3 = Component()
        l2l2p6c3.type = .label
        l2l2p6c3.text = "Ownership is purely private: whoever controls the private key controls the coins."
        
        let l2l2p6 = Page()
        l2l2p6.components = [l2l2p6c1, l2l2p6c3]
        
        
        let l2l2 = Lesson()
        l2l2.title = "Who owns the most bitcoin?"
        l2l2.id = "whoownsthemostbitcoin"
        l2l2.image = "whoownsthemostbitcoin"
        l2l2.pages = [l2l2p1, l2l2p2, l2l2p3, l2l2p4, l2l2p5, l2l2p6]
        
        
        let l2l4p1c1 = Component()
        l2l4p1c1.type = .label
        l2l4p1c1.text = "The bitcoin network runs on <b>software</b>. The original and most widely used software is called <b>Bitcoin Core</b>."
        
        let l2l4p1c3 = Component()
        l2l4p1c3.type = .label
        l2l4p1c3.text = "This software enables functions like <b>mining</b>, <b>validating transactions</b>, and <b>running nodes</b>."
        
        let l2l4p1 = Page()
        l2l4p1.components = [l2l4p1c1, l2l4p1c3]
        
        
        let l2l4p2c1 = Component()
        l2l4p2c1.type = .label
        l2l4p2c1.text = "A <b>bitcoin node</b> is any computer that's running software like Bitcoin Core."
        
        let l2l4p2c2 = Component()
        l2l4p2c2.type = .label
        l2l4p2c2.text = "Anyone can run a node. Tens of thousands of people do."
        
        let l2l4p2c3 = Component()
        l2l4p2c3.type = .label
        l2l4p2c3.text = "Nodes download the blockchain and independently verify all transactions. They keep the bitcoin network <b>decentralized</b>, secure, and functional."
        
        let l2l4p2 = Page()
        l2l4p2.components = [l2l4p2c1, l2l4p2c2, l2l4p2c3]
        
        
        let l2l4p3c1 = Component()
        l2l4p3c1.type = .label
        l2l4p3c1.text = "Bitcoin Core is <b>open-source</b>, meaning everyone can see its code."
        
        let l2l4p3c2 = Component()
        l2l4p3c2.type = .label
        l2l4p3c2.text = "Everyone can see exactly how bitcoin works. Everyone can view the entire blockchain and all transactions."
        
        let l2l4p3 = Page()
        l2l4p3.components = [l2l4p3c1, l2l4p3c2]
        
        
        let l2l4p4c1 = Component()
        l2l4p4c1.type = .label
        l2l4p4c1.text = "Anyone can collaborate on Bitcoin Core development, subject to an open review process."
        
        let l2l4p4c2 = Component()
        l2l4p4c2.type = .label
        l2l4p4c2.text = "New ideas are called <b>Bitcoin Improvement Proposals (BIP)</b>, which are discussed and tested rigorously."
        
        let l2l4p4c3 = Component()
        l2l4p4c3.type = .label
        l2l4p4c3.text = "Improvements are launched only upon wide community consensus. Nodes decide individually whether or not to adopt changes."
        
        let l2l4p4 = Page()
        l2l4p4.components = [l2l4p4c1, l2l4p4c2, l2l4p4c3]
        
        let l2l4 = Lesson()
        l2l4.title = "What is Bitcoin Core?"
        l2l4.id = "whatisbitcoincore"
        l2l4.image = "whatiscore"
        l2l4.pages = [l2l4p1, l2l4p2, l2l4p3, l2l4p4]
        
        
        let l2l3p1c1 = Component()
        l2l3p1c1.type = .label
        l2l3p1c1.text = "To send and receive bitcoin, you need a <b>wallet</b>."
        
        let l2l3p1c2 = Component()
        l2l3p1c2.type = .label
        l2l3p1c2.text = "With a <b>self-custodial</b> wallet (like this app), you hold your own bitcoin and private keys."
        
        let l2l3p1c3 = Component()
        l2l3p1c3.type = .label
        l2l3p1c3.text = "With a <b>custodial</b> wallet, a middleman (like Coinbase) holds your bitcoin on your behalf."
        
        let l2l3p1 = Page()
        l2l3p1.components = [l2l3p1c1, l2l3p1c2, l2l3p1c3]
        
        
        let l2l3p2c1 = Component()
        l2l3p2c1.type = .label
        l2l3p2c1.text = "To receive bitcoin, your wallet generates <b>addresses</b>. Each wallet can generate unlimited addresses."
        
        let l2l3p2c2 = Component()
        l2l3p2c2.type = .label
        l2l3p2c2.text = "You can reuse addresses, or (for <b>privacy</b>) create a new address for each transaction."
        
        let l2l3p2c3 = Component()
        l2l3p2c3.type = .label
        l2l3p2c3.text = "All addresses and all bitcoin in them are public. What wallet an address belongs to isn't."
        
        let l2l3p2 = Page()
        l2l3p2.components = [l2l3p2c1, l2l3p2c2, l2l3p2c3]
        
        
        let l2l3p3c1 = Component()
        l2l3p3c1.type = .label
        l2l3p3c1.text = "To send bitcoin, you enter the <b>recipient's address</b>, the <b>amount</b>, and the <b>transaction fee</b>."
        
        let l2l3p3c2 = Component()
        l2l3p3c2.type = .label
        l2l3p3c2.text = "The higher the selected fee, the quicker a miner will include your transaction in their <b>block</b>."
        
        let l2l3p3c3 = Component()
        l2l3p3c3.type = .label
        l2l3p3c3.text = "Wallets usually recommend fees based on your urgency to get your transaction confirmed."
        
        let l2l3p3 = Page()
        l2l3p3.components = [l2l3p3c1, l2l3p3c2, l2l3p3c3]
        
        
        let l2l3p4c1 = Component()
        l2l3p4c1.type = .label
        l2l3p4c1.text = "The amount barely impacts the fee, regardless of whether you send 100 bitcoin or 0.001 bitcoin."
        
        let l2l3p4c2 = Component()
        l2l3p4c2.type = .label
        l2l3p4c2.text = "The fee height fluctuates with demand, since blocks hold limited transactions and miners wish to maximize their returns."
        
        let l2l3p4c3 = Component()
        l2l3p4c3.type = .label
        l2l3p4c3.text = "If your fee is too low, your transaction may take days to - or never - get mined."
        
        let l2l3p4 = Page()
        l2l3p4.components = [l2l3p4c1, l2l3p4c2, l2l3p4c3]
        
        
        let l2l3p5c1 = Component()
        l2l3p5c1.type = .label
        l2l3p5c1.text = "Bitcoin transactions are <b>irreversible</b>, so make sure you enter the correct address and amount."
        
        let l2l3p5c2 = Component()
        l2l3p5c2.type = .label
        l2l3p5c2.text = "You can use a <b>block explorer</b> (like mempool.space) to check transaction statuses."
        
        let l2l3p5c3 = Component()
        l2l3p5c3.type = .label
        l2l3p5c3.text = "Once your transaction is mined into a block, that's one confirmation. Each following block is an additional confirmation. Typically, six confirmations is considered final."
        
        let l2l3p5 = Page()
        l2l3p5.components = [l2l3p5c1, l2l3p5c2, l2l3p5c3]
        
        
        let l2l3 = Lesson()
        l2l3.title = "Sending and receiving bitcoin"
        l2l3.id = "sendingandreceivingbitcoin"
        l2l3.image = "sendingandreceiving"
        l2l3.pages = [l2l3p1, l2l3p2, l2l3p3, l2l3p4, l2l3p5]
        
        
        let l2l5p1c1 = Component()
        l2l5p1c1.type = .label
        l2l5p1c1.text = "Bitcoin transactions can be <b>on-chain</b> or <b>off-chain</b>."
        
        let l2l5p1c2 = Component()
        l2l5p1c2.type = .label
        l2l5p1c2.text = "On-chain transactions are the ones that get <b>mined</b> onto a <b>block</b> on the blockchain."
        
        let l2l5p1c3 = Component()
        l2l5p1c3.type = .label
        l2l5p1c3.text = "These come with some limitations."
        
        let l2l5p1 = Page()
        l2l5p1.components = [l2l5p1c1, l2l5p1c2, l2l5p1c3]
        
        
        let l2l5p2c1 = Component()
        l2l5p2c1.type = .label
        l2l5p2c1.text = "The blockchain is arguably the most <b>secure</b> financial database in existence."
        
        let l2l5p2c2 = Component()
        l2l5p2c2.type = .label
        l2l5p2c2.text = "But <b>fees</b> can get high and <b>confirmation times</b> can be slow."
        
        let l2l5p2c3 = Component()
        l2l5p2c3.type = .label
        l2l5p2c3.text = "Off-chain transactions (payments that <b>don't touch the blockchain</b>) address these issues."
        
        let l2l5p2 = Page()
        l2l5p2.components = [l2l5p2c1, l2l5p2c2, l2l5p2c3]
        
        
        let l2l5p3c1 = Component()
        l2l5p3c1.type = .label
        l2l5p3c1.text = "The <b>lightning network</b> is such a solution."
        
        let l2l5p3c2 = Component()
        l2l5p3c2.type = .label
        l2l5p3c2.text = "With one on-chain transaction, <b>two users</b> lock up bitcoin in a <b>multisignature address</b>."
        
        let l2l5p3c3 = Component()
        l2l5p3c3.type = .label
        l2l5p3c3.text = "Inside this <b>payment channel</b>, they can send bitcoin back and forth, <b>instantly</b> and <b>without fees</b>."
        
        let l2l5p3 = Page()
        l2l5p3.components = [l2l5p3c1, l2l5p3c2, l2l5p3c3]
        
        
        let l2l5p4c1 = Component()
        l2l5p4c1.type = .label
        l2l5p4c1.text = "Either user can <b>close the channel</b>, settling their balance on the blockchain."
        
        let l2l5p4c2 = Component()
        l2l5p4c2.type = .label
        l2l5p4c2.text = "Or, through 3rd parties, users can <b>swap funds</b> between lightning and on-chain."
        
        let l2l5p4 = Page()
        l2l5p4.components = [l2l5p4c1, l2l5p4c2]
        
        
        let l2l5p5c1 = Component()
        l2l5p5c1.type = .label
        l2l5p5c1.text = "The lightning network is a <b>web</b> of <b>nodes</b> connected through <b>channels</b>."
        
        let l2l5p5c2 = Component()
        l2l5p5c2.type = .label
        l2l5p5c2.text = "If you have a channel with <b>Bob</b>, who has a channel with <b>Alice</b>, you can send instant payments to Alice without having a direct channel with her."
        
        let l2l5p5c3 = Component()
        l2l5p5c3.type = .label
        l2l5p5c3.text = "Such payments may incur <b>minor fees</b>, allowing you to instantly pay anyone (if a route can be found)."
        
        let l2l5p5 = Page()
        l2l5p5.components = [l2l5p5c1, l2l5p5c2, l2l5p5c3]
        
        
        let l2l5p6c1 = Component()
        l2l5p6c1.type = .label
        l2l5p6c1.text = "Lightning payments are great for <b>frequent, small, private</b> transactions."
        
        let l2l5p6c2 = Component()
        l2l5p6c2.type = .label
        l2l5p6c2.text = "They're <b>faster</b> and <b>cheaper</b>, allowing bitcoin to <b>scale</b>."
        
        let l2l5p6c3 = Component()
        l2l5p6c3.type = .label
        l2l5p6c3.text = "Downsides are the need for <b>upfront funding</b>, and the <b>technical expertise</b> required."
        
        let l2l5p6 = Page()
        l2l5p6.components = [l2l5p6c1, l2l5p6c2, l2l5p6c3]
        
        
        let l2l5p7c1 = Component()
        l2l5p7c1.type = .label
        l2l5p7c1.text = "To stimulate bitcoin adoption, wallets like this one try to offer seamless switching between <b>regular transactions</b> and <b>instant payments</b>."
        
        let l2l5p7c2 = Component()
        l2l5p7c2.type = .label
        l2l5p7c2.text = "With bitcoin purchases under 100 €/CHF, bittr opens a channel with you."
        
        let l2l5p7 = Page()
        l2l5p7.components = [l2l5p7c1, l2l5p7c2]
        
        
        let l2l5 = Lesson()
        l2l5.title = "What is lightning?"
        l2l5.id = "whatislightning"
        l2l5.image = "whatislightning"
        l2l5.pages = [l2l5p1, l2l5p2, l2l5p3, l2l5p4, l2l5p5, l2l5p6, l2l5p7]
        
        
        let l2l6p1c1 = Component()
        l2l6p1c1.type = .label
        l2l6p1c1.text = "Your bitcoin exists only on the <b>blockchain</b>."
        
        let l2l6p1c2 = Component()
        l2l6p1c2.type = .label
        l2l6p1c2.text = "You have your <b>public keys</b> (addresses) to receive bitcoin, and your <b>private keys</b> (seedphrase) to send bitcoin."
        
        let l2l6p1c3 = Component()
        l2l6p1c3.type = .label
        l2l6p1c3.text = "A <b>bitcoin wallet</b> is a piece of <b>hardware or software</b> to store these keys, to manage your bitcoin."
        
        let l2l6p1 = Page()
        l2l6p1.components = [l2l6p1c1, l2l6p1c2, l2l6p1c3]
        
        
        let l2l6p2c1 = Component()
        l2l6p2c1.type = .label
        l2l6p2c1.text = "There are various types of wallets, with various levels of <b>security</b>."
        
        let l2l6p2c2 = Component()
        l2l6p2c2.type = .label
        l2l6p2c2.text = "With a <b>custodial wallet</b>, a 3rd party (like an exchange) holds your keys on your behalf."
        
        let l2l6p2c3 = Component()
        l2l6p2c3.type = .label
        l2l6p2c3.text = "While easy to use, this goes against bitcoin's ethos of \"<b>Not your keys, not your coins</b>\"."
        
        let l2l6p2 = Page()
        l2l6p2.components = [l2l6p2c1, l2l6p2c2, l2l6p2c3]
        
        
        let l2l6p3c1 = Component()
        l2l6p3c1.type = .label
        l2l6p3c1.text = "With a <b>self-custodial or non-custodial wallet</b>, you hold your own keys. These come as software or hardware."
        
        let l2l6p3c2 = Component()
        l2l6p3c2.type = .label
        l2l6p3c2.text = "A <b>software</b> wallet is an app (like this one) that's connected to the internet."
        
        let l2l6p3c3 = Component()
        l2l6p3c3.type = .label
        l2l6p3c3.text = "A <b>hardware</b> wallet is an offline device."
        
        let l2l6p3 = Page()
        l2l6p3.components = [l2l6p3c1, l2l6p3c2, l2l6p3c3]
        
        
        let l2l6p4c1 = Component()
        l2l6p4c1.type = .label
        l2l6p4c1.text = "Software wallets are convenient to keep some bitcoin at hand for you to easily make transactions."
        
        let l2l6p4c2 = Component()
        l2l6p4c2.type = .label
        l2l6p4c2.text = "But any software that's connected to the internet, is always somewhat at risk to online threats."
        
        let l2l6p4c3 = Component()
        l2l6p4c3.type = .label
        l2l6p4c3.text = "If you hold significant bitcoin, a hardware wallet offers superior security."
        
        let l2l6p4 = Page()
        l2l6p4.components = [l2l6p4c1, l2l6p4c2, l2l6p4c3]
        
        
        let l2l6p5c1 = Component()
        l2l6p5c1.type = .label
        l2l6p5c1.text = "A hardware wallet can be paired with a <b>watch-only</b> software wallet."
        
        let l2l6p5c2 = Component()
        l2l6p5c2.type = .label
        l2l6p5c2.text = "This wallet only holds your public keys, so you can view your balance."
        
        let l2l6p5c3 = Component()
        l2l6p5c3.type = .label
        l2l6p5c3.text = "You can prepare transactions, which you sign with your hardware wallet."
        
        let l2l6p5 = Page()
        l2l6p5.components = [l2l6p5c1, l2l6p5c2, l2l6p5c3]
        
        
        let l2l6 = Lesson()
        l2l6.title = "Choosing a bitcoin wallet"
        l2l6.id = "introductiontobitcoinwallets"
        l2l6.image = "introductiontowallets"
        l2l6.pages = [l2l6p1, l2l6p2, l2l6p3, l2l6p4, l2l6p5]
        
        
        let level2 = Level()
        level2.lessons = [l2l4, l2l1, l2l2, l2l3, l2l5, l2l6]
        
        
        let l3l1p1c1 = Component()
        l3l1p1c1.type = .label
        l3l1p1c1.text = "A blockchain is a <b>database</b> that stores data in <b>chronologically linked blocks</b>."
        
        let l3l1p1c2 = Component()
        l3l1p1c2.type = .label
        l3l1p1c2.text = "Data can be added, but it can never be altered or removed."
        
        let l3l1p1c3 = Component()
        l3l1p1c3.type = .label
        l3l1p1c3.text = "It offers a <b>single, verifiable version of history</b>."
        
        let l3l1p1 = Page()
        l3l1p1.components = [l3l1p1c1, l3l1p1c2, l3l1p1c3]
        
        
        let l3l1p2c1 = Component()
        l3l1p2c1.type = .label
        l3l1p2c1.text = "Blockchain was invented for bitcoin."
        
        let l3l1p2c2 = Component()
        l3l1p2c2.type = .label
        l3l1p2c2.text = "It solves the <b>double spend problem</b>: the ability to spend digital currency more than once."
        
        let l3l1p2c3 = Component()
        l3l1p2c3.type = .label
        l3l1p2c3.text = "This ensures that bitcoin (like physical currency) can only be spent once, moving from one address to another."
        
        let l3l1p2 = Page()
        l3l1p2.components = [l3l1p2c1, l3l1p2c2, l3l1p2c3]
        
        
        let l3l1p3c1 = Component()
        l3l1p3c1.type = .label
        l3l1p3c1.text = "Bitcoin is <b>trustless</b>."
        
        let l3l1p3c2 = Component()
        l3l1p3c2.type = .label
        l3l1p3c2.text = "You don't need to trust any single entity (like a bank or government) that your money is safe."
        
        let l3l1p3c3 = Component()
        l3l1p3c3.type = .label
        l3l1p3c3.text = "Accordingly, the blockchain is <b>public</b>. Anyone can download and verify the entire blockchain."
        
        let l3l1p3 = Page()
        l3l1p3.components = [l3l1p3c1, l3l1p3c2, l3l1p3c3]
        
        
        let l3l1p4c1 = Component()
        l3l1p4c1.type = .label
        l3l1p4c1.text = "The blockchain is <b>decentralized</b>."
        
        let l3l1p4c2 = Component()
        l3l1p4c2.type = .label
        l3l1p4c2.text = "Tens of thousands of people (<b>nodes</b>) worldwide independently maintain their own copy."
        
        let l3l1p4 = Page()
        l3l1p4.components = [l3l1p4c1, l3l1p4c2]
        
        
        let l3l1p5c1 = Component()
        l3l1p5c1.type = .label
        l3l1p5c1.text = "The blockchain is <b>immutable</b>. Here's how:"
        
        let l3l1p5c2 = Component()
        l3l1p5c2.type = .label
        l3l1p5c2.text = "In encryption, you can run data through a mathematical formula to get a <b>hash</b>."
        
        let l3l1p5c3 = Component()
        l3l1p5c3.type = .label
        l3l1p5c3.text = "This hash (a long string of letters and numbers) is a unique digital fingerprint for that data."
        
        let l3l1p5 = Page()
        l3l1p5.components = [l3l1p5c1, l3l1p5c2, l3l1p5c3]
        
        
        let l3l1p6c1 = Component()
        l3l1p6c1.type = .label
        l3l1p6c1.text = "Each block in the blockchain starts with the hash of the previous block."
        
        let l3l1p6c2 = Component()
        l3l1p6c2.type = .label
        l3l1p6c2.text = "Miners fill each block with 4 MB of data, around <b>3000 transactions</b>."
        
        let l3l1p6c3 = Component()
        l3l1p6c3.type = .label
        l3l1p6c3.text = "They pick these from the <b>mempool</b>, which holds all unconfirmed transactions."
        
        let l3l1p6 = Page()
        l3l1p6.components = [l3l1p6c1, l3l1p6c2, l3l1p6c3]
        
        
        let l3l1p7c1 = Component()
        l3l1p7c1.type = .label
        l3l1p7c1.text = "That data plus the hash of the previous block <b>form a new hash</b>."
        
        let l3l1p7c2 = Component()
        l3l1p7c2.type = .label
        l3l1p7c2.text = "However, that hash needs to meet certain conditions: the <b>difficulty rule</b>."
        
        let l3l1p7c3 = Component()
        l3l1p7c3.type = .label
        l3l1p7c3.text = "The difficulty gets updated every two weeks, to ensure that a block gets mined <b>every 10 minutes</b>."
        
        let l3l1p7 = Page()
        l3l1p7.components = [l3l1p7c1, l3l1p7c2, l3l1p7c3]
        
        
        let l3l1p8c1 = Component()
        l3l1p8c1.type = .label
        l3l1p8c1.text = "To meet those conditions, miners try adding trillions of numbers (<b>nonces</b>) to the block's data."
        
        let l3l1p8c2 = Component()
        l3l1p8c2.type = .label
        l3l1p8c2.text = "<b>Hash of the previous block</b> + <b>new transactions</b> + <b>unknown nonce</b> = <b>new hash</b> that meets the <b>difficulty rule</b>."
        
        let l3l1p8c3 = Component()
        l3l1p8c3.type = .label
        l3l1p8c3.text = "The first miner to guess a correct nonce, <b>mines the block</b> and gets 3.125 bitcoin plus all transaction fees."
        
        let l3l1p8 = Page()
        l3l1p8.components = [l3l1p8c1, l3l1p8c2, l3l1p8c3]
        
        
        let l3l1p9c1 = Component()
        l3l1p9c1.type = .label
        l3l1p9c1.text = "Since each hash is unique, and each block contains the previous block's hash, these blocks are <b>immutable</b>."
        
        let l3l1p9c2 = Component()
        l3l1p9c2.type = .label
        l3l1p9c2.text = "If you change anything, the entire chain breaks. To change one block, you need to change all following blocks."
        
        let l3l1p9c3 = Component()
        l3l1p9c3.type = .label
        l3l1p9c3.text = "The high investments required to mine blocks make this virtually impossible."
        
        let l3l1p9 = Page()
        l3l1p9.components = [l3l1p9c1, l3l1p9c2, l3l1p9c3]
        
        
        let l3l1 = Lesson()
        l3l1.title = "What is a blockchain?"
        l3l1.id = "whatisablockchain"
        l3l1.image = "whatisablockchain"
        l3l1.pages = [l3l1p1, l3l1p2, l3l1p3, l3l1p4, l3l1p5, l3l1p6, l3l1p7, l3l1p8, l3l1p9]
        
        
        let l3l2p1c1 = Component()
        l3l2p1c1.type = .label
        l3l2p1c1.text = "A common misconception is that bitcoin is anonymous."
        
        let l3l2p1c2 = Component()
        l3l2p1c2.type = .label
        l3l2p1c2.text = "And that it's, therefore, used mostly by criminals."
        
        let l3l2p1c3 = Component()
        l3l2p1c3.type = .label
        l3l2p1c3.text = "But how private is bitcoin really?"
        
        let l3l2p1 = Page()
        l3l2p1.components = [l3l2p1c1, l3l2p1c2, l3l2p1c3]
        
        
        let l3l2p2c1 = Component()
        l3l2p2c1.type = .label
        l3l2p2c1.text = "The blockchain is public."
        
        let l3l2p2c2 = Component()
        l3l2p2c2.type = .label
        l3l2p2c2.text = "Everyone can see every transaction, and the amount of bitcoin in every address."
        
        let l3l2p2c3 = Component()
        l3l2p2c3.type = .label
        l3l2p2c3.text = "These addresses, however, contain no personal information of the owner."
        
        let l3l2p2 = Page()
        l3l2p2.components = [l3l2p2c1, l3l2p2c2, l3l2p2c3]
        
        
        let l3l2p3c1 = Component()
        l3l2p3c1.type = .label
        l3l2p3c1.text = "This means that bitcoin is <b>pseudonymous</b>, not anonymous."
        
        let l3l2p3c2 = Component()
        l3l2p3c2.type = .label
        l3l2p3c2.text = "This pseudonymity provides privacy, while allowing anyone to audit the bitcoin supply."
        
        let l3l2p3c3 = Component()
        l3l2p3c3.type = .label
        l3l2p3c3.text = "If bitcoin were anonymous, there would be no way to verify the correct minting and movement of coins."
        
        let l3l2p3 = Page()
        l3l2p3.components = [l3l2p3c1, l3l2p3c2, l3l2p3c3]
        
        
        let l3l2p4c1 = Component()
        l3l2p4c1.type = .label
        l3l2p4c1.text = "However, bitcoin exchanges are often required to verify customer identities, above certain purchase thresholds."
        
        let l3l2p4c2 = Component()
        l3l2p4c2.type = .label
        l3l2p4c2.text = "This is enforced through <b>Know Your Customer (KYC)</b> regulations."
        
        let l3l2p4c3 = Component()
        l3l2p4c3.type = .label
        l3l2p4c3.text = "If requested, they must share these data with authorities."
        
        let l3l2p4 = Page()
        l3l2p4.components = [l3l2p4c1, l3l2p4c2, l3l2p4c3]
        
        
        let l3l2p5c1 = Component()
        l3l2p5c1.type = .label
        l3l2p5c1.text = "Additionally, <b>blockchain analysis</b> companies exist."
        
        let l3l2p5c2 = Component()
        l3l2p5c2.type = .label
        l3l2p5c2.text = "These companies, through various strategies, try to trace what address and bitcoin belongs to whom."
        
        let l3l2p5 = Page()
        l3l2p5.components = [l3l2p5c1, l3l2p5c2]
        
        
        let l3l2p6c1 = Component()
        l3l2p6c1.type = .label
        l3l2p6c1.text = "Reduced privacy can lead to compromised safety. For example, for activists, dissidents, or opponents to oppressive regimes."
        
        let l3l2p6c2 = Component()
        l3l2p6c2.type = .label
        l3l2p6c2.text = "As bitcoin evolves, developers explore ways to preserve its pseudonymity."
        
        let l3l2p6c3 = Component()
        l3l2p6c3.type = .label
        l3l2p6c3.text = "Off-chain solutions (like <b>lightning</b>) enhance privacy by allowing for private transactions."
        
        let l3l2p6 = Page()
        l3l2p6.components = [l3l2p6c1, l3l2p6c2, l3l2p6c3]
        
        
        let l3l2 = Lesson()
        l3l2.title = "How private is bitcoin?"
        l3l2.id = "howprivateisbitcoin"
        l3l2.image = "howprivateisbitcoin"
        l3l2.pages = [l3l2p1, l3l2p2, l3l2p3, l3l2p4, l3l2p5, l3l2p6]
        
        
        let l3l3p1c1 = Component()
        l3l3p1c1.type = .label
        l3l3p1c1.text = "For <b>trustlessness</b>, it's important that bitcoin is secure against attacks."
        
        let l3l3p1c2 = Component()
        l3l3p1c2.type = .label
        l3l3p1c2.text = "The blockchain has <b>never been hacked</b>. Its decentralized nature makes attacks extremely difficult, technically and economically."
        
        let l3l3p1 = Page()
        l3l3p1.components = [l3l3p1c1, l3l3p1c2]
        
        
        let l3l3p2c1 = Component()
        l3l3p2c1.type = .label
        l3l3p2c1.text = "In hacking, there's the <b>user level</b> and <b>network level</b>."
        
        let l3l3p2c2 = Component()
        l3l3p2c2.type = .label
        l3l3p2c2.text = "On the user level, if you're careless with your seedphrase, you can lose your coins."
        
        let l3l3p2c3 = Component()
        l3l3p2c3.type = .label
        l3l3p2c3.text = "Or if you get a custodial wallet, that 3rd party can get hacked or steal your coins."
        
        let l3l3p2 = Page()
        l3l3p2.components = [l3l3p2c1, l3l3p2c2, l3l3p2c3]
        
        
        let l3l3p3c1 = Component()
        l3l3p3c1.type = .label
        l3l3p3c1.text = "On the network level, how technically robust is bitcoin?"
        
        let l3l3p3c2 = Component()
        l3l3p3c2.type = .label
        l3l3p3c2.text = "The blockchain is maintained by tens of thousands of independent nodes worldwide."
        
        let l3l3p3c3 = Component()
        l3l3p3c3.type = .label
        l3l3p3c3.text = "You can't hack just a single computer, you'd need to hack tens of thousands."
        
        let l3l3p3 = Page()
        l3l3p3.components = [l3l3p3c1, l3l3p3c2, l3l3p3c3]
        
        
        let l3l3p4c1 = Component()
        l3l3p4c1.type = .label
        l3l3p4c1.text = "Hacking the blockchain by <b>mining blocks</b> would require more computing power than all miners combined."
        
        let l3l3p4c2 = Component()
        l3l3p4c2.type = .label
        l3l3p4c2.text = "The high rewards and extreme competition, complexity, and randomness, make this extremely expensive if not impossible."
        
        let l3l3p4c3 = Component()
        l3l3p4c3.type = .label
        l3l3p4c3.text = "Even if you do mine a block with fraudulent transactions, the nodes would just reject the block."
        
        let l3l3p4 = Page()
        l3l3p4.components = [l3l3p4c1, l3l3p4c2, l3l3p4c3]
        
        
        let l3l3p5c1 = Component()
        l3l3p5c1.type = .label
        l3l3p5c1.text = "Paradoxically, if you'd successfully hack the blockchain in order to enrich yourself, the value of bitcoin would fall."
        
        let l3l3p5c2 = Component()
        l3l3p5c2.type = .label
        l3l3p5c2.text = "The value of bitcoin relies entirely on its security and scarcity."
        
        let l3l3p5c3 = Component()
        l3l3p5c3.type = .label
        l3l3p5c3.text = "If not technically, then also economically, it's impossible to hack bitcoin and make a profit."
        
        let l3l3p5 = Page()
        l3l3p5.components = [l3l3p5c1, l3l3p5c2, l3l3p5c3]
        
        
        let l3l3p6c1 = Component()
        l3l3p6c1.type = .label
        l3l3p6c1.text = "What if the <b>internet goes down</b>? This would impact bitcoin, like it would impact all modern services."
        
        let l3l3p6c2 = Component()
        l3l3p6c2.type = .label
        l3l3p6c2.text = "Data would stay <b>intact</b> with all nodes, while they wait for the connection to return."
        
        let l3l3p6c3 = Component()
        l3l3p6c3.type = .label
        l3l3p6c3.text = "As bitcoin evolves, <b>alternative paths</b> are explored to run the network, not relying on the traditional internet."
        
        let l3l3p6 = Page()
        l3l3p6.components = [l3l3p6c1, l3l3p6c2, l3l3p6c3]
        
        
        let l3l3p7c1 = Component()
        l3l3p7c1.type = .label
        l3l3p7c1.text = "What about hypothetical <b>quantum computers</b>, breaking cryptography and computing power?"
        
        let l3l3p7c2 = Component()
        l3l3p7c2.type = .label
        l3l3p7c2.text = "This would compromise all modern services. Comparatively, bitcoin is exponentially more difficult to hack."
        
        let l3l3p7c3 = Component()
        l3l3p7c3.type = .label
        l3l3p7c3.text = "If such a threat would arise, bitcoin can evolve to anticipate it - as it's continuously doing."
        
        let l3l3p7 = Page()
        l3l3p7.components = [l3l3p7c1, l3l3p7c2, l3l3p7c3]
        
        
        let l3l3p8c1 = Component()
        l3l3p8c1.type = .label
        l3l3p8c1.text = "In conclusion, bitcoin remains unhacked and its security unmatched."
        
        let l3l3p8c2 = Component()
        l3l3p8c2.type = .label
        l3l3p8c2.text = "Any real threat to your funds, comes from carelessness with your keys."
        
        let l3l3p8c3 = Component()
        l3l3p8c3.type = .label
        l3l3p8c3.text = "Choose the appropriate wallets, and protect access to your keys and devices, and your coins will be secure."
        
        let l3l3p8 = Page()
        l3l3p8.components = [l3l3p8c1, l3l3p8c2, l3l3p8c3]
        
        
        let l3l3 = Lesson()
        l3l3.title = "Can bitcoin be hacked?"
        l3l3.id = "canbitcoinbehacked"
        l3l3.image = "canbitcoinbehacked"
        l3l3.pages = [l3l3p1, l3l3p2, l3l3p3, l3l3p4, l3l3p5, l3l3p6, l3l3p7, l3l3p8]
        
        
        let l3l4p1c1 = Component()
        l3l4p1c1.type = .label
        l3l4p1c1.text = "The words bitcoin and <b>crypto</b> are often inappropriately interchanged."
        
        let l3l4p1c2 = Component()
        l3l4p1c2.type = .label
        l3l4p1c2.text = "Bitcoin is a currency. Crypto refers to bitcoin and all <b>altcoins</b> that have spawned since."
        
        let l3l4p1c3 = Component()
        l3l4p1c3.type = .label
        l3l4p1c3.text = "These are not the same."
        
        let l3l4p1 = Page()
        l3l4p1.components = [l3l4p1c1, l3l4p1c2, l3l4p1c3]
        
        
        let l3l4p2c1 = Component()
        l3l4p2c1.type = .label
        l3l4p2c1.text = "Bitcoin has shown itself to be a strong, long-term store of value."
        
        let l3l4p2c2 = Component()
        l3l4p2c2.type = .label
        l3l4p2c2.text = "Its annual growth averages 60%."
        
        let l3l4p2c3 = Component()
        l3l4p2c3.type = .label
        l3l4p2c3.text = "In contrast, according to 2023 data, 90% of crypto traders lose money."
        
        let l3l4p2 = Page()
        l3l4p2.components = [l3l4p2c1, l3l4p2c2, l3l4p2c3]
        
        
        let l3l4p3c1 = Component()
        l3l4p3c1.type = .label
        l3l4p3c1.text = "Bitcoin was the first working crypto asset."
        
        let l3l4p3c2 = Component()
        l3l4p3c2.type = .label
        l3l4p3c2.text = "It has by far the largest <b>market cap</b> and the densest ecosystem, with the most users and infrastructure."
        
        let l3l4p3c3 = Component()
        l3l4p3c3.type = .label
        l3l4p3c3.text = "This network effect cannot be copy-pasted."
        
        let l3l4p3 = Page()
        l3l4p3.components = [l3l4p3c1, l3l4p3c2, l3l4p3c3]
        
        
        let l3l4p4c1 = Component()
        l3l4p4c1.type = .label
        l3l4p4c1.text = "It's difficult for altcoins to achieve true decentralization."
        
        let l3l4p4c2 = Component()
        l3l4p4c2.type = .label
        l3l4p4c2.text = "In practice, they all have a central authority - a company or a small dev team."
        
        let l3l4p4c3 = Component()
        l3l4p4c3.type = .label
        l3l4p4c3.text = "Also, they lack bitcoin's proven resilience: no network outages since 2013; overcome bear markets, bans, and controversies."
        
        let l3l4p4 = Page()
        l3l4p4.components = [l3l4p4c1, l3l4p4c2, l3l4p4c3]
        
        
        let l3l4p5c1 = Component()
        l3l4p5c1.type = .label
        l3l4p5c1.text = "Bitcoin's value comes from its fixed supply, transparent protocol, and proven security."
        
        let l3l4p5c2 = Component()
        l3l4p5c2.type = .label
        l3l4p5c2.text = "As an investment strategy, it offers proven long-term value over crypto's high-risk, short-term gains."
        
        let l3l4p5 = Page()
        l3l4p5.components = [l3l4p5c1, l3l4p5c2]
        
        
        let l3l4 = Lesson()
        l3l4.title = "Bitcoin versus crypto"
        l3l4.id = "bitcoinversuscrypto"
        l3l4.image = "bitcoinversuscrypto"
        l3l4.pages = [l3l4p1, l3l4p2, l3l4p3, l3l4p4, l3l4p5]
        
        
        let l3l5p1c1 = Component()
        l3l5p1c1.type = .image
        l3l5p1c1.url = "https://bittr-notion-bucket.s3.eu-central-2.amazonaws.com/notion-media/299d2c8de1aa8027ad0dd1cd0726e0c1.png"
        
        let l3l5p1c2 = Component()
        l3l5p1c2.type = .label
        l3l5p1c2.text = "Bitcoin, as a concept, was introduced on <b>31 October 2008</b>."
        
        let l3l5p1c3 = Component()
        l3l5p1c3.type = .label
        l3l5p1c3.text = "On that day, the pseudonymous <b>Satoshi Nakamoto</b> published <b>Bitcoin: A Peer-to-Peer Electronic Cash System</b>."
        
        let l3l5p1 = Page()
        l3l5p1.components = [l3l5p1c1, l3l5p1c2, l3l5p1c3]
        
        
        let l3l5p2c1 = Component()
        l3l5p2c1.type = .label
        l3l5p2c1.text = "The timing of the release, weeks after the Lehman Brothers collapse, was likely no coincidence."
        
        let l3l5p2c2 = Component()
        l3l5p2c2.type = .label
        l3l5p2c2.text = "The modest 9-page document became the starting point of a financial shift."
        
        let l3l5p2c3 = Component()
        l3l5p2c3.type = .label
        l3l5p2c3.text = "It laid the foundation for bitcoin’s rise in the following years."
        
        let l3l5p2 = Page()
        l3l5p2.components = [l3l5p2c1, l3l5p2c2, l3l5p2c3]
        
        
        let l3l5p3c1 = Component()
        l3l5p3c1.type = .label
        l3l5p3c1.text = "That date, 31 October, is now known as <b>Bitcoin Whitepaper Day</b>."
        
        let l3l5p3c2 = Component()
        l3l5p3c2.type = .label
        l3l5p3c2.text = "It's meant to celebrate the start of this movement, and the birth of the first decentralized cryptocurrency system."
        
        let l3l5p3 = Page()
        l3l5p3.components = [l3l5p3c1, l3l5p3c2]
        
        
        let l3l5p4c1 = Component()
        l3l5p4c1.type = .label
        l3l5p4c1.text = "Nakamoto introduced bitcoin to address core weaknesses in traditional money."
        
        let l3l5p4c2 = Component()
        l3l5p4c2.type = .label
        l3l5p4c2.text = "It emphasized <b>trustlessness</b>: creating a <b>decentralized</b> peer-to-peer network with no central middlemen."
        
        let l3l5p4c3 = Component()
        l3l5p4c3.type = .label
        l3l5p4c3.text = "It explained the <b>blockchain</b>, as a way to solve the <b>double-spend problem</b>."
        
        let l3l5p4 = Page()
        l3l5p4.components = [l3l5p4c1, l3l5p4c2, l3l5p4c3]
        
        let l3l5p5c1 = Component()
        l3l5p5c1.type = .label
        l3l5p5c1.text = "It announced the <b>fixed supply</b> of 21 million coins, to protect against inflation."
        
        let l3l5p5c2 = Component()
        l3l5p5c2.type = .label
        l3l5p5c2.text = "It aimed for <b>financial inclusion and global access</b>, offering an open financial system to the 1.4 billion people worldwide without bank accounts."
        
        let l3l5p5 = Page()
        l3l5p5.components = [l3l5p5c1, l3l5p5c2]
        
        
        let l3l5p6c1 = Component()
        l3l5p6c1.type = .label
        l3l5p6c1.text = "Bitcoin represents <b>freedom in finance</b>, and challenges conventional ideas about money and ownership."
        
        let l3l5p6c2 = Component()
        l3l5p6c2.type = .label
        l3l5p6c2.text = "It stands for <b>financial sovereignty</b>: individuals hold full control over their assets and transactions."
        
        let l3l5p6c3 = Component()
        l3l5p6c3.type = .label
        l3l5p6c3.text = "It's a movement that puts financial self-determination at the center."
        
        let l3l5p6 = Page()
        l3l5p6.components = [l3l5p6c1, l3l5p6c2, l3l5p6c3]
        
        
        let l3l5 = Lesson()
        l3l5.title = "Bitcoin Whitepaper Day"
        l3l5.id = "bitcoinwhitepaperday"
        l3l5.image = "bitcoinwhitepaperday"
        l3l5.pages = [l3l5p1, l3l5p2, l3l5p3, l3l5p4, l3l5p5, l3l5p6]
        
        
        let l3l6p1c1 = Component()
        l3l6p1c1.type = .label
        l3l6p1c1.text = "Bitcoin challenges the status quo of fiat money."
        
        let l3l6p1c2 = Component()
        l3l6p1c2.type = .label
        l3l6p1c2.text = "For some governments, that’s a threat."
        
        let l3l6p1c3 = Component()
        l3l6p1c3.type = .label
        l3l6p1c3.text = "That raises the question: <b>could governments ban bitcoin entirely?</b>"
        
        let l3l6p1 = Page()
        l3l6p1.components = [l3l6p1c1, l3l6p1c2, l3l6p1c3]
        
        
        let l3l6p2c1 = Component()
        l3l6p2c1.type = .label
        l3l6p2c1.text = "Why might governments want to ban bitcoin?"
        
        let l3l6p2c2 = Component()
        l3l6p2c2.type = .label
        l3l6p2c2.text = "Firstly, for bitcoin's <b>privacy</b>. Its pseudonymity allows individuals to transact outside of state surveillance."
        
        let l3l6p2c3 = Component()
        l3l6p2c3.type = .label
        l3l6p2c3.text = "Secondly, bitcoin is <b>censorship resistant</b>. Transactions cannot be reversed or blocked, unlike bank accounts which can be frozen."
        
        let l3l6p2 = Page()
        l3l6p2.components = [l3l6p2c1, l3l6p2c2, l3l6p2c3]
        
        
        let l3l6p3c1 = Component()
        l3l6p3c1.type = .label
        l3l6p3c1.text = "Thirdly, because of <b>competition</b>. Some states' monetary authority relies on its control of its fiat currency."
        
        let l3l6p3c2 = Component()
        l3l6p3c2.type = .label
        l3l6p3c2.text = "If people switch to bitcoin, this reduces the power of that currency."
        
        let l3l6p3c3 = Component()
        l3l6p3c3.type = .label
        l3l6p3c3.text = "It could also allow individuals to sidestep sanctions."
        
        let l3l6p3 = Page()
        l3l6p3.components = [l3l6p3c1, l3l6p3c2, l3l6p3c3]
        
        
        let l3l6p4c1 = Component()
        l3l6p4c1.type = .label
        l3l6p4c1.text = "<b>China</b> has declared bitcoin illegal multiple times. But mining and trading have continued."
        
        let l3l6p4c2 = Component()
        l3l6p4c2.type = .label
        l3l6p4c2.text = "<b>India</b> has attempted a ban, which was struck down by its Supreme Court."
        
        let l3l6p4c3 = Component()
        l3l6p4c3.type = .label
        l3l6p4c3.text = "In 2021, <b>Nigeria</b> banned bank involvement in crypto, which conversely led to a dramatic spike in bitcoin adoption."
        
        let l3l6p4 = Page()
        l3l6p4.components = [l3l6p4c1, l3l6p4c2, l3l6p4c3]
        
        
        let l3l6p5c1 = Component()
        l3l6p5c1.type = .label
        l3l6p5c1.text = "How could governments shut down bitcoin?"
        
        let l3l6p5c2 = Component()
        l3l6p5c2.type = .label
        l3l6p5c2.text = "One way would be <b>banning regulated platforms</b>. This would make it harder for citizens to buy or sell bitcoin."
        
        let l3l6p5c3 = Component()
        l3l6p5c3.type = .label
        l3l6p5c3.text = "This wouldn't influence the bitcoin network itself, though it could hurt adoption."
        
        let l3l6p5 = Page()
        l3l6p5.components = [l3l6p5c1, l3l6p5c2, l3l6p5c3]
        
        
        let l3l6p6c1 = Component()
        l3l6p6c1.type = .label
        l3l6p6c1.text = "Another way would be for governments to <b>attack the network</b>."
        
        let l3l6p6c2 = Component()
        l3l6p6c2.type = .label
        l3l6p6c2.text = "But hacking the bitcoin network is, technically and economically, virtually impossible. It's designed to be resilient to exactly this kind of censorship."
        
        let l3l6p6c3 = Component()
        l3l6p6c3.type = .label
        l3l6p6c3.text = "Even if a government blocked all domestic nodes, users could still connect through VPNs."
        
        let l3l6p6 = Page()
        l3l6p6.components = [l3l6p6c1, l3l6p6c2, l3l6p6c3]
        
        
        let l3l6p7c1 = Component()
        l3l6p7c1.type = .label
        l3l6p7c1.text = "What about a coordinated, global ban?"
        
        let l3l6p7c2 = Component()
        l3l6p7c2.type = .label
        l3l6p7c2.text = "Governments could ban exchanges, and block internet access to bitcoin-related services."
        
        let l3l6p7c3 = Component()
        l3l6p7c3.type = .label
        l3l6p7c3.text = "They could pressure social platforms to censor bitcoin content, and classify self-custody wallets as illegal."
        
        let l3l6p7 = Page()
        l3l6p7.components = [l3l6p7c1, l3l6p7c2, l3l6p7c3]
        
        
        let l3l6p8c1 = Component()
        l3l6p8c1.type = .label
        l3l6p8c1.text = "That kind of unified effort is unlikely."
        
        let l3l6p8c2 = Component()
        l3l6p8c2.type = .label
        l3l6p8c2.text = "Different countries have very different regulatory goals."
        
        let l3l6p8c3 = Component()
        l3l6p8c3.type = .label
        l3l6p8c3.text = "Plus, any nation choosing not to join the ban would benefit from capital inflow, innovation, and bitcoin businesses relocating."
        
        let l3l6p8 = Page()
        l3l6p8.components = [l3l6p8c1, l3l6p8c2, l3l6p8c3]
        
        let l3l6p9c1 = Component()
        l3l6p9c1.type = .label
        l3l6p9c1.text = "Actually, in democratic countries, voters and lawmakers are increasingly bitcoin-friendly"
        
        let l3l6p9c2 = Component()
        l3l6p9c2.type = .label
        l3l6p9c2.text = "Bitcoin creates jobs, attracts investment, and generates tax revenue."
        
        let l3l6p9c3 = Component()
        l3l6p9c3.type = .label
        l3l6p9c3.text = "Some governments actively embrace bitcoin, to attract innovation."
        
        let l3l6p9 = Page()
        l3l6p9.components = [l3l6p9c1, l3l6p9c2, l3l6p9c3]
        
        
        let l3l6 = Lesson()
        l3l6.title = "What if bitcoin gets forbidden?"
        l3l6.id = "bitcoinforbidden"
        l3l6.image = "forbiddenbitcoin"
        l3l6.pages = [l3l6p1, l3l6p2, l3l6p3, l3l6p4, l3l6p5, l3l6p6, l3l6p7, l3l6p8, l3l6p9]
        
        
        let level3 = Level()
        level3.lessons = [l3l1, l3l2, l3l3, l3l4, l3l5, l3l6]
        
        
        return [level1, level2, level3]
    }
}
