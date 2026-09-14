package com.bittr.android

/**
 * This test needs Google Play services on the image, so it runs in the
 * `fcm-delivery` job and nowhere else — **BIT-135**.
 *
 * ## Why an annotation rather than an `@Assume` or a source set
 *
 * The `:app` androidTest APK is built once and installed by two jobs that boot
 * deliberately different images:
 *
 * - `wallet-instrumented` runs **`default`** — AOSP, chosen because
 *   `BackupExclusionTest` needs `com.android.localtransport`, which no
 *   Play-flavoured image carries.
 * - `fcm-delivery` runs **`google_apis`** — which has Play services and, for
 *   exactly the same reason, no local backup transport.
 *
 * The two requirements are mutually exclusive on one AVD, so the class below has
 * to be excluded from the first job and be the whole of the second. Three ways to
 * do that, and the other two are worse:
 *
 * - **`@Assume`** would turn `wallet-instrumented` red for behaving correctly.
 *   `check-wallet-instrumented-results.py` treats **any** `<skipped/>` as a failed
 *   run — an assumption and an `@Ignore` are the same XML — and that rule is not
 *   negotiable, since a skipped test is precisely how a green run comes to prove
 *   nothing. `androidTestRegtest/` exists because BIT-132 hit this same wall.
 * - **A conditional source set**, the BIT-132 answer, costs a directory that
 *   nothing normally compiles and therefore rots; BIT-132 pays for it with a
 *   throwaway-value compile in the `build` job. It is the right shape when the
 *   *build* differs — there, the source set only makes sense against a configured
 *   APK. Here the APK is identical in both jobs and only the **image** differs, so
 *   the switch belongs at run time.
 * - **This annotation**, applied by the runner: `notAnnotation` in
 *   `ci-wallet-instrumented.sh`, `annotation` in `ci-fcm-delivery.sh`. Excluded
 *   tests emit no `<testcase>` at all rather than a `<skipped/>`, so neither
 *   gate sees a skip, and the class is compiled by every ordinary build.
 *
 * ## The failure directions, which are what makes this safe
 *
 * If the `notAnnotation` filter is ever dropped from `ci-wallet-instrumented.sh`,
 * these tests run on AOSP and fail loudly on [FcmDeliveryTest.playServicesAreOnThisImage]
 * — a legible red naming the image, not a silent green.
 *
 * If the `annotation` filter in `ci-fcm-delivery.sh` is ever misspelled, that job
 * matches no tests and `connectedDebugAndroidTest` exits 0 — the vacuous green.
 * `check-fcm-delivery-results.py` is what refuses it, by requiring each method
 * below by name.
 *
 * Not applied to methods anywhere yet; the target is declared so a future partial
 * class does not need this file edited to do the obvious thing.
 */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
annotation class RequiresPlayServices
