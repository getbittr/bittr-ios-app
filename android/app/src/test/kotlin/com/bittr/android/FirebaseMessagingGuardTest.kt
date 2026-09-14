package com.bittr.android

import com.bittr.android.SourceTree.codeWithoutLiterals
import com.bittr.android.SourceTree.repoPath
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Keeps Firebase inside `:core:push-fcm`, and keeps the notification *permission* out of the
 * payout path (BIT-41 item 3).
 *
 * Two rules, one file, because they are two halves of the same decision: the push client is
 * split so that everything testable lives in `:core:push` and `:core:network` and the untestable
 * remainder is as small as it can be made. A guard is what keeps "as small as it can be made"
 * true after the next feature.
 *
 * ### Why the module boundary is worth a test
 *
 * `com.google.firebase:firebase-messaging` brings `firebase-common`, `firebase-installations`
 * and `play-services-basement` with it, and the Firebase BOM makes every other Firebase artefact
 * a one-line addition from any module that already has one. Analytics is the one that matters:
 * adding it collects events by default, against an app whose data-collection record (BIT-91) and
 * whose store listing say what it collects. That change would be one line in a build file, in a
 * feature module, for an unrelated reason. This is the tripwire.
 *
 * ### Why the permission rule is worth a test
 *
 * BIT-41 deliverable 3 states it and it is the least obvious fact in the whole issue:
 *
 * > the runtime permission does **not** gate data-message delivery — the silent payout path
 * > works without it; only user-visible types need it.
 *
 * `api-contract` §3.3 requires the payout push to be a **data-only** message precisely so the app
 * is invoked while backgrounded, and a data message is delivered whether or not
 * `POST_NOTIFICATIONS` was ever granted. So a permission check anywhere on the token or receive
 * path breaks instant payouts for every customer who declined a dialog about *alerts* — and
 * breaks them silently, because everything visible still works. §4.3 then turns that into a
 * permanent `onchain` downgrade: no token sent, no route.
 *
 * The permission itself is not the problem and is correctly declared and requested; where it is
 * *read* is the problem.
 */
class FirebaseMessagingGuardTest {

    private companion object {

        /** The one module allowed to reach Firebase. */
        const val FIREBASE_MODULE = "core/push-fcm"

        /**
         * Firebase artefacts this app does not have, by coordinate fragment.
         *
         * Not an exhaustive list of the BOM's contents — an exhaustive list would need updating
         * with every Firebase release and would fail open on the next new one. [FIREBASE_GROUP]
         * below is the closed rule; this list exists to name the ones whose arrival would be a
         * compliance event rather than only an architectural one, so the failure message says
         * *why* instead of only *no*.
         */
        val NAMED_BANNED_ARTEFACTS = listOf(
            "firebase-analytics",
            "firebase-crashlytics",
            "firebase-perf",
            "firebase-config",
            "firebase-inappmessaging",
            "google-analytics",
        )

        /** The Firebase Gradle group, matched in build files. */
        const val FIREBASE_GROUP = "com.google.firebase"

        /** The one artefact that is allowed, by catalog alias and by coordinate. */
        val ALLOWED_FIREBASE = listOf("firebase-messaging", "firebase-bom", "firebase.messaging", "firebase.bom")

        /**
         * The permission, as it can be named in Kotlin.
         *
         * `BittrPermissions.NOTIFICATIONS` is the app's own constant and is how the UI names it;
         * both spellings are searched, because the rule is about the *check*, not the spelling.
         */
        val PERMISSION_SYMBOLS = listOf(
            "POST_NOTIFICATIONS",
            "BittrPermissions.NOTIFICATIONS",
            "areNotificationsEnabled",
            "NotificationManagerCompat",
        )

        /**
         * The modules on the payout path — where a permission check must not appear.
         *
         * `:core:push` decodes the payload, `:core:network` decides what to send and when, and
         * `:core:push-fcm` receives. None of the three has any business asking whether the
         * customer wants to *see* an alert.
         */
        val PAYOUT_PATH_MODULES = listOf("core/push/", "core/push-fcm/", "core/network/")

        /** Files that state these rules rather than break them. */
        val ALLOWED_FILES = setOf("FirebaseMessagingGuardTest.kt")

        /**
         * The collision these two assertions exist to catch, and how it was settled.
         *
         * BIT-133's background wake once added a *second* `BittrMessagingService`, in `:app`,
         * with its own `<service>` entry and its own Firebase dependency. BIT-146 folded it into
         * this module's service: the wake reaches it through `PushHost.dataMessageWake` and runs
         * before the decode.
         *
         * Appended to the failure messages because the obvious way to make this test green is
         * also the wrong one: deleting a `<service>` entry silently turns off either the
         * background wake or the payout decode, and the build stays green either way.
         */
        val MERGE_NOTE =
            "There is one FirebaseMessagingService, in :core:push-fcm (BIT-146). The manifest " +
                "merger unions two services filtering MESSAGING_EVENT rather than rejecting " +
                "them — after which FCM starts whichever one it resolves first and the other " +
                "silently never runs. The background wake (node start) and the payload decode " +
                "+ token registration both ride on that one service; add behaviour through " +
                "PushHost, not a second <service>. Do not silence this test to make a merge green."
    }

    /**
     * A Gradle script's *declarations*, with its comments removed.
     *
     * The same rule the Kotlin guards state at length in [SourceTree.codeWithoutLiterals], and it
     * bit immediately: the comment in `app/build.gradle.kts` explaining that `:core:push-fcm` is
     * the only path by which `com.google.firebase` reaches that classpath made
     * `app/build.gradle.kts` look like a second declaration of it. A guard that counts sentences
     * has one stable outcome — the next person deletes the sentence.
     *
     * String literals are kept, because a dependency coordinate *is* a string literal.
     */
    private fun File.declarations(): String =
        SourceTree.stripKotlin(readText(), keepStringLiterals = true)

    // ------------------------------------------------------------------ the module boundary

    @Test
    fun `firebase is declared in exactly one module`() {
        val declaringFiles = SourceTree.buildFiles()
            .filterNot { it.name == "libs.versions.toml" }
            .filter { FIREBASE_GROUP in it.declarations() || "firebase" in it.declarations() }
            .map { it.repoPath() }

        assertEquals(
            "Firebase must be reachable from $FIREBASE_MODULE and nowhere else — the BOM makes " +
                "analytics one line away from any module that already has a Firebase " +
                "dependency, and BIT-91 records what this app collects. Declared in: " +
                declaringFiles +
                "\n\n$MERGE_NOTE",
            listOf("$FIREBASE_MODULE/build.gradle.kts"),
            declaringFiles,
        )
    }

    @Test
    fun `no Firebase artefact beyond messaging is on the graph`() {
        val offences = SourceTree.buildFiles().flatMap { file ->
            // The catalog is read raw: it is a declaration file with no code to separate prose
            // from, and its `#` comments are not Kotlin comments anyway. Every other build file
            // goes through the comment strip, for the reason on [declarations].
            val text = if (file.name == "libs.versions.toml") file.readText() else file.declarations()
            NAMED_BANNED_ARTEFACTS.filter { it in text }.map { "${file.repoPath()}: $it" }
        }

        assertEquals(
            "The Firebase BOM covers far more than messaging and none of it is wanted here. " +
                "firebase-analytics in particular starts collecting events by default, which is " +
                "a change to what the app collects (BIT-91) made in a build file. Found: $offences",
            emptyList<String>(),
            offences,
        )
    }

    @Test
    fun `only firebase-messaging and the BOM are named`() {
        val catalog = File(SourceTree.root, "gradle/libs.versions.toml")
        val firebaseLines = catalog.readLines()
            .filter { FIREBASE_GROUP in it || Regex("""^\s*firebase-""").containsMatchIn(it) }
            .map { it.trim() }

        val unexpected = firebaseLines.filterNot { line -> ALLOWED_FIREBASE.any { it in line } }

        assertEquals(
            "Every Firebase coordinate in the catalog should be the messaging artefact or the " +
                "BOM that versions it. Unexpected: $unexpected",
            emptyList<String>(),
            unexpected,
        )
    }

    @Test
    fun `Firebase types are referenced only from the module that owns them`() {
        val offenders = SourceTree.kotlinSources(*ALLOWED_FILES.toTypedArray())
            .filterNot { FIREBASE_MODULE in it.repoPath() }
            .filter { file ->
                val code = file.codeWithoutLiterals()
                "com.google.firebase" in code || "FirebaseMessaging" in code
            }
            .map { it.repoPath() }

        assertEquals(
            "Firebase types belong to $FIREBASE_MODULE. Everything above it takes " +
                "DeviceTokenSource and PushDelivery, which is what makes the push rules JVM-" +
                "testable at all. Found in: $offenders",
            emptyList<String>(),
            offenders,
        )
    }

    // ------------------------------------------------------------------ the manifest entry

    @Test
    fun `the messaging service is declared once, in its own module, and not exported`() {
        val declaring = SourceTree.manifests()
            .filter { "com.google.firebase.MESSAGING_EVENT" in it.readText() }

        assertEquals(
            "The <service> entry belongs beside the class it activates, and there must be " +
                "exactly one of it: two services filtering com.google.firebase.MESSAGING_EVENT " +
                "is not a build error, it is a coin toss at dispatch. Declared in: " +
                declaring.map { it.repoPath() } +
                "\n\n$MERGE_NOTE",
            listOf("$FIREBASE_MODULE/src/main/AndroidManifest.xml"),
            declaring.map { it.repoPath() },
        )

        val manifest = declaring.single().readText()
        assertTrue(
            "The FCM service is started by an explicit in-process broadcast from the Play " +
                "services client library. Nothing outside the app has any business starting it, " +
                "so it must be exported=\"false\".",
            Regex("""android:name="\.BittrMessagingService"[\s\S]*?android:exported="false"""")
                .containsMatchIn(manifest),
        )
    }

    // ------------------------------------------------------------------ the permission

    @Test
    fun `the payout path never checks the notification permission`() {
        val offences = SourceTree.kotlinSources(*ALLOWED_FILES.toTypedArray())
            .filter { file -> PAYOUT_PATH_MODULES.any { it in file.repoPath().replace('\\', '/') } }
            .flatMap { file ->
                val code = file.codeWithoutLiterals()
                PERMISSION_SYMBOLS.filter { it in code }.map { "${file.repoPath()}: $it" }
            }

        assertEquals(
            "POST_NOTIFICATIONS does not gate FCM data-message delivery, and the lightning " +
                "payout push is data-only by contract (api-contract §3.3). A permission check " +
                "on this path would break instant payouts for every customer who declined a " +
                "dialog about alerts, silently — and §4.3 would then read it as 'no token sent' " +
                "and downgrade them to onchain. Found: $offences",
            emptyList<String>(),
            offences,
        )
    }

    @Test
    fun `the permission is still declared and still named in one place`() {
        // The other half of the rule: not gating on it is not the same as not having it. The
        // user-visible push types need the grant, and Device details asks for it — the port of
        // iOS's askForPushNotifications().
        val manifest = File(SourceTree.root, "app/src/main/AndroidManifest.xml").readText()
        assertTrue(
            "POST_NOTIFICATIONS must stay declared — the user-visible notification types need it.",
            "android.permission.POST_NOTIFICATIONS" in manifest,
        )

        val permissionsFile = File(
            SourceTree.root,
            "core/permissions/src/main/kotlin/com/bittr/android/core/permissions/BittrPermissions.kt",
        )
        assertTrue(
            "BittrPermissions is the one place a permission string is spelled out.",
            "POST_NOTIFICATIONS" in permissionsFile.readText(),
        )
    }
}
