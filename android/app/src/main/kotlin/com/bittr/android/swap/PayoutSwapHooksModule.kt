package com.bittr.android.swap

import com.bittr.android.push.PayoutSwapLauncher
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow

/** A request, from outside any screen, to open the swap screen. The navigation graph collects it. */
sealed interface SwapLaunchRequest {

    /**
     * "Swap & Instant Receive" on a channel-full payout — iOS `swapAndPayForNotification` →
     * `CoreToSwap` with `pendingSuggestedSwapAmount`: a lightning-to-onchain swap of that amount.
     */
    data class PayoutSwap(val notificationId: String, val suggestedSats: Long) : SwapLaunchRequest

    /** A swap push: the latest swap's status screen (`HomeToSwapStatus`). */
    data class Status(val boltzId: String) : SwapLaunchRequest
}

/**
 * The push coordinator has no navigation, so it posts here; and the swap screen says here whether
 * it is showing, which a swap push checks before opening another (iOS `swapVC != nil`).
 */
@Singleton
class SwapLaunchRequests @Inject constructor() {

    private val _requests = MutableSharedFlow<SwapLaunchRequest>(
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val requests: SharedFlow<SwapLaunchRequest> = _requests.asSharedFlow()

    private val _swapScreenOpen = MutableStateFlow(false)
    val swapScreenOpen: StateFlow<Boolean> = _swapScreenOpen.asStateFlow()

    fun post(request: SwapLaunchRequest): Boolean = _requests.tryEmit(request)

    fun setSwapScreenOpen(open: Boolean) {
        _swapScreenOpen.value = open
    }
}

/** How the navigation graph reaches [SwapLaunchRequests]. */
@dagger.hilt.android.lifecycle.HiltViewModel
class SwapLaunchViewModel @Inject constructor(val requests: SwapLaunchRequests) : androidx.lifecycle.ViewModel()

@Module
@InstallIn(SingletonComponent::class)
object PayoutSwapHooksModule {

    @Provides
    fun providePayoutSwapLauncher(requests: SwapLaunchRequests): PayoutSwapLauncher =
        PayoutSwapLauncher { notificationId, suggestedSats ->
            requests.post(SwapLaunchRequest.PayoutSwap(notificationId, suggestedSats))
        }
}
