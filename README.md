# coen-behaviour-box

Acquisition for the Coen Lab behaviour box: a triggered Spinnaker camera recorded with FFmpeg, frame times paired with Harp triggers, and the Harp board logged raw. Session files follow av-dome's (`ActiveExperiments`) layout. The hardware (assembly, parts) lives in [Coen-Lab/hw-behaviour-box](https://github.com/Coen-Lab/hw-behaviour-box).

Generated from the [open-rigs](https://github.com/open-rigs/open-rigs) template (`.copier-answers.yml` records the commit).

## Setup

Needs git, uv and the .NET 8 SDK. From the repository root:

```
scripts\deploy.cmd
```

This creates the Python environment, regenerates the schemas and their C# classes, downloads the Bonsai version pinned in `.bonsai\Bonsai.config` and restores its packages.

## Per-machine settings

Nothing machine-specific is committed. The workflow reads `<ConfigRoot>\<MACHINE-NAME>\rig.yml` at startup (`ConfigRoot` defaults to `C:\Coen-Lab-Local\RigConfigs`, with the lab's other local files; rig-setup moves an older `C:\RigConfigs` there and leaves a link at the old place) and refuses to start if it is missing. `deploy.cmd` creates it from `config\rig-template.yml` the first time; fill in that machine's board port, camera serial number, exposure, gain, binning, wheel size and data path (`rootPath`) there.

`rig.yml` is the source of truth for the hardware: each kind of device is a group of named entries, and each entry binds that name to its port or serial number. The workflow asks for the names it drives, and the name in the data is the kind and the entry joined by a hyphen:

```yaml
behaviorBoard:
  main:              # BehaviorBoard-Main
    portName: COM3
    ...
camera:
  box:               # Camera-Box
    serialNumber: '23201539'
    ...
```

The board is found by its port and the camera by its serial number, never by the name. An entry the workflow does not ask for (a `spare:` board, say) is ignored. A name it asks for and does not find stops it at Start with the entries the file has: "rig.yml has no camera named 'box', which this workflow records as Camera-Box. Its camera entries: face. ..." (`RigDevice`, in `src\Extensions\RigDevice.cs`). A file still in the layout from before 30 Oct 2026, with the settings straight under `behaviorBoard:`, stops it at Start with "Property 'trigger0Frequency' not found on type 'UclOpenCoenBehaviourBox.BehaviorBoard'": add the `main:` and `box:` levels.

## Running a session

Open `src\main.bonsai` in `.bonsai\Bonsai.exe`, click an empty part of the workspace, and in the Properties panel set `SubjectId`, `SessionId` and `RunLengthMins` (whole minutes, default 30). Or set them from the command line: `.bonsai\Bonsai.exe src\main.bonsai --start --property:SubjectId=<id> --property:SessionId=<id> --property:RunLengthMins=30`. Press Start: the values are read once; if either ID is empty or the run length is not 1 to 9999, the workflow stops at once with "Sequence contains no elements." and nothing is recorded. Otherwise the board connects, the camera arms, triggers start 5 s later, and after the run length the last video and CSV close. Wait for `ffmpeg.exe` to exit before closing Bonsai, or the end of the video is lost. Never save the workflow: per-session values are set at each run and per-rig values live in `rig.yml`.

Each device's name is typed once in the workflow, as the `Name` of its `RigDevice` node in `RigConfig`. That node publishes the device's `Name` and `Settings` (its `rig.yml` entry) into a subject labelled with the name, and the device's file and log names are mapped from that subject's `Name`, so the entry read and the files written cannot disagree. Each half of the name starts with a capital and holds only letters and digits (`Camera-Box`, never `Camera-box` or `Camera-Box_2`: the logging spec reads a device's name up to the first underscore); `RigDevice` stops the workflow at Start on any other. The subject labels repeat the name, but a misspelt label stops Bonsai's build ("The specified variable ... was not found"), and a label that differs from the name changes nothing in the data. The file and log names' own value is `UNMAPPED`, so a deleted mapping shows in the file names rather than writing `_<DateTime>` files.

A second camera, `Camera-Face` on the board's second trigger, takes these, each by hand: a `face:` entry under `camera:` in every rig's `rig.yml`; in `RigConfig`, another `RigDevice` and `AsyncSubject` named `Camera-Face` off the `Camera` selector; in `Hardware`, a copy of the `Camera` group subscribing to `Camera-Face`, parsing `TimestampedCamera1Frame` and publishing `FrameEvents-Face`; in `Logging`, a copy of `RecordVideo` subscribing to `FrameEvents-Face`, with its three `Camera-Box` subscriptions in `CameraChunk` changed to `Camera-Face` and `Trigger0Frequency` changed to `Trigger1Frequency` in `RunLengthToFrames` and the video's `FrameRate`. A copy that misses one of the `Camera-Box` subscriptions records under the wrong name, and nothing catches it. Also open-rigs#4: `CameraTriggerController`'s `StartCameras` does not start the second output and its Camera1 subject parses the Camera0 register, so the second camera gets no triggers until that is fixed.

The workflow's top level follows the open-rigs layout: `RigConfig` (reads `rig.yml` and takes out `BehaviorBoard-Main` and `Camera-Box`), `Initialization` (the run settings), `Hardware` (board and camera, each configured from its entry in `rig.yml`) and `Logging` (session folder, video, board log).

Each session writes to `<rootPath>\sub-<subject>\ses-<session>_date-<date>\`, one folder per device named as the device, and each device's files as `<Device>_<DateTime>` in one-hour chunks on the board's Harp clock, as the Open Rigs logging spec (`ucl-open/specs/logging.md`) has it. `<DateTime>` is the chunk's start, so a run crossing the hour has two of each file:

- `Camera-Box\Camera-Box_<DateTime>.avi`: H.264 video of every frame received. A frame the camera drops is missing, not repeated, and the recording stops after the run length's number of received frames (30 min at 50 Hz = 90,000, across the chunks).
- `Camera-Box\Camera-Box_<DateTime>.csv`: one row per video frame, the same columns as av-dome: the Harp time of its trigger (`Seconds`), camera `Timestamp`, `FrameID` and `ExposureTime` (the configured value). A dropped frame shows as a jump in `FrameID` and `Seconds`.
- `BehaviorBoard-Main\BehaviorBoard-Main_<address>_<DateTime>.bin`: every Harp event and write from the board, one file per register, logged with `OpenRigs.Logging:LogHarpDevice` (the same logger as ucl-open main). `<DateTime>` is the Harp clock's, not wall time. The running wheel's raw encoder position is in `BehaviorBoard-Main_44_*` (`AnalogData`, `Encoder`) at the board's full rate, about 1 kHz.
- `BehaviorBoard-Main\BehaviorBoard-Main_<DateTime>.bin`: the board's register dump, requested when logging begins, so its settings for the session are on record. (av-dome's current logger, `UclOpen.Logging` from May 2026, keeps only the first reply of each second: ucl-open/av-dome#33.)

Sessions before 30 Oct 2026 have `Cameras\VideoData_Camera1.avi` and `.csv`, one file per run, and `BehaviorBoard\BehaviorBoard_*`.

If no frame arrives within 15 s of Start, the workflow stops with "The operation has timed out." (usually the trigger cable).

## Checking a change without the rig

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check-workflow.ps1
```

On a deployed clone, with no Bonsai window and no hardware: compiles `src\Extensions` as C# 5 (Bonsai compiles it with the .NET Framework's compiler, so `$"..."` and other C# 6 features fail there; `Extensions.csproj` sets `LangVersion` 5 for the same reason), builds `src\main.bonsai` with Bonsai's own builders (every type, selector, include, subject and mapping), and runs `RigDevice` on `config\rig-template.yml`, both for the names the workflow asks for and for names it must refuse. Exit 0 when all pass. It cannot check the camera, the board or the hour hand-over: those need the rig (`BACKLOG.md`, "Check on the rig").

## OpenRigs packages

The `OpenRigs.*` Bonsai packages are built locally into `local_packages\` until open-rigs publishes a release. `patches\README.md` records the base commit, the two camera fixes applied on top, and the package hashes.
