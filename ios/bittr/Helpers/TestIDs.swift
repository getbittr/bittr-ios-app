// AUTO-GENERATED. DO NOT EDIT.
// Source: shared/test-ids/test-ids.json
// Regenerate: ./shared/test-ids/build.py

enum TestID {
    enum Academy {
        static let completeButton = "academy.completeButton"
        static let headerLabel = "academy.headerLabel"
        static let lessonSpinner = "academy.lessonSpinner"
        static let nextLessonButton = "academy.nextLessonButton"
        static let nextPageButton = "academy.nextPageButton"
    }
    enum Buy {
        static let continueButton = "buy.continueButton"
        static let downButton = "buy.downButton"
        static let headerLabel = "buy.headerLabel"
        static let yourCode = "buy.yourCode"
        static let yourEmail = "buy.yourEmail"
        static let yourIban = "buy.yourIban"
        static let paymentModeSwitch = "buy.paymentModeSwitch"
        static let paymentModeButton = "buy.paymentModeButton"
    }
    enum Device {
        enum Darkmode {
            static let deviceButton = "device.darkmode.deviceButton"
            static let moonButton = "device.darkmode.moonButton"
            static let sunButton = "device.darkmode.sunButton"
        }
        enum Row {
            static let bittrpeer = "device.row.bittrpeer"
            static let currency = "device.row.currency"
            static let darkmode = "device.row.darkmode"
            static let devicetoken = "device.row.devicetoken"
            static let language = "device.row.language"
            static let lightningchannels = "device.row.lightningchannels"
            static let notification = "device.row.notification"
            static let pendingpayouts = "device.row.pendingpayouts"
            static let publickey = "device.row.publickey"
            static let purchases = "device.row.purchases"
            static let restore = "device.row.restore"
        }
    }
    enum Header {
        static let downButton = "header.downButton"
    }
    enum History {
        static let swapComplete = "history.swapComplete"
        static let swapPending = "history.swapPending"
        static let transactionAmount = "history.transactionAmount"
        static let transactionButton = "history.transactionButton"
    }
    enum Home {
        static let balanceCardButton = "home.balanceCardButton"
        static let balanceLabel = "home.balanceLabel"
        static let buyButton = "home.buyButton"
        static let currencyButton = "home.currencyButton"
        static let headerLabel = "home.headerLabel"
        static let headerSpinner = "home.headerSpinner"
        static let mapButton = "home.mapButton"
        static let profitButton = "home.profitButton"
        static let profitLabel = "home.profitLabel"
        static let receiveButton = "home.receiveButton"
        static let sendButton = "home.sendButton"
    }
    enum Map {
        static let mapSpinner = "map.mapSpinner"
        static let mapView = "map.mapView"
        enum OnePlace {
            static let closeButton = "map.onePlace.closeButton"
            static let nameLabel = "map.onePlace.nameLabel"
        }
        static let placeCellButton = "map.placeCellButton"
        static let placeName = "map.placeName"
        static let placesTableView = "map.placesTableView"
        static let userLocationButton = "map.userLocationButton"
    }
    enum Move {
        static let satsInstant = "move.satsInstant"
        static let satsRegular = "move.satsRegular"
        static let satsTotal = "move.satsTotal"
        static let subtitleLabel = "move.subtitleLabel"
        static let swapButton = "move.swapButton"
    }
    enum Nav {
        static let academyButton = "nav.academyButton"
        static let settingsButton = "nav.settingsButton"
        static let walletButton = "nav.walletButton"
    }
    enum Pin {
        static let button0 = "pin.button0"
        static let button1 = "pin.button1"
        static let button2 = "pin.button2"
        static let button3 = "pin.button3"
        static let button4 = "pin.button4"
        static let button5 = "pin.button5"
        static let button6 = "pin.button6"
        static let button7 = "pin.button7"
        static let button8 = "pin.button8"
        static let button9 = "pin.button9"
        static let buttonBackspace = "pin.buttonBackspace"
        static let confirmButton = "pin.confirmButton"
        static let pinTextField = "pin.pinTextField"
        static let restoreButton = "pin.restoreButton"
    }
    enum Profits {
        static let subtitleLabel = "profits.subtitleLabel"
        static let totalInvestmentLabel = "profits.totalInvestmentLabel"
        static let totalProfitLabel = "profits.totalProfitLabel"
        static let totalValueLabel = "profits.totalValueLabel"
    }
    enum Question {
        static let answerLabel = "question.answerLabel"
        static let yellowCard = "question.yellowCard"
    }
    enum Receive {
        static let addressLabel = "receive.addressLabel"
        static let addressTitle = "receive.addressTitle"
        static let amountTextField = "receive.amountTextField"
        static let copyButton = "receive.copyButton"
        static let editButton = "receive.editButton"
        static let invoiceLabel = "receive.invoiceLabel"
        static let moreButton = "receive.moreButton"
        static let qrImageView = "receive.qrImageView"
        static let qrSpinner = "receive.qrSpinner"
        static let questionButton = "receive.questionButton"
        static let refreshButton = "receive.refreshButton"
    }
    enum Send {
        static let amountTextField = "send.amountTextField"
        static let availableButton = "send.availableButton"
        static let availableLabel = "send.availableLabel"
        static let bdkSpinner = "send.bdkSpinner"
        enum Confirm {
            static let addressLabel = "send.confirm.addressLabel"
            static let amountFiatLabel = "send.confirm.amountFiatLabel"
            static let amountLabel = "send.confirm.amountLabel"
            static let confirmButton = "send.confirm.confirmButton"
            static let feeFastButton = "send.confirm.feeFastButton"
            static let feeSlowButton = "send.confirm.feeSlowButton"
        }
        static let currencyButton = "send.currencyButton"
        static let currencyLabel = "send.currencyLabel"
        static let lnurlSpinner = "send.lnurlSpinner"
        static let nextButton = "send.nextButton"
        static let pasteButton = "send.pasteButton"
        static let regularButton = "send.regularButton"
        static let toLabel = "send.toLabel"
        static let toTextField = "send.toTextField"
    }
    enum Settings {
        enum Row {
            static let currency = "settings.row.currency"
            static let device = "settings.row.device"
            static let privacy = "settings.row.privacy"
            static let restore = "settings.row.restore"
            static let support = "settings.row.support"
            static let terms = "settings.row.terms"
            static let wallets = "settings.row.wallets"
        }
    }
    enum Signup {
        enum Bittr {
            enum Otp {
                static let codeButton = "signup.bittr.otp.codeButton"
                static let codeTextField = "signup.bittr.otp.codeTextField"
                static let nextButton = "signup.bittr.otp.nextButton"
                static let resendButton = "signup.bittr.otp.resendButton"
                static let topLabel = "signup.bittr.otp.topLabel"
            }
            enum Start {
                static let emailButton = "signup.bittr.start.emailButton"
                static let emailTextField = "signup.bittr.start.emailTextField"
                static let ibanButton = "signup.bittr.start.ibanButton"
                static let ibanTextField = "signup.bittr.start.ibanTextField"
                static let nextButton = "signup.bittr.start.nextButton"
                static let skipButton = "signup.bittr.start.skipButton"
                static let topLabelOne = "signup.bittr.start.topLabelOne"
                static let topLabelThree = "signup.bittr.start.topLabelThree"
                static let topLabelTwo = "signup.bittr.start.topLabelTwo"
            }
            enum Success {
                static let nextButton = "signup.bittr.success.nextButton"
                static let ourIbanLabel = "signup.bittr.success.ourIbanLabel"
                static let topLabelOne = "signup.bittr.success.topLabelOne"
                static let topLabelTwo = "signup.bittr.success.topLabelTwo"
                static let yourCodeLabel = "signup.bittr.success.yourCodeLabel"
            }
            enum TransferInfo {
                static let amountLabel = "signup.bittr.transferInfo.amountLabel"
                static let amountTitle = "signup.bittr.transferInfo.amountTitle"
                static let backButton = "signup.bittr.transferInfo.backButton"
                static let connectionLabel = "signup.bittr.transferInfo.connectionLabel"
                static let connectionTitle = "signup.bittr.transferInfo.connectionTitle"
                static let dcaLabel = "signup.bittr.transferInfo.dcaLabel"
                static let dcaTitle = "signup.bittr.transferInfo.dcaTitle"
                static let lightningLabel = "signup.bittr.transferInfo.lightningLabel"
                static let lightningTitle = "signup.bittr.transferInfo.lightningTitle"
                static let nextButton = "signup.bittr.transferInfo.nextButton"
            }
        }
        enum Create {
            enum Confirm {
                static let cancelButton = "signup.create.confirm.cancelButton"
                static let nextButton = "signup.create.confirm.nextButton"
                static let switchOne = "signup.create.confirm.switchOne"
                static let switchTwo = "signup.create.confirm.switchTwo"
                static let topLabel = "signup.create.confirm.topLabel"
            }
            enum Mnemonic {
                static let mnemonicStack = "signup.create.mnemonic.mnemonicStack"
                static let nextButton = "signup.create.mnemonic.nextButton"
                static let topLabelOne = "signup.create.mnemonic.topLabelOne"
                static let word = "signup.create.mnemonic.word"
            }
            enum PinConfirm {
                static let topLabel = "signup.create.pinConfirm.topLabel"
            }
            enum PinSet {
                static let topLabel = "signup.create.pinSet.topLabel"
            }
            enum Ready {
                static let continueButton = "signup.create.ready.continueButton"
                static let skipButton = "signup.create.ready.skipButton"
                static let topLabelOne = "signup.create.ready.topLabelOne"
            }
            enum Start {
                static let createWalletButton = "signup.create.start.createWalletButton"
                static let headerLabel = "signup.create.start.headerLabel"
                static let restoreButton = "signup.create.start.restoreButton"
            }
            enum Verify {
                static let backButton = "signup.create.verify.backButton"
                static let field1 = "signup.create.verify.field1"
                static let field2 = "signup.create.verify.field2"
                static let field3 = "signup.create.verify.field3"
                static let label1 = "signup.create.verify.label1"
                static let label2 = "signup.create.verify.label2"
                static let label3 = "signup.create.verify.label3"
                static let nextButton = "signup.create.verify.nextButton"
                static let topLabel = "signup.create.verify.topLabel"
            }
        }
        enum Restore {
            static let field1 = "signup.restore.field1"
            static let field10 = "signup.restore.field10"
            static let field11 = "signup.restore.field11"
            static let field12 = "signup.restore.field12"
            static let field2 = "signup.restore.field2"
            static let field3 = "signup.restore.field3"
            static let field4 = "signup.restore.field4"
            static let field5 = "signup.restore.field5"
            static let field6 = "signup.restore.field6"
            static let field7 = "signup.restore.field7"
            static let field8 = "signup.restore.field8"
            static let field9 = "signup.restore.field9"
            static let nextButton = "signup.restore.nextButton"
            enum PinConfirm {
                static let topLabel = "signup.restore.pinConfirm.topLabel"
            }
            enum PinSet {
                static let topLabel = "signup.restore.pinSet.topLabel"
            }
            static let removeWalletButton = "signup.restore.removeWalletButton"
            static let topLabel = "signup.restore.topLabel"
        }
    }
    enum Swap {
        static let amountTextField = "swap.amountTextField"
        static let fromButton = "swap.fromButton"
        static let fromLabel = "swap.fromLabel"
        static let nextButton = "swap.nextButton"
        static let subtitleLabel = "swap.subtitleLabel"
    }
    enum SwapStatus {
        static let confirmCard = "swapStatus.confirmCard"
        static let confirmStatusLabel = "swapStatus.confirmStatusLabel"
    }
    enum Transaction {
        static let labelAmount = "transaction.labelAmount"
        static let labelDate = "transaction.labelDate"
        static let yellowCard = "transaction.yellowCard"
    }
    enum Unlock {
        static let topLabel = "unlock.topLabel"
    }
    enum Value {
        static let currentValueLabel = "value.currentValueLabel"
        static let fiveYearsButton = "value.fiveYearsButton"
        static let graphValueLabel = "value.graphValueLabel"
        static let graphView = "value.graphView"
        static let monthButton = "value.monthButton"
        static let profitLabel = "value.profitLabel"
        static let valueSpinner = "value.valueSpinner"
        static let weekButton = "value.weekButton"
        static let yearButton = "value.yearButton"
    }
    enum Website {
        static let downButton = "website.downButton"
    }
}
