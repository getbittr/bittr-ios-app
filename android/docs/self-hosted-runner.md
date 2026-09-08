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

The workflow installs the Android SDK, AVD and Maestro itself, so nothing else needs
pre-installing. Java is pinned to 17 (see `JAVA_VERSION` in the workflow);
`actions/setup-java` will provision it, but having a system JDK avoids a download
per job.

### 3. Disk

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

**Security.** A self-hosted runner executes code from any workflow that targets it.
Do not attach this runner to a public fork-PR workflow; the `pull_request` trigger
on a public repo runs fork code. `bittr-ios-app` being private is what makes this
acceptable — revisit if that ever changes.

## Verifying before you trust it

Run the workflow via `workflow_dispatch` and check, in order:

1. The `Preflight` step prints `KVM OK` and names your host.
2. The emulator boots in roughly a minute, not five.
3. `shared/flows/android/scaffold_smoke.yaml` passes.
4. **Three consecutive dispatches all pass.** This is the actual definition of done
   for BIT-5, and one green run does not establish it — a flaky pass is a failure.

Then report the per-run wall-clock number.
