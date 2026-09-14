package com.bittr.android.lnurl

import com.bittr.android.core.network.HttpClient
import com.bittr.android.di.WalletComposition
import com.bittr.android.push.LnurlPushHandler
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * Someone paying the user's Lightning address, answered by [LightningAddressPush] over the one
 * wallet composition. `PushHandlingModule` declares the hook optional; this fills it. The alerts
 * around it are the push coordinator's.
 */
@Module
@InstallIn(SingletonComponent::class)
object LnurlPushHooksModule {

    @Provides
    fun provideLnurlPushHandler(composition: WalletComposition, http: HttpClient): LnurlPushHandler {
        val responder = LightningAddressPush(composition.lightning, http)
        return LnurlPushHandler { push ->
            val request = responder.request(push) ?: return@LnurlPushHandler false
            responder.handle(request).isSuccess
        }
    }
}
