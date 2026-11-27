package com.bittr.android.core.designsystem

import androidx.compose.runtime.Composable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.CoroutineScope

/**
 * [create]'s value, kept by the nearest `ViewModelStoreOwner` — in a navigation destination, its
 * back-stack entry — rather than by this composition, and built on that owner's scope.
 *
 * A sheet is a navigation dialog destination, and navigation's `DialogHost` takes a dialog out of
 * composition when the app stops and puts it back when it starts (`PopulateVisibleList`, on
 * `ON_STOP` and `ON_START`). Whatever the sheet `remember`ed is rebuilt on the way back: the map's
 * open place after "Go to maps", what Send was given before the user left to copy an invoice, a
 * Buy signup left for its email code. iOS keeps a presented sheet as it was. The entry outlives
 * the app's stop and is cleared, cancelling the scope, when the sheet is popped.
 *
 * [key] tells two retained values in one destination apart.
 */
@Composable
fun <T : Any> rememberRetained(key: String, create: (CoroutineScope) -> T): T {
    val holder: RetainedHolder = viewModel(key = key) { RetainedHolder() }
    @Suppress("UNCHECKED_CAST")
    return holder.value as T? ?: create(holder.viewModelScope).also { holder.value = it }
}

internal class RetainedHolder : ViewModel() {
    var value: Any? = null
}
