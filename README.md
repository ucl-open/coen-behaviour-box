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

Nothing machine-specific is committed. The workflow reads `<ConfigRoot>\<MACHINE-NAME>\rig.yml` at startup (`ConfigRoot` defaults to `C:\RigConfigs`) and refuses to start if it is missing. `deploy.cmd` creates it from `config\rig-template.yml` the first time; fill in that machine's board port, camera serial number, exposure, gain, binning, wheel size and data path (`rootPath`) there.

## Running a session

Open `src\main.bonsai` in `.bonsai\Bonsai.exe` and press Start. The board connects and the wheel starts counting, but nothing is recorded yet. Double-click the `RunPanel` node to open the panel, type the subject ID and session ID, check the run length (whole minutes, default 30) and press **Start recording**. The values are read once, at that moment; recording does not start while either ID is empty or the run length is not a whole number of minutes from 1 to 9999. The camera then arms, triggers start 5 s later, and after the run length the video and CSV close. Wait for `ffmpeg.exe` to exit before closing Bonsai, or the end of the video is lost. Never save the workflow: per-session values live in the panel and per-rig values in `rig.yml`.

Each session writes to `<rootPath>\sub-<subject>\ses-<session>_date-<date>\`:

- `Cameras\VideoData_Camera1.avi`: H.264 video of every frame received. A frame the camera drops is missing, not repeated, and the recording stops after the run length's number of received frames (30 min at 50 Hz = 90,000).
- `Cameras\VideoData_Camera1.csv`: one row per video frame, the same columns as av-dome: the Harp time of its trigger (`Seconds`), camera `Timestamp`, `FrameID` and `ExposureTime` (the configured value). A dropped frame shows as a jump in `FrameID` and `Seconds`.
- `BehaviorBoard\BehaviorBoard_<address>_<date>.bin`: every Harp event and write from the board, one file per register, logged with `OpenRigs.Logging:LogHarpDevice` (the same logger as ucl-open main). `<date>` is the Harp clock's, not wall time. The running wheel's raw encoder position is in `BehaviorBoard_44_*` (`AnalogData`, `Encoder`) at the board's full rate, about 1 kHz.
- `BehaviorBoard\BehaviorBoard_<date>.bin`: the board's register dump, requested when logging begins, so its settings for the session are on record. (av-dome's current logger, `UclOpen.Logging` from May 2026, keeps only the first reply of each second: ucl-open/av-dome#33.)

If no frame arrives within 15 s of Start recording, the workflow stops with "The operation has timed out." (usually the trigger cable).

## OpenRigs packages

The `OpenRigs.*` Bonsai packages are built locally into `local_packages\` until open-rigs publishes a release. `patches\README.md` records the base commit, the two camera fixes applied on top, and the package hashes.
