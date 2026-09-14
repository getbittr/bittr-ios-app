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
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/** A request, from outside any screen, to open the swap screen. The navigation graph collects it. */
data class SwapLaunchRequest(val notificationId: String, val suggestedSats: Long)

/**
 * "Swap & Instant Receive" on a channel-full payout — iOS stores `pendingSuggestedSwapAmount` and
 * opens the swap screen. The push coordinator has no navigation, so it posts here.
 */
@Singleton
class SwapLaunchRequests @Inject constructor() {

    private val _requests = MutableSharedFlow<SwapLaunchRequest>(
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val requests: SharedFlow<SwapLaunchRequest> = _requests.asSharedFlow()

    fun post(request: SwapLaunchRequest): Boolean = _requests.tryEmit(request)
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
            requests.post(SwapLaunchRequest(notificationId, suggestedSats))
        }
}
