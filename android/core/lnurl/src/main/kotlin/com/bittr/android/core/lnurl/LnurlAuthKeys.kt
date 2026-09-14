package com.bittr.android.core.lnurl

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * The LNURL-auth key derivation iOS uses — `getLNURLAuthSeed()` and `deriveLNURLAuthKey(forDomain:)`
 * (`SendLNURL.swift:590–599`, `758–773`). Not LUD-05's BIP32 path: bittr's own scheme, and the
 * only one that gives an existing iOS user the same identity on a site after moving to Android.
 *
 * - seed = HMAC-SHA256(key = the mnemonic trimmed and lower-cased, message = `bittr-lnurl-auth-seed-v1`)
 * - linking private key = HMAC-SHA256(key = seed, message = the callback's host, lower-cased)
 *
 * The signature over `k1` needs secp256k1 and lives where that library is.
 */
object LnurlAuthKeys {

    /** "Don't change this String without using version control." — iOS. */
    private const val SEED_LABEL = "bittr-lnurl-auth-seed-v1"

    fun seed(mnemonic: String): ByteArray =
        hmacSha256(key = mnemonic.trim().lowercase().toByteArray(Charsets.UTF_8), message = SEED_LABEL.toByteArray(Charsets.UTF_8))

    fun linkingPrivateKey(seed: ByteArray, domain: String): ByteArray =
        hmacSha256(key = seed, message = domain.lowercase().toByteArray(Charsets.UTF_8))

    /** `friendlyActionText()`: the Proceed button's label, and the verb in `lnauth1`. */
    fun actionText(action: String?): String = when (action?.lowercase()) {
        "login" -> "Log in"
        "register" -> "Register"
        "link" -> "Link account"
        else -> "Authenticate"
    }

    private fun hmacSha256(key: ByteArray, message: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256"))
            doFinal(message)
        }
}
