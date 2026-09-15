package com.bittr.android

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Whether the app is on screen — iOS `UIApplication.shared.applicationState == .active`, which a
 * swap push checks before opening a screen. Set by [MainActivity]'s start and stop; this is a
 * single-activity app, so that is the process's foreground.
 */
@Singleton
class AppForeground @Inject constructor() {

    private val _isActive = MutableStateFlow(false)
    val isActive: StateFlow<Boolean> = _isActive.asStateFlow()

    fun setActive(active: Boolean) {
        _isActive.value = active
    }
}
