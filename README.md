# coen-behaviour-box

Acquisition for the Coen Lab behaviour box: a triggered Spinnaker camera recorded with FFmpeg, frame times paired with Harp triggers, and centre-of-mass tracking. The hardware (assembly, parts) lives in [Coen-Lab/hw-behaviour-box](https://github.com/Coen-Lab/hw-behaviour-box).

Generated from the [open-rigs](https://github.com/open-rigs/open-rigs) template (`.copier-answers.yml` records the commit).

## Setup

Needs git, uv and the .NET 8 SDK. From the repository root:

```
scripts\deploy.cmd
```

This creates the Python environment, regenerates the schemas and their C# classes, downloads the Bonsai version pinned in `.bonsai\Bonsai.config` and restores its packages.

## Per-machine settings

Nothing machine-specific is committed. The workflow reads `<ConfigRoot>\<MACHINE-NAME>\rig.yml` at startup (`ConfigRoot` defaults to `C:\RigConfigs`) and refuses to start if it is missing. `deploy.cmd` creates it from `config\rig-template.yml` the first time; fill in that machine's board port, camera serial number, exposure, gain, binning, wheel size, tracking threshold and data path (`rootPath`) there.

## Running a session

Open `src\main.bonsai` in `.bonsai\Bonsai.exe` and press Start. The board connects and the wheel starts counting, but nothing is recorded yet. Double-click the `RunPanel` node to open the panel, type the subject ID and session ID, check the run length (minutes, default 30) and press **Start recording**. The values are read once, at that moment; recording does not start while either ID is empty. The camera then arms, triggers start 5 s later, and after the run length the video and CSV close. Wait for `ffmpeg.exe` to exit before closing Bonsai, or the end of the video is lost. Never save the workflow: per-session values live in the panel and per-rig values in `rig.yml`.

Each session writes to `<rootPath>\sub-<subject>\ses-<session>_date-<date>\`:

- `VideoData_Camera.avi`: H.264 video, one frame per camera trigger.
- `LogData.csv`: one row per video frame with the Harp time (`Seconds`), camera timestamp, `FrameID`, configured exposure, the mouse's centre of mass (`MouseLocation.X`, `MouseLocation.Y`) and the wheel distance in cm.
- `BehaviorBoard\`: every Harp message from the board, one binary file per register (`OpenRigs.Logging:LogHarpDevice`, as av-dome logs its boards). The running wheel's raw encoder counts are in the `AnalogData` register at the board's full rate.

If no frame arrives within 15 s of Start recording, the workflow stops with "The operation has timed out." (usually the trigger cable).

## OpenRigs packages

The `OpenRigs.*` Bonsai packages are built locally into `local_packages\` until open-rigs publishes a release. `patches\README.md` records the base commit, the two camera fixes applied on top, and the package hashes.
