package com.bittr.android.feature.academy

import android.content.Context

/**
 * Which lessons this wallet has finished.
 *
 * iOS keeps the set in `CacheManager` alongside wallet data
 * (`getCompletedLessons` / `addCompletedLesson`). Here it is its own store, for the
 * same reason `:core:preferences` was split out of the wallet seam on the Android
 * side: lesson progress is not wallet state, and putting it behind the wallet API
 * would mean BIT-6 owning a value the Academy writes.
 *
 * An interface because the unlock rule is the part worth testing and it should not
 * need a `Context` to exercise — see `LessonUnlockTest`.
 */
interface LessonProgressStore {

    fun completedLessonIds(): Set<String>

    fun markCompleted(lessonId: String)
}

/** The shipped store. Ids only; no timestamps, matching iOS. */
class SharedPreferencesLessonProgressStore(context: Context) : LessonProgressStore {

    private val preferences =
        context.applicationContext.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)

    override fun completedLessonIds(): Set<String> =
        preferences.getStringSet(KEY, emptySet()).orEmpty()

    override fun markCompleted(lessonId: String) {
        // A fresh set rather than mutating the one getStringSet returned: the
        // documented contract says the returned instance must not be modified, and
        // an in-place edit is persisted or not depending on whether the value was
        // still in the memory cache.
        preferences.edit()
            .putStringSet(KEY, completedLessonIds() + lessonId)
            .apply()
    }

    private companion object {
        const val FILE_NAME = "academy_progress"
        const val KEY = "completed_lesson_ids"
    }
}

/** In-memory store, for previews and for tests that do not want a `Context`. */
class InMemoryLessonProgressStore(
    initial: Set<String> = emptySet(),
) : LessonProgressStore {

    private var completed: Set<String> = initial

    override fun completedLessonIds(): Set<String> = completed

    override fun markCompleted(lessonId: String) {
        completed = completed + lessonId
    }
}
