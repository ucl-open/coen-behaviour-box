# Backlog

## Raise upstream (open-rigs/open-rigs)

Found while building this workflow on 28 Oct 2026. Open each with the line `*Comment/research by Claude, read/edited by Pip.*` and a fix diff where it is short.

- **CameraTriggerController counts the register-dump reply as a trigger.** Comment on open-rigs#4, which already covers the Camera1 subject parsing the Camera0 register and StartCameras not starting output 1. Both trigger subjects parse every `BehaviorEvents` message, so with `DumpRegisters` on, the Read reply of `Camera0Frame` becomes one extra trigger at startup and the first CSV row comes out early (measured on the box before hw-behaviour-box added the filter). Fix: `FilterMessageType` (Include, Event) before each `Parse`. This repo filters locally in the `Camera` group.
- **RunningWheel takes a Difference in Displacement mode.** New issue. The include sets `EncoderMode` to `Displacement` and still runs `Difference`, `ConvertSigned` and `Accumulate`, which suits `Position` (a running count). The firmware settles it: in Displacement mode `app.c` reports `previous - timer_cnt` and then sets `previous = timer_cnt`, the change over each 2 ms sample, so the chain telescopes to the current sample minus the first, a speed sample rather than a distance. hw-behaviour-box, av-dome's `ActiveExperiments` branch and now this repo all replace the include with an inline copy set to `Position`. Fix: `Position` with the chain as is, or `Displacement` without the `Difference`. Not the same as ucl-open/acquisition#9 (encoder reset racing the subscription).
- **Template: generated files make a deployed clone look changed.** New issue, with the `.gitattributes` lines from this repo. `deploy.ps1` regenerates `*.Generated.cs` (written LF by bonsai.sgen) and the schema JSON and rig template (written CRLF by Python), so with `core.autocrlf=true`, Git for Windows' default, a fresh deploy leaves `git status` reporting the C# file as modified, and with `false` the other two.
- **Template: `deploy.ps1` ignores failures.** New issue. No native step's exit code is checked, and `Setup.ps1` exits 0 whatever Bonsai's restore returned, so a failed deploy exits 0. This repo's fix: `Assert-Success` after each step. `regenerate.py` also ignores `os.system`, which this repo keeps as the template has it (054f823): its sgen runs before `dotnet tool restore`, so on a fresh machine it always fails, and deploy's own checked sgen run catches a real failure.
- **Template: a new project's first deploy writes the C# classes to the project root.** New issue, drafted 29 Oct 2026. `deploy.ps1` runs `regenerate-schemas` (which calls `bonsai.sgen`) before `dotnet tool restore`, so on a machine without the tool cached that sgen run fails and never creates `src\Extensions`; `Push-Location .\src\Extensions` then fails and the second sgen writes `<Name>.Generated.cs` to the root, outside what `Extensions.csproj` compiles. Exit 0. Fix: restore tools first, and create `src\Extensions` before `Push-Location`. This repo already creates the folder first (9a118fe), so it only shows a stray "Run dotnet tool restore" line; reorder here too once upstream takes the fix.
- **Template: `pyproject.toml` declares a console script with no module.** New issue. `<project> = "<package>.cli:main"`, but the template has no `cli.py`; running it fails with `ModuleNotFoundError`. Removed here.
- **LogVideo's CSV columns do not exist on TriggeredSpinnaker's trigger overload.** New issue. `LogVideo` selects `Value.ChunkData.ExposureTime` and `.Gain`, which `Bonsai.Spinnaker`'s frame has but `OpenRigs.Video.VideoChunkData` (FrameID and Timestamp only) does not, so the shared logger cannot record the operator's output. Fix: add `ExposureTime` and `Gain` to `VideoChunkData`, copied in the callback with the other two, or drop them from the selector.
- **FFmpeg writer for LogVideo.** Already tracked in ucl-open/av-dome#25 (live compression, H.264) and ucl-open/support#9 (standard video compression). Add this repo as a second user: Bonsai.Vision's writer crashed 30-minute sessions on the box's N150, FFmpeg on Quick Sync does not.

## Check on the rig

- **Wheel distance.** Turn the wheel exactly 10 turns during a recording: the `Encoder` value in `BehaviorBoard\BehaviorBoard_44_*.bin` (`AnalogData`) should change by 10 x `countsPerRev` (40,960 at 4096), unwrapping the 16-bit counter, which is about 471 cm on the 150 mm wheel. The inline wheel is in Position mode; a wrong sign or scale points at `countsPerRev` or the encoder wiring.
- **Register dump.** Done 29 Oct 2026 on GEEK-BBOX1: `BehaviorBoard\BehaviorBoard_<date>.bin` holds all 106 Read replies, 0.6 s after Start recording and 3 s before the first camera trigger.
- **Run settings.** The run panel was removed (29 Oct 2026); `SubjectId`, `SessionId` and `RunLengthMins` are top-level properties, so recording starts at Start. Check a first session after the regroup end to end. Candidate replacement, the open-rigs way: a launcher that writes the session JSON (`ExperimentSession`), passes it to Bonsai and saves it in the session folder, which `specs/logging.md` section 6 requires and this workflow does not yet do.
- **Stale local layouts.** The regroup moved node indices; a machine whose gitignored `.bonsai\Settings\src\main.layout` predates it fails with "Element #N does not exist in the workflow". Delete that file on every machine that ran the old workflow (GEEK-BBOX1's was re-nested by hand).
- **Start-up order.** Video and CSV are subscribed only once `PathPrefix` exists; check the first session's files have the expected names and the run length's frame count (30 min = 90,000 rows).

## Later

- Switch to released OpenRigs packages once open-rigs publishes one with the camera fixes and the config operators (`patches/README.md`).
- Move `copier.yml` handling to upstream once roadmap#38's fix lands, then `copier update` from `gh:open-rigs/open-rigs`.
- Re-pin `open-rigs` in `pyproject.toml` once `rig-config-resolver` is merged. The current `rev` is a commit on that unmerged branch, which can become unfetchable if the branch is squash-merged and deleted.

## rig-setup

- **Back up `rig.yml` to the share.** Decided 28 Oct 2026: `C:\RigConfigs\<MACHINE>\rig.yml` on the rig is the master and is edited there; rig-setup copies it one way up to `K:\config\<MACHINE>\` with a last-synced time, as it does `Health.json`. The workflow reads only the local file, so a rig runs while the server is down. Not server-to-rig, because `config/` on the share is writable by rigs only (`2750 svc-rig:lab-tonic`), and not a two-way mirror. Copy to a temporary name and rename, and never touch the local file from the sync. Also: set up the clone (`deploy.cmd`) when rig-setup first clones it, and give `rig-behaviour-box` the .NET SDK, which deploy's regeneration needs (Pip's choice over skipping regeneration on rigs, to stay identical to the open-rigs template). The full plan is in Coen-Lab/rig-setup `BACKLOG.md`, "Behaviour box on `ucl-open/coen-behaviour-box`".

## Audit 28 Oct 2026: not changed

Raised by the independent audit and kept as they are; do not raise again without new information.

- Unused template packages in `.bonsai/Bonsai.config` (Sleap, Pylon, TensorFlow and others): harmless, and keeping parity with the template eases `copier update`.
- `swc-aeon` from a git branch in `pyproject.toml`: `uv.lock` pins the commit and deploy installs from the lock.
- Unused PulseController classes and the `version` Literal in the rig schema: both come from the upstream schema and break nothing today.
- Rebuilding the local packages to compare hashes: the committed patches applied to 3788bfb reproduce the built source tree exactly, and nupkg hashes are not deterministic.
- Sending `StopCameras` at startup: the Behavior firmware stops the camera outputs whenever the board goes to Standby, which Bonsai does on disconnect; only a hard crash leaves them running.
- No "run finished" signal and the board log running until Bonsai closes: the README says to close Bonsai when the run ends.
- `main.bonsai` without its generator script: the committed XML is the artefact and is edited from now on.

## Audit 29 Oct 2026 (bonsai.sgen deploy): not changed

Raised by the independent audit of the bonsai.sgen deploy failure and kept as they are; do not raise again without new information.

- Moving `dotnet tool restore` above `regenerate-schemas` here to drop the stray "Run dotnet tool restore" line from every fresh deploy's log: Pip chose template parity; the fix comes with `copier update` once upstream takes it.
- Checking `os.system` in `regenerate.py` again: deploy's own sgen run is checked and stops a real failure (forced with a read-only output file: exit 1, "Generating the C# classes failed").
- Running sgen once instead of twice (regenerate.py's and deploy's give byte-identical output here): template parity; left to the maintainers as a question in the upstream issue.
