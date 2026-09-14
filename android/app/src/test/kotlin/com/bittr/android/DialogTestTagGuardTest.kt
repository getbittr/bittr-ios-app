package com.bittr.android

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Every Compose dialog must publish its test tags as resource ids.
 *
 * `MainActivity` sets `testTagsAsResourceId = true` on the app root, and that is what makes
 * `id:` selectors in `shared/flows/` work on Android. A dialog does not inherit it: an
 * `AlertDialog` composes into its own window with its own semantics root. Before this was
 * fixed every `alert.button.N` was invisible to Maestro, so each flow step that taps an
 * alert button failed as "element not found" while the alert was plainly on screen —
 * found on the first device run of `send_onchain.yaml`. Robolectric reads the semantics
 * tree directly and passes either way, which is why this is a source guard.
 */
class DialogTestTagGuardTest {

    private val dialogCall = Regex("""\b(Basic)?AlertDialog\s*\(|\bDialog\s*\(""")

    @Test
    fun `every file that composes a dialog exposes its test tags`() {
        val offenders = SourceTree.root
            .walkTopDown()
            .onEnter { it.name != "build" && it.name != ".gradle" }
            .filter { it.isFile && it.extension == "kt" && "/src/main/" in it.path.replace('\\', '/') }
            .filter { file -> dialogCall.containsMatchIn(file.readText()) }
            .filterNot { file ->
                val text = file.readText()
                "exposeTestTags()" in text || Regex("""testTagsAsResourceId\s*=\s*true""").containsMatchIn(text)
            }
            .map { it.relativeTo(SourceTree.root).path }
            .toList()

        assertTrue(
            "These files compose a dialog without publishing its test tags, so Maestro cannot " +
                "find anything inside it (alert.button.N and friends). Apply " +
                "`Modifier.exposeTestTags()` (in :core:designsystem) or set " +
                "`testTagsAsResourceId = true` on the dialog content:\n" + offenders.joinToString("\n"),
            offenders.isEmpty(),
        )
    }
}
