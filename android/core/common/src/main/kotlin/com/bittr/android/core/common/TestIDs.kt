// AUTO-GENERATED. DO NOT EDIT.
// Source: shared/test-ids/test-ids.json
// Regenerate: ./shared/test-ids/build.py

package com.bittr.android.core.common

/** Apply with `Modifier.testTag(TestID.Signup.Create.Start.createWalletButton)`. */
object TestID {
    object Academy {
        const val backPageButton = "academy.backPageButton"
        const val completeButton = "academy.completeButton"
        const val headerLabel = "academy.headerLabel"
        const val lessonSpinner = "academy.lessonSpinner"
        const val nextLessonButton = "academy.nextLessonButton"
        const val nextPageButton = "academy.nextPageButton"
    }
    object Alert {
        const val addNote = "alert.addNote"
        const val amountMissing = "alert.amountMissing"
        // Runtime-indexed: position 0 → "alert.button.0", position 1 → "alert.button.1", …
        const val button = "alert.button"
        fun buttonAt(position: Int) = "alert.button.$position"
        const val confirmStatements = "alert.confirmStatements"
        const val copied = "alert.copied"
        const val exclusiveInitiative = "alert.exclusiveInitiative"
        const val incomingPayment = "alert.incomingPayment"
        const val incorrectPhrase = "alert.incorrectPhrase"
        const val incorrectPin = "alert.incorrectPin"
        const val insufficientOnchainBalance = "alert.insufficientOnchainBalance"
        const val invalidWords = "alert.invalidWords"
        const val lightningExplanation = "alert.lightningExplanation"
        const val lowFee = "alert.lowFee"
        const val missingWords = "alert.missingWords"
        const val noScreenshot = "alert.noScreenshot"
        const val notificationsRequired = "alert.notificationsRequired"
        const val onlyIban = "alert.onlyIban"
        const val paymentRequest = "alert.paymentRequest"
        const val paymentRequestFailed = "alert.paymentRequestFailed"
        const val pinLength = "alert.pinLength"
        const val pinRequired = "alert.pinRequired"
        const val receiveNotificationsDenied = "alert.receiveNotificationsDenied"
        const val receiveNotificationsPrompt = "alert.receiveNotificationsPrompt"
        const val resendCode = "alert.resendCode"
        const val swapValidationFailed = "alert.swapValidationFailed"
        const val syncingWallet = "alert.syncingWallet"
        const val textField = "alert.textField"
        const val transactionError = "alert.transactionError"
        const val withdrawRequest = "alert.withdrawRequest"
    }
    object Article {
        const val downButton = "article.downButton"
        const val tableView = "article.tableView"
    }
    object Buy {
        const val continueButton = "buy.continueButton"
        const val downButton = "buy.downButton"
        const val headerLabel = "buy.headerLabel"
        const val paymentModeButton = "buy.paymentModeButton"
        const val paymentModeSwitch = "buy.paymentModeSwitch"
        const val yourCode = "buy.yourCode"
        const val yourEmail = "buy.yourEmail"
        const val yourIban = "buy.yourIban"
    }
    object Core {
        const val launchComplete = "core.launchComplete"
    }
    object Device {
        object Darkmode {
            const val deviceButton = "device.darkmode.deviceButton"
            const val moonButton = "device.darkmode.moonButton"
            const val sunButton = "device.darkmode.sunButton"
        }
        object Row {
            const val bittrpeer = "device.row.bittrpeer"
            const val currency = "device.row.currency"
            const val darkmode = "device.row.darkmode"
            const val devicetoken = "device.row.devicetoken"
            const val language = "device.row.language"
            const val lightningchannels = "device.row.lightningchannels"
            const val pendingpayouts = "device.row.pendingpayouts"
            const val publickey = "device.row.publickey"
            const val restore = "device.row.restore"
        }
    }
    object Header {
        const val downButton = "header.downButton"
        const val titleLabel = "header.titleLabel"
    }
    object History {
        // Runtime-indexed: position 0 → "history.swapComplete0", position 1 → "history.swapComplete1", …
        const val swapComplete = "history.swapComplete"
        fun swapCompleteAt(position: Int) = "history.swapComplete$position"
        // Runtime-indexed: position 0 → "history.swapPending0", position 1 → "history.swapPending1", …
        const val swapPending = "history.swapPending"
        fun swapPendingAt(position: Int) = "history.swapPending$position"
        // Runtime-indexed: position 0 → "history.transactionAmount0", position 1 → "history.transactionAmount1", …
        const val transactionAmount = "history.transactionAmount"
        fun transactionAmountAt(position: Int) = "history.transactionAmount$position"
        // Runtime-indexed: position 0 → "history.transactionButton0", position 1 → "history.transactionButton1", …
        const val transactionButton = "history.transactionButton"
        fun transactionButtonAt(position: Int) = "history.transactionButton$position"
    }
    object Home {
        const val balanceCardButton = "home.balanceCardButton"
        const val balanceLabel = "home.balanceLabel"
        const val buyButton = "home.buyButton"
        const val currencyButton = "home.currencyButton"
        const val headerLabel = "home.headerLabel"
        const val headerSpinner = "home.headerSpinner"
        const val mapButton = "home.mapButton"
        const val profitButton = "home.profitButton"
        const val profitLabel = "home.profitLabel"
        const val receiveButton = "home.receiveButton"
        const val sendButton = "home.sendButton"
        const val syncStatusButton = "home.syncStatusButton"
    }
    object Loading {
        const val handlingLnurl = "loading.handlingLnurl"
        const val receivingPayment = "loading.receivingPayment"
        const val syncingWallet = "loading.syncingWallet"
    }
    object Map {
        const val mapSpinner = "map.mapSpinner"
        const val mapView = "map.mapView"
        object OnePlace {
            const val closeButton = "map.onePlace.closeButton"
            const val goToMapsButton = "map.onePlace.goToMapsButton"
            const val nameLabel = "map.onePlace.nameLabel"
            const val websiteButton = "map.onePlace.websiteButton"
        }
        const val placeCellButton = "map.placeCellButton"
        const val placeName = "map.placeName"
        const val placesTableView = "map.placesTableView"
        const val poweredByButton = "map.poweredByButton"
        const val userLocationButton = "map.userLocationButton"
    }
    object Move {
        const val channelButton = "move.channelButton"
        const val satsInstant = "move.satsInstant"
        const val satsRegular = "move.satsRegular"
        const val satsTotal = "move.satsTotal"
        const val subtitleLabel = "move.subtitleLabel"
        const val swapButton = "move.swapButton"
    }
    object Nav {
        const val academyButton = "nav.academyButton"
        const val settingsButton = "nav.settingsButton"
        const val walletButton = "nav.walletButton"
    }
    object Pin {
        const val button0 = "pin.button0"
        const val button1 = "pin.button1"
        const val button2 = "pin.button2"
        const val button3 = "pin.button3"
        const val button4 = "pin.button4"
        const val button5 = "pin.button5"
        const val button6 = "pin.button6"
        const val button7 = "pin.button7"
        const val button8 = "pin.button8"
        const val button9 = "pin.button9"
        const val buttonBackspace = "pin.buttonBackspace"
        const val confirmButton = "pin.confirmButton"
        const val pinTextField = "pin.pinTextField"
        const val restoreButton = "pin.restoreButton"
    }
    object Profits {
        const val subtitleLabel = "profits.subtitleLabel"
        const val totalInvestmentLabel = "profits.totalInvestmentLabel"
        const val totalProfitLabel = "profits.totalProfitLabel"
        const val totalValueLabel = "profits.totalValueLabel"
    }
    object Question {
        const val answerLabel = "question.answerLabel"
        const val channelView = "question.channelView"
        const val yellowCard = "question.yellowCard"
    }
    object Receive {
        const val addressLabel = "receive.addressLabel"
        const val addressTitle = "receive.addressTitle"
        const val amountTextField = "receive.amountTextField"
        const val copyButton = "receive.copyButton"
        const val currencyButton = "receive.currencyButton"
        const val currencyLabel = "receive.currencyLabel"
        const val editButton = "receive.editButton"
        const val invoiceLabel = "receive.invoiceLabel"
        const val moreButton = "receive.moreButton"
        const val qrImageView = "receive.qrImageView"
        const val qrSpinner = "receive.qrSpinner"
        const val questionButton = "receive.questionButton"
        const val refreshButton = "receive.refreshButton"
    }
    object Scanner {
        const val closeButton = "scanner.closeButton"
        const val scannerView = "scanner.scannerView"
    }
    object Send {
        const val amountTextField = "send.amountTextField"
        const val availableButton = "send.availableButton"
        const val availableLabel = "send.availableLabel"
        const val availableQuestionButton = "send.availableQuestionButton"
        const val bdkSpinner = "send.bdkSpinner"
        object Confirm {
            const val addressLabel = "send.confirm.addressLabel"
            const val amountFiatLabel = "send.confirm.amountFiatLabel"
            const val amountLabel = "send.confirm.amountLabel"
            const val confirmButton = "send.confirm.confirmButton"
            const val feeFastButton = "send.confirm.feeFastButton"
            const val feeSlowButton = "send.confirm.feeSlowButton"
        }
        const val currencyButton = "send.currencyButton"
        const val currencyLabel = "send.currencyLabel"
        const val nextButton = "send.nextButton"
        const val pasteButton = "send.pasteButton"
        const val regularButton = "send.regularButton"
        const val scanButton = "send.scanButton"
        const val switchQuestionButton = "send.switchQuestionButton"
        const val toLabel = "send.toLabel"
        const val toTextField = "send.toTextField"
    }
    object Settings {
        object Row {
            const val currency = "settings.row.currency"
            const val device = "settings.row.device"
            const val privacy = "settings.row.privacy"
            const val restore = "settings.row.restore"
            const val support = "settings.row.support"
            const val terms = "settings.row.terms"
            const val wallets = "settings.row.wallets"
        }
    }
    object Signup {
        object Bittr {
            object Initiative {
                const val cancelButton = "signup.bittr.initiative.cancelButton"
                const val confirmButton = "signup.bittr.initiative.confirmButton"
            }
            object Otp {
                const val codeButton = "signup.bittr.otp.codeButton"
                const val codeTextField = "signup.bittr.otp.codeTextField"
                const val nextButton = "signup.bittr.otp.nextButton"
                const val resendButton = "signup.bittr.otp.resendButton"
                const val topLabel = "signup.bittr.otp.topLabel"
            }
            object Start {
                const val emailButton = "signup.bittr.start.emailButton"
                const val emailTextField = "signup.bittr.start.emailTextField"
                const val ibanButton = "signup.bittr.start.ibanButton"
                const val ibanTextField = "signup.bittr.start.ibanTextField"
                const val nextButton = "signup.bittr.start.nextButton"
                const val skipButton = "signup.bittr.start.skipButton"
                const val topLabelOne = "signup.bittr.start.topLabelOne"
                const val topLabelThree = "signup.bittr.start.topLabelThree"
                const val topLabelTwo = "signup.bittr.start.topLabelTwo"
            }
            object Success {
                const val codeButton = "signup.bittr.success.codeButton"
                const val ibanButton = "signup.bittr.success.ibanButton"
                const val nameButton = "signup.bittr.success.nameButton"
                const val nextButton = "signup.bittr.success.nextButton"
                const val ourIbanLabel = "signup.bittr.success.ourIbanLabel"
                const val screenshotButton = "signup.bittr.success.screenshotButton"
                const val topLabelOne = "signup.bittr.success.topLabelOne"
                const val topLabelTwo = "signup.bittr.success.topLabelTwo"
                const val yourCodeLabel = "signup.bittr.success.yourCodeLabel"
            }
            object TransferInfo {
                const val amountLabel = "signup.bittr.transferInfo.amountLabel"
                const val amountTitle = "signup.bittr.transferInfo.amountTitle"
                const val backButton = "signup.bittr.transferInfo.backButton"
                const val connectionLabel = "signup.bittr.transferInfo.connectionLabel"
                const val connectionTitle = "signup.bittr.transferInfo.connectionTitle"
                const val dcaLabel = "signup.bittr.transferInfo.dcaLabel"
                const val dcaTitle = "signup.bittr.transferInfo.dcaTitle"
                const val lightningLabel = "signup.bittr.transferInfo.lightningLabel"
                const val lightningTitle = "signup.bittr.transferInfo.lightningTitle"
                const val nextButton = "signup.bittr.transferInfo.nextButton"
            }
        }
        object Create {
            object Confirm {
                const val cancelButton = "signup.create.confirm.cancelButton"
                const val nextButton = "signup.create.confirm.nextButton"
                const val switchOne = "signup.create.confirm.switchOne"
                const val switchTwo = "signup.create.confirm.switchTwo"
                const val topLabel = "signup.create.confirm.topLabel"
            }
            object Mnemonic {
                const val mnemonicStack = "signup.create.mnemonic.mnemonicStack"
                const val nextButton = "signup.create.mnemonic.nextButton"
                const val topLabelOne = "signup.create.mnemonic.topLabelOne"
                // Runtime-indexed: position 0 → "signup.create.mnemonic.word1", position 1 → "signup.create.mnemonic.word2", …
                const val word = "signup.create.mnemonic.word"
                fun wordAt(position: Int) = "signup.create.mnemonic.word${position + 1}"
            }
            object PinConfirm {
                const val topLabel = "signup.create.pinConfirm.topLabel"
            }
            object PinSet {
                const val topLabel = "signup.create.pinSet.topLabel"
            }
            object Ready {
                const val continueButton = "signup.create.ready.continueButton"
                const val skipButton = "signup.create.ready.skipButton"
                const val topLabelOne = "signup.create.ready.topLabelOne"
            }
            object Start {
                const val articleButton = "signup.create.start.articleButton"
                const val createWalletButton = "signup.create.start.createWalletButton"
                const val headerLabel = "signup.create.start.headerLabel"
                const val restoreButton = "signup.create.start.restoreButton"
            }
            object Verify {
                const val backButton = "signup.create.verify.backButton"
                const val field1 = "signup.create.verify.field1"
                const val field2 = "signup.create.verify.field2"
                const val field3 = "signup.create.verify.field3"
                const val label1 = "signup.create.verify.label1"
                const val label2 = "signup.create.verify.label2"
                const val label3 = "signup.create.verify.label3"
                const val nextButton = "signup.create.verify.nextButton"
                const val topLabel = "signup.create.verify.topLabel"
            }
        }
        object Restore {
            const val field1 = "signup.restore.field1"
            const val field10 = "signup.restore.field10"
            const val field11 = "signup.restore.field11"
            const val field12 = "signup.restore.field12"
            const val field2 = "signup.restore.field2"
            const val field3 = "signup.restore.field3"
            const val field4 = "signup.restore.field4"
            const val field5 = "signup.restore.field5"
            const val field6 = "signup.restore.field6"
            const val field7 = "signup.restore.field7"
            const val field8 = "signup.restore.field8"
            const val field9 = "signup.restore.field9"
            const val nextButton = "signup.restore.nextButton"
            object PinConfirm {
                const val topLabel = "signup.restore.pinConfirm.topLabel"
            }
            object PinSet {
                const val topLabel = "signup.restore.pinSet.topLabel"
            }
            const val removeWalletButton = "signup.restore.removeWalletButton"
            const val topLabel = "signup.restore.topLabel"
        }
    }
    object Swap {
        const val amountTextField = "swap.amountTextField"
        const val fromButton = "swap.fromButton"
        const val fromLabel = "swap.fromLabel"
        const val nextButton = "swap.nextButton"
        const val subtitleLabel = "swap.subtitleLabel"
    }
    object SwapStatus {
        const val confirmCard = "swapStatus.confirmCard"
        const val confirmStatusLabel = "swapStatus.confirmStatusLabel"
        const val refreshButton = "swapStatus.refreshButton"
    }
    object Sync {
        const val closeButton = "sync.closeButton"
        const val statusView = "sync.statusView"
    }
    object Transaction {
        const val addNoteButton = "transaction.addNoteButton"
        const val bittrFeeButton = "transaction.bittrFeeButton"
        const val copyBottomIdButton = "transaction.copyBottomIdButton"
        const val copyIdButton = "transaction.copyIdButton"
        const val descriptionButton = "transaction.descriptionButton"
        const val descriptionLabel = "transaction.descriptionLabel"
        const val labelAmount = "transaction.labelAmount"
        const val labelDate = "transaction.labelDate"
        const val labelNote = "transaction.labelNote"
        const val swapStatusButton = "transaction.swapStatusButton"
        const val transferFeeButton = "transaction.transferFeeButton"
        const val urlIdButton = "transaction.urlIdButton"
        const val yellowCard = "transaction.yellowCard"
    }
    object Unlock {
        const val topLabel = "unlock.topLabel"
    }
    object Value {
        const val currentValueLabel = "value.currentValueLabel"
        const val fiveYearsButton = "value.fiveYearsButton"
        const val graphValueLabel = "value.graphValueLabel"
        const val graphView = "value.graphView"
        const val monthButton = "value.monthButton"
        const val profitLabel = "value.profitLabel"
        const val valueSpinner = "value.valueSpinner"
        const val weekButton = "value.weekButton"
        const val yearButton = "value.yearButton"
    }
    object Website {
        const val downButton = "website.downButton"
    }
}
