package com.bittr.android.swap

import com.bittr.android.AppForeground
import com.bittr.android.core.push.PushEnvelope
import com.bittr.android.core.swaps.SwapStore
import com.bittr.android.push.SwapPushHandler
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * A `swap_notification` push — iOS `handleSwapNotificationFromBackground` /
 * `handleSwapNotificationImmediately`. The push coordinator handles sign-in and sync; this opens
 * the latest swap's status screen, and only while the app is on screen. It never claims or
 * refunds: iOS does that from the swap screens, not from a push.
 */
@Module
@InstallIn(SingletonComponent::class)
object SwapPushHooksModule {

    @Provides
    fun provideSwapPushHook(
        store: SwapStore,
        launches: SwapLaunchRequests,
        foreground: AppForeground,
    ): SwapPushHandler = object : SwapPushHandler {

        override fun swapScreenOpen(): Boolean = launches.swapScreenOpen.value

        override suspend fun onSwapPush(push: PushEnvelope.Swap) {
            val latest = withContext(Dispatchers.IO) { store.latest() } ?: return
            // `applicationState == .active`: no status screen for an app in the background.
            if (!foreground.isActive.value) return
            val boltzId = latest.boltzId ?: return
            launches.post(SwapLaunchRequest.Status(boltzId))
        }
    }
}
