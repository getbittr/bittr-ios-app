package com.bittr.android.swap

import com.bittr.android.push.SwapPushHandler
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import com.bittr.android.core.swaps.SwapPushHandler as SwapsPushHandler

/**
 * A `swap_notification` push, handed from the push coordinator to swaps — `PushHandlingModule`
 * declares the hook optional; this fills it with the process's `SwapCoordinator`.
 */
@Module
@InstallIn(SingletonComponent::class)
object SwapPushHooksModule {

    @Provides
    fun provideSwapPushHook(swaps: SwapsPushHandler): SwapPushHandler =
        SwapPushHandler { push -> swaps.onSwapPush(push.swapId, push.status) }
}
