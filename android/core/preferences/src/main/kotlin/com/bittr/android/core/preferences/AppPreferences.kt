package com.bittr.android.core.preferences

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The two device settings the user can change and the app has to remember: the
 * dark-mode choice and the display currency.
 *
 * Both are written by Device details (`ios/bittr/Settings/DeviceViewController`) and
 * read somewhere else — the theme at the app root, the currency by Home's conversion
 * label — so neither can live in a screen's `ViewModel`.
 *
 * **`SharedPreferences`, not DataStore.** Two enum values, read synchronously once at
 * launch by the theme. DataStore's value is its asynchronous, transactional API, and
 * the one place that matters here is the one place it would hurt: the theme has to
 * know light-or-dark *before* the first frame, and a suspending read means either a
 * flash of the wrong theme or a blocking `runBlocking` that undoes the point. The
 * apply-vs-commit distinction is the only durability question and [set] uses `apply`
 * with an in-memory [StateFlow] in front of it, so a reader never waits on the disk.
 *
 * The flows are hot and seeded from disk at construction, which is why this is a
 * `@Singleton`: two instances would each hold their own copy of the value and the
 * second writer's change would not reach the first one's collectors.
 */
@Singleton
class AppPreferences @Inject constructor(@ApplicationContext context: Context) {

    private val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    private val _darkMode = MutableStateFlow(read(KEY_DARK_MODE, DarkModeSetting.entries, DEFAULT_DARK_MODE))
    private val _currency = MutableStateFlow(read(KEY_CURRENCY, Currency.entries, DEFAULT_CURRENCY))

    /** How the app decides light or dark. See [DarkModeSetting]. */
    val darkMode: StateFlow<DarkModeSetting> = _darkMode.asStateFlow()

    /** The fiat currency amounts are shown in. */
    val currency: StateFlow<Currency> = _currency.asStateFlow()

    fun setDarkMode(setting: DarkModeSetting) {
        prefs.edit().putString(KEY_DARK_MODE, setting.name).apply()
        _darkMode.value = setting
    }

    fun setCurrency(currency: Currency) {
        prefs.edit().putString(KEY_CURRENCY, currency.name).apply()
        _currency.value = currency
    }

    /**
     * Reads an enum by name, falling back to [fallback] on anything unexpected.
     *
     * A stored name that no longer matches a constant is not a corruption to report —
     * it is what a downgrade, or a renamed constant, looks like. Throwing would make
     * the app unopenable over a colour scheme.
     */
    private fun <T : Enum<T>> read(key: String, values: List<T>, fallback: T): T {
        val stored = prefs.getString(key, null) ?: return fallback
        return values.firstOrNull { it.name == stored } ?: fallback
    }

    private companion object {
        const val FILE = "bittr.settings"
        const val KEY_DARK_MODE = "darkMode"
        const val KEY_CURRENCY = "currency"

        /**
         * iOS defaults to the system appearance (`CacheManager.darkMode()` → `.device`)
         * and so does this — see the note on `BittrTheme` and DEV-03.
         */
        val DEFAULT_DARK_MODE = DarkModeSetting.Device

        /** iOS ships EUR as the default currency. */
        val DEFAULT_CURRENCY = Currency.EUR
    }
}

/**
 * The three states of the Device screen's dark-mode control — iOS's `DarkMode` enum,
 * and the same three buttons (`device.darkmode.sunButton`, `moonButton`,
 * `deviceButton`).
 */
enum class DarkModeSetting {
    /** Always light, whatever the system is set to. */
    Light,

    /** Always dark. */
    Dark,

    /** Follow the system. iOS's `.device`, and the default on both platforms. */
    Device,
}

/**
 * The currencies iOS offers in `DeviceViewController.changeCurrency()`.
 *
 * [label] is what the picker shows and what `features/settings.yaml` taps by text —
 * `"EUR €"` and `"CHF"`, exactly as the iOS action sheet spells them. Changing either
 * string breaks the flow on both platforms, so they are here rather than in a strings
 * file the Android side could drift on its own.
 */
enum class Currency(val code: String, val symbol: String, val label: String) {
    EUR("EUR", "€", "EUR €"),
    CHF("CHF", "CHF", "CHF"),
}
