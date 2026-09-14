package com.bittr.android

/**
 * This test is a **phase of a host-driven sequence** and must not be run by the
 * undirected suite.
 *
 * BIT-132, K7. `android/docs/wallet-node-device-tests.md` §3 item 1 states the
 * constraint this annotation exists to enforce: *the test cannot observe its own
 * restart*. K7 is four instrumented runs against one emulator boot, with the
 * host funding the wallet, mining, holding an HTLC and killing the process in
 * between them. Run in any other order — or all four in one instrumentation,
 * which is what `connectedDebugAndroidTest` with no filter would do — they do not
 * merely fail, they fail *misleadingly*: phase 4 would assert about a payment
 * phase 3 had not sent yet and report a fund-safety property as broken.
 *
 * ## The mechanism, and why it is a filter rather than an `@Ignore`
 *
 * `android/scripts/ci-wallet-regtest.sh` runs the undirected suite with
 * `-Pandroid.testInstrumentationRunnerArguments.notAnnotation=com.bittr.android.HostDriven`,
 * and `android/scripts/k7-interrupted-payment.sh` then runs each phase by name.
 * AndroidX's runner applies `notAnnotation` **while building the test
 * description**, so an excluded method is never created, never executed and
 * never appears in the JUnit XML at all.
 *
 * That last property is the whole reason this is not `@Ignore`.
 * `check-wallet-regtest-results.py` treats any `<skipped/>` as a failed run — an
 * `@Ignore` reports exactly that — and it is right to: a skipped test does not
 * fail a build, which makes it the quietest way for a suite to stop measuring
 * anything. A filtered test is absent, and absence from a run the gate is not
 * reading is not a claim about anything.
 *
 * The counterpart, and it is what keeps this honest: the four phases **are** in
 * that gate's `REQUIRED` set by name, checked against the results directories the
 * host script preserves per phase. So excluding them from one run does not
 * excuse them from the verdict; it moves them to the run that can sequence them.
 *
 * ## The failure this costs, named
 *
 * A phase added here and not added to the host script is a test nothing runs,
 * and the gate catches that — `REQUIRED` names methods, and a method that never
 * executed is reported as "did not run at all". A phase added to the script and
 * not annotated is worse and quieter: it would also run inside the undirected
 * suite, out of order, and its red would be read as a K7 result.
 * `android/scripts/test_k7_host_phase.sh` pins the two lists against each other
 * in the build job, on a machine with no emulator, seconds after the edit.
 */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.FUNCTION, AnnotationTarget.CLASS)
annotation class HostDriven
