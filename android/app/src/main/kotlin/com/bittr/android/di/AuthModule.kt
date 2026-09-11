package com.bittr.android.di

import com.bittr.android.BuildConfig
import com.bittr.android.core.common.AuthCapabilities
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * The one place a build type's authentication capabilities become a value the rest
 * of the app can read.
 *
 * Feature modules cannot see `:app`'s `BuildConfig`, so unlock (DEV-17) must inject
 * [AuthCapabilities] rather than reading the flag. That indirection is the point —
 * it means there is exactly one binding to audit when asking "can a biometric
 * prompt appear in the build CI installs?", and the answer for
 * `com.bittr.android.regtest` is no.
 */
@Module
@InstallIn(SingletonComponent::class)
object AuthModule {

    @Provides
    @Singleton
    fun provideAuthCapabilities(): AuthCapabilities = BuildConfigAuthCapabilities

    private object BuildConfigAuthCapabilities : AuthCapabilities {
        override val biometricUnlockEnabled: Boolean = BuildConfig.BIOMETRIC_UNLOCK_ENABLED
    }
}
