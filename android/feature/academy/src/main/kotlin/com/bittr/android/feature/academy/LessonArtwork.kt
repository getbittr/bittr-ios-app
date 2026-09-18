package com.bittr.android.feature.academy

import androidx.annotation.DrawableRes

/**
 * The tile artwork for each lesson, keyed by [Lesson.image].
 *
 * iOS bundles these in the asset catalogue and looks them up by name
 * (`UIImage(named: thisLesson.image!)`, `LevelTableViewCell.swift:141`), so they are
 * bundled here too rather than fetched. The iOS originals are 1024 px JPEGs, about
 * 4.8 MB for the set; a tile is about 100 dp wide, so they are shipped as 384 px WebP
 * (`lesson_<image>.webp`, roughly 95 KB together), which still covers a tile at
 * xxxhdpi.
 *
 * An explicit table rather than `Resources.getIdentifier`: release builds shrink
 * resources, and a name built at runtime is invisible to the shrinker, which would
 * strip the artwork and leave every tile blank. `LessonArtworkTest` checks the table
 * covers every lesson.
 */
internal object LessonArtwork {

    @DrawableRes
    fun forImage(image: String?): Int? = when (image) {
        "whatisbitcoin" -> R.drawable.lesson_whatisbitcoin
        "whataresatoshis" -> R.drawable.lesson_whataresatoshis
        "theproblemwithfiatcurrencies" -> R.drawable.lesson_theproblemwithfiatcurrencies
        "whydopeopleinvest" -> R.drawable.lesson_whydopeopleinvest
        "whyisbitcoinvolatile" -> R.drawable.lesson_whyisbitcoinvolatile
        "whatismining" -> R.drawable.lesson_whatismining
        "whatiscore" -> R.drawable.lesson_whatiscore
        "seedphrase" -> R.drawable.lesson_seedphrase
        "whoownsthemostbitcoin" -> R.drawable.lesson_whoownsthemostbitcoin
        "sendingandreceiving" -> R.drawable.lesson_sendingandreceiving
        "whatislightning" -> R.drawable.lesson_whatislightning
        "introductiontowallets" -> R.drawable.lesson_introductiontowallets
        "whatisablockchain" -> R.drawable.lesson_whatisablockchain
        "howprivateisbitcoin" -> R.drawable.lesson_howprivateisbitcoin
        "canbitcoinbehacked" -> R.drawable.lesson_canbitcoinbehacked
        "bitcoinversuscrypto" -> R.drawable.lesson_bitcoinversuscrypto
        "bitcoinwhitepaperday" -> R.drawable.lesson_bitcoinwhitepaperday
        "forbiddenbitcoin" -> R.drawable.lesson_forbiddenbitcoin
        "badfortheenvironment" -> R.drawable.lesson_badfortheenvironment
        "bitcoinforks" -> R.drawable.lesson_bitcoinforks
        "21millioncoins" -> R.drawable.lesson_21millioncoins
        "whatisutxomanagement" -> R.drawable.lesson_whatisutxomanagement
        else -> null
    }
}
