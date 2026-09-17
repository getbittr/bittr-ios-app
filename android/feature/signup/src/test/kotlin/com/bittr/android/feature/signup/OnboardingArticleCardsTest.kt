package com.bittr.android.feature.signup

import androidx.compose.runtime.Composable
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.feature.academy.BittrArticles
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * The onboarding pages' article cards — iOS's `pageArticle1Slug` on Signup1, Signup2, Signup3,
 * Signup7 and RestoreViewController. `happy_path_wallet.yaml` taps
 * `signup.create.start.articleButton` and expects `article.downButton`.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
class OnboardingArticleCardsTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val opened = mutableListOf<String>()

    private fun title(slug: String): String =
        BittrArticles.article(RuntimeEnvironment.getApplication(), slug)!!.title

    private fun show(content: @Composable (onOpen: (String) -> Unit) -> Unit) {
        composeRule.setContent { BittrTheme { content { opened += it } } }
    }

    /** [scroll] on the pages that scroll (Signup3, Restore); Signup2 and Signup7 fit the screen. */
    private fun tapCard(slug: String, scroll: Boolean = false) {
        val card = composeRule.onNodeWithText(title(slug))
        if (scroll) card.performScrollTo()
        card.assertIsDisplayed().performClick()
    }

    @Test
    fun `Signup1's card carries the flow's id and opens what-is-bittr`() {
        show { SignupStartScreen(onOpenArticle = it) }
        composeRule.onNodeWithTag(TestID.Signup.Create.Start.articleButton).assertIsDisplayed().performClick()
        assertEquals(listOf(BittrArticles.WHAT_IS_BITTR), opened)
    }

    @Test
    fun `Signup2's card opens what-is-a-bitcoin-wallet`() {
        show { ConfirmScreen(onUnderstood = {}, onBack = {}, onOpenArticle = it) }
        tapCard(BittrArticles.WHAT_IS_A_BITCOIN_WALLET)
        assertEquals(listOf(BittrArticles.WHAT_IS_A_BITCOIN_WALLET), opened)
    }

    @Test
    fun `Signup3's card opens wallet-recovery`() {
        show {
            MnemonicScreen(
                mnemonic = Mnemonic(
                    listOf(
                        "abandon", "ability", "able", "about", "above", "absent",
                        "absorb", "abstract", "absurd", "abuse", "access", "accident",
                    ),
                ),
                onNext = {},
                onOpenArticle = it,
            )
        }
        tapCard(BittrArticles.WALLET_RECOVERY, scroll = true)
        assertEquals(listOf(BittrArticles.WALLET_RECOVERY), opened)
    }

    @Test
    fun `Signup7's card opens what-is-bittr`() {
        show { ReadyScreen(onContinue = {}, onSkip = {}, onOpenArticle = it) }
        tapCard(BittrArticles.WHAT_IS_BITTR)
        assertEquals(listOf(BittrArticles.WHAT_IS_BITTR), opened)
    }

    @Test
    fun `Restore's card opens wallet-recovery`() {
        show { RestoreScreen(onSubmit = {}, onCancel = {}, onOpenArticle = it) }
        tapCard(BittrArticles.WALLET_RECOVERY, scroll = true)
        assertEquals(listOf(BittrArticles.WALLET_RECOVERY), opened)
    }

    @Test
    fun `no card without a way to open it`() {
        show { SignupStartScreen() }
        composeRule.onNodeWithTag(TestID.Signup.Create.Start.articleButton).assertDoesNotExist()
    }

    @Test
    fun `the new slugs have their header images`() {
        listOf(BittrArticles.WHAT_IS_A_BITCOIN_WALLET, BittrArticles.WALLET_RECOVERY).forEach { slug ->
            assert(BittrArticles.imageRes(slug) != null) { "no image for $slug" }
        }
    }
}
