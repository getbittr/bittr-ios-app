# Self-hosted runner for the Android emulator job

What a host needs before `.github/workflows/android-maestro.yml` will run its
`maestro` job on it. Written so the runner works the first time it is registered
rather than after a cycle of red jobs.

Only the **emulator job** moves. `build` stays on GitHub-hosted runners: it needs no
special hardware, and keeping it there means a compile error still fails in about a
minute without waiting for the self-hosted host to be free.

## Switching the job over

```sh
gh variable set ANDROID_EMULATOR_RUNNER --body '["self-hosted","linux","x64","android"]'
```

The workflow reads
`${{ fromJSON(vars.ANDROID_EMULATOR_RUNNER || '["ubuntu-latest"]') }}`. Unset,
everything stays on GitHub-hosted runners — so setting this variable is the entire
switch, and unsetting it is the entire rollback. Nothing else changes.

**The value must be a JSON array**, not a comma-separated string. `runs-on` matches
a *list* of labels; a bare `"self-hosted,linux,x64"` is treated as one label named
`self-hosted,linux,x64`, which matches no runner — and the symptom is a job that
queues forever rather than an error.

The host must carry **all** the labels in the array. Set them when registering:
`./config.sh --labels linux,x64,android` (`self-hosted` is added automatically).

## Host requirements

### 1. KVM — the one that actually matters

```sh
[ -e /dev/kvm ] && echo present || echo MISSING
```

Without hardware acceleration the emulator does not fail, it **crawls**: boot goes
from about a minute to past any sane timeout, and the job dies at the 30-minute mark
with "Timeout waiting for emulator to boot". That reads like a flaky emulator and
sends you looking in the wrong place. The workflow preflights this and fails in
seconds instead.

- **Bare metal:** enable VT-x / AMD-V in firmware.
- **A VM (most likely case):** the hypervisor must expose **nested virtualisation**.
  This is off by default nearly everywhere. Proxmox: set the VM's CPU type to
  `host`. VMware: "Virtualize Intel VT-x/EPT". Cloud: GCP needs a nested-virt
  licence on the image; **EC2 does not support it except on `*.metal` instances** —
  if the plan is EC2, budget for metal or use GitHub-hosted runners for this job.
- **A container:** must be `--privileged` or have `--device=/dev/kvm`. A stock
  Docker-based runner will not have it.

The runner user needs read/write on the device:

```sh
sudo usermod -aG kvm "$(id -un)"   # then restart the runner service
```

Group membership is picked up at process start, so the runner service must be
restarted — not just the shell you tested in. This is the most common way the
preflight still fails after "I added the group".

### 2. Packages

```sh
sudo apt-get install -y openjdk-17-jdk curl unzip
```

The workflow installs the Android SDK, AVD and Maestro itself. Java is pinned to 17
(see `JAVA_VERSION` in the workflow); `actions/setup-java` will provision it, but
having a system JDK avoids a download per job.

### 3. `ANDROID_HOME` — the one thing the workflow cannot install for you

`android-emulator-runner` downloads and installs the SDK components (`cmdline-tools`,
`platform-tools`, `emulator`, the system image) rather than expecting them, so they do
**not** need pre-installing. But it installs them *into* `$ANDROID_HOME`, and it does
not pick a default. GitHub-hosted images set the variable; a freshly registered
self-hosted runner does not — and unset, the action expands the target path to the
literal string `undefined/cmdline-tools`. The failure then surfaces several steps later
as an `sdkmanager` error about a path nobody wrote, which is a poor clue.

Set it in the **runner service** environment, not your login shell — the service does
not read `.bashrc`. In the runner directory, `.env` is read at service start:

```sh
echo 'ANDROID_HOME=/opt/android-sdk' >> .env    # then restart the runner service
sudo mkdir -p /opt/android-sdk
sudo chown "$(id -un)" /opt/android-sdk         # the runner user must be able to write it
```

The workflow preflights this on non-GitHub-hosted runners and names the variable, so a
missing value costs seconds rather than a debugging session.

### 4. Disk

Budget **~25 GB**: system image (~8 GB), SDK and platform tools (~5 GB), AVD
snapshot (~3 GB), Gradle caches, plus artefacts. A self-hosted runner does **not**
get a clean disk per job the way a GitHub-hosted one does, so this fills up quietly
until jobs start failing for unrelated-looking reasons. Prune or monitor it.

## Things that behave differently from GitHub-hosted

**The AVD cache step becomes near-pointless — and can actively hurt.** The workflow
caches `~/.android/avd` keyed on `avd-api34-aosp-atd-x86_64`. On a persistent host
that directory survives between jobs anyway, so the cache is re-uploading something
already there. Worse, a stale local AVD and a restored cache can disagree. Once the
host is stable, consider dropping the `Cache AVD` and `Create AVD snapshot` steps
for self-hosted and letting the host keep the AVD.

**Jobs serialise.** One runner runs one job at a time. `build` and `maestro` are
separate jobs and `maestro` needs `build`, so this is fine today — but three
consecutive runs for the definition of done will run one after another, not in
parallel. Factor that into the wall-clock number: report per-run time, not total.

**State leaks between runs.** Emulator processes, an `adb` server, and a booted AVD
can survive a cancelled job and poison the next one. The single most useful thing to
add once this is real:

```sh
adb kill-server || true
pkill -f qemu-system || true
```

as a pre-job step or in the runner's job-started hook. A leaked emulator presents as
exactly the kind of intermittent failure that BIT-5 says to treat as a blocker
rather than paper over with retries — so it is worth eliminating structurally.

**The failure video needs the emulator console auth token.** On failure the job
uploads `maestro-video/scaffold_smoke.webm`, recorded via `adb emu screenrecord` —
an *emulator console* command, not an `adb shell` one. The console authenticates
against `~/.emulator_console_auth_token`, read from the **home directory of the user
running `adb`**. On a GitHub-hosted runner one user does everything, so this is
invisible. On a self-hosted host it is not: if the emulator is launched by a
different user than the runner service, or the service has no writable `HOME`, the
recording silently does not start.

That failure is non-fatal by design — the job still passes or fails on the flow
alone, and prints:

```
::warning::Could not start emulator screen recording (...)
```

So the symptom is a missing video on the one run you wanted it for. If you see that
warning, check `HOME` for the runner service and confirm
`~/.emulator_console_auth_token` exists after a boot. Everything else in
`maestro-debug/` (screenshot, view hierarchy, logs) is unaffected — it comes from
Maestro, not the console.

**Security.** A self-hosted runner executes code from any workflow that targets it.
Do not attach this runner to a public fork-PR workflow; the `pull_request` trigger
on a public repo runs fork code. `bittr-ios-app` being private is what makes this
acceptable — revisit if that ever changes.

## Verifying before you trust it

> **Prerequisite that is easy to trip over: `workflow_dispatch` needs this workflow on
> the _default_ branch.** GitHub only offers the manual trigger for workflow files that
> exist on the default branch — `master` here, which today contains no
> `.github/workflows/` directory at all. Until `android-maestro.yml` is merged to
> `master`, `gh workflow run android-maestro.yml --ref android` fails with *"could not
> find any workflows named android-maestro.yml"*, which reads like a typo rather than a
> branch-visibility rule. Merging it to `master` is the fix; the `paths:` filter means
> it stays dormant there until something under `android/` or `shared/flows/` changes.
>
> **Three pushes are now a valid substitute for three dispatches — this reverses what
> this document said earlier.** Push and `pull_request` runs used to share the
> concurrency group `android-maestro-<ref>-auto` with `cancel-in-progress: true`, so
> three pushes to the same branch cancelled runs 1 and 2 — the exact evidence-eating
> failure that keying dispatches on `github.run_id` exists to prevent, arriving through
> a different door. The advice here was to space the pushes out instead, which assumed
> someone is watching the run list and able to wait; nobody driving this from a headless
> environment can do either. The group is keyed on `github.sha` for non-dispatch events
> now, so every commit gets its own run and none of them cancel each other.
>
> What that costs: push twice while iterating and you pay for two emulator runs instead
> of one. That is the whole of the loss, and it is the same overlap case the DoD needs
> preserved, which is why the rule went rather than being special-cased.

Run the workflow via `workflow_dispatch` and check, in order:

1. The `Preflight` step prints `KVM OK` and names your host.
2. The emulator boots in roughly a minute, not five.
3. `shared/flows/android/scaffold_smoke.yaml` passes.
4. **Three consecutive runs all pass.** This is the actual definition of done
   for BIT-5, and one green run does not establish it — a flaky pass is a failure.

Then report the per-run wall-clock number.

### Why three runs in a row is safe to do

It was not, until recently. The workflow's `concurrency` group used to be keyed on the
ref alone with `cancel-in-progress: true`, which looks right — an older commit's emulator
run is dead weight — and is actively destructive here: run 2 would cancel run 1, run 3
would cancel run 2, and the evidence for the definition of done would be one result and
two cancellations. On this host it would have been quieter still, because a single runner
serialises jobs: runs 1 and 2 would have been cancelled while **queued**, having never
booted an emulator, showing up as greys in the run list rather than reds.

This was fixed for `workflow_dispatch` first, by keying manual runs on `github.run_id`,
and that fix was incomplete for a reason worth remembering: `workflow_dispatch` only
exists once the workflow is on the default branch, so at the time the fix landed it
protected the one route that could not yet be used, and left the only usable route —
pushing — exposed. Non-dispatch runs are keyed on `github.sha` now, so every commit gets
its own group too.

The general lesson is that supersede-cancellation and "prove it three times" are the same
mechanism read two ways, and this repo cares about the second. Guarded by the *Check no
run of this workflow can cancel another* step in the `build` job, which asserts the group
varies by both contexts — a property check, not a string match, so the group can still be
rewritten. It runs seconds in, before any emulator boots.

### The three runs must use the same Maestro

`MAESTRO_VERSION` in the workflow is pinned (currently `2.10.0`) and the install step
echoes `maestro --version` into the log. This matters more than it looks: the installer
defaults to `releases/latest`, so an unpinned harness lets the tool change between run 1
and run 3 — and "it went red and nothing changed" is the most expensive kind of CI
failure to chase. Maestro does move under this; recent versions route `takeScreenshot`
output into the `--debug-output` bundle rather than writing it relative to the working
directory. Bump the pin deliberately, in its own commit, and re-run the three runs.
