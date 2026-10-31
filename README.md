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

The workflow runs under a session controller (`OpenRigs.Control`, from [ucl-open/coen-openrigs-custom](https://github.com/ucl-open/coen-openrigs-custom), whose README has the protocol; the rig agent and the window that drive it are [Coen-Lab/rig-control](https://github.com/Coen-Lab/rig-control)): it starts into **ready mode** and records nothing until it is told to go. Pressing Start, or `.bonsai\Bonsai.exe src\main.bonsai --no-editor --property:SubjectId=<id> --property:SessionId=<id>`, connects the board, arms the camera, starts the triggers 5 s later and streams the preview (in the editor, the preview window opens on the last node of `Hardware` > `Camera`, so it shows the camera in ready mode); the first frame reports Ready on the control port (TCP 5561, which answers on this machine only). `SubjectId` and `SessionId` are set in the Properties panel (click an empty part of the workspace) or on the command line; `RunLengthMins` (whole minutes, default 30) is a controller parameter, in `Initialization`'s `Parameters`, which the rig agent or `rig-control set` may change until Go. Go comes from the rig agent: the window, or `rig-control go <rig>`. The agent relays to a workflow it launched and also to one started here by hand, which it shows as unmanaged (commands reach it; nothing is recorded in the lab's records). With no agent running on this machine, send the commands straight to the control port: `rig-control go 127.0.0.1 --port 5561`, and `status`, `set` and `stop` the same way. Nothing else starts the session: without Go the workflow stays in ready mode. Go reads the IDs and the run length once; if either ID is empty or the run length is not 1 to 9999, the workflow stops with "Sequence contains no elements." and nothing is recorded. Otherwise the session folder is made (Recording), and after the run length the last video and CSV close (Finished); the agent then stops the workflow, which ends it through `SessionStoppedException` so every file closes, and waits for `ffmpeg.exe` before recording the session. Without the agent, stop it yourself after `ffmpeg.exe` exits, or the end of the video is lost. In the editor, `--start` needs the machine's editor layout, `.bonsai\Settings\src\main.layout`, which `deploy` creates: without it the editor shows "Object reference not set to an instance of an object." and never starts; pressing Start works either way. Never save the workflow: per-session values are set at each run and per-rig values live in `rig.yml`.

The camera's `ExposureTime` (microseconds), `Gain` (dB) and `Binning` are in the same panel, beside those three, to change them without editing `rig.yml` (`--property:ExposureTime=3000` from the command line). Blank, the default, keeps the camera's values in `rig.yml`; change those for a lasting change. A value typed in the panel stays for every later Start until you clear it or close Bonsai without saving. Exposure plus 1,000 us must fit inside the trigger period, so at most 19,000 at 50 Hz: longer, and the camera skips triggers and every frame gets the wrong time, so the workflow stops at Start saying the most that fits (`ExposureFitsTrigger`, whether the value came from the panel or `rig.yml`). The CSV's `ExposureTime` column holds the value in use; `Gain` and `Binning` are recorded nowhere in the session (binning shows in the video's size), so note a run that changed them. The serial number stays in `rig.yml` only: it binds `Camera-Box` to the camera.

Each device's name is typed once in the workflow, as the `Name` of its `RigDevice` node in `RigConfig`. That node publishes the device's `Name` and `Settings` (its `rig.yml` entry) into a subject labelled with the name, and the device's file and log names are mapped from that subject's `Name`, so the entry read and the files written cannot disagree. Each half of the name starts with a capital and holds only letters and digits (`Camera-Box`, never `Camera-box` or `Camera-Box_2`: the logging spec reads a device's name up to the first underscore); `RigDevice` stops the workflow at Start on any other. The subject labels repeat the name, but a misspelt label stops Bonsai's build ("The specified variable ... was not found"), and a label that differs from the name changes nothing in the data. The file and log names' own value is `UNMAPPED`, so a deleted mapping shows in the file names rather than writing `_<DateTime>` files.

A second camera, `Camera-Face` on the board's second trigger, takes these, each by hand: a `face:` entry under `camera:` in every rig's `rig.yml`; in `RigConfig`, another `RigDevice` and `AsyncSubject` named `Camera-Face` off the `Camera` selector; in `Hardware`, a copy of the `Camera` group subscribing to `Camera-Face`, parsing `TimestampedCamera1Frame` and publishing `Camera-Face.Data`, which the live view then streams with nothing more to do; in `Logging`, a copy of `RecordVideo` subscribing to `Camera-Face.Data`, with its three `Camera-Box` subscriptions in `CameraChunk` changed to `Camera-Face` and `Trigger0Frequency` changed to `Trigger1Frequency` in `RunLengthToFrames` and the video's `FrameRate`; and its own `CameraOverrides` and `ExposureFitsTrigger` (`TriggerOutput` 1) in front of its subject, the `CameraOverrides` with an `ExternalizedMapping` of its own whose properties have names of their own (`FaceExposureTime` and so on), carried to the top level beside `ExposureTime`: a second mapping by the same names stops Bonsai's build ("A workflow property with the name ... already exists"), and wiring `Camera-Box`'s mapping to both gives the two cameras the same settings. A copy that misses one of the `Camera-Box` subscriptions records under the wrong name, and nothing catches it. Also open-rigs#4: `CameraTriggerController`'s `StartCameras` does not start the second output and its Camera1 subject parses the Camera0 register, so the second camera gets no triggers until that is fixed.

The workflow's top level follows the open-rigs layout: `RigConfig` (reads `rig.yml` and takes out `BehaviorBoard-Main` and `Camera-Box`), `Initialization` (the run settings), `Hardware` (board and camera, each configured from its entry in `rig.yml`), `Logging` (session folder, video, board log) and `LiveView` (streams every device; below).

Each session writes to `<rootPath>\sub-<subject>\ses-<session>_date-<date>\`, one folder per device named as the device, and each device's files as `<Device>_<DateTime>` in one-hour chunks on the board's Harp clock, as the Open Rigs logging spec (`ucl-open/specs/logging.md`) has it. The workflow sets that clock to the PC's UTC time when the board connects (`Hardware` > `BehaviorBoard` > `Clock`, whole seconds, so up to 1 s behind the PC), and logs nothing from the board until it has. If the board has not confirmed the new time 10 s after Start, the workflow stops with "The board did not confirm within 10 s of Start that its clock was set ..." (its messages are not reaching the PC, or the board is not responding) rather than record a whole session without the board's files; triggers start 5 s after Start, so that session folder holds a few seconds of video and CSV and no board files. So `<DateTime>`, and `Seconds` in the CSV, are UTC: chunks start on the clock hour, not an hour into the run. `<DateTime>` is the chunk's start, so a run crossing the hour has two of each file:

- `Camera-Box\Camera-Box_<DateTime>.avi`: H.264 video of every frame received. A frame the camera drops is missing, not repeated, and the recording stops after the run length's number of received frames (30 min at 50 Hz = 90,000, across the chunks).
- `Camera-Box\Camera-Box_<DateTime>.csv`: one row per video frame, the same columns as av-dome: the Harp time of its trigger (`Seconds`), camera `Timestamp`, `FrameID` and `ExposureTime` (the configured value). A dropped frame shows as a jump in `FrameID` and `Seconds`. Trigger messages lost between the board and the PC do not show in `FrameID`: frames pair with trigger messages in order, so from the first lost one every later row's `Seconds` is late by the number lost (seen once, 30 Oct 2026: 9 lost, every later row 0.18 s late; BACKLOG, "Lost board messages"). The sign is a step in `Seconds` other than the trigger period (20 ms at 50 Hz) where the step in `Timestamp` is one period; `Timestamp` is the camera's own clock, so `Seconds` can be rebuilt from the rows before the first such step.
- `BehaviorBoard-Main\BehaviorBoard-Main_<address>_<DateTime>.bin`: every Harp event and write from the board, one file per register, logged with `OpenRigs.Logging:LogHarpDevice` (the same logger as ucl-open main). The running wheel's raw encoder position is in `BehaviorBoard-Main_44_*` (`AnalogData`, `Encoder`) at the board's full rate, about 1 kHz.
- `BehaviorBoard-Main\BehaviorBoard-Main_<DateTime>.bin`: the board's register dump, requested when logging begins, so its settings for the session are on record. (av-dome's current logger, `UclOpen.Logging` from May 2026, keeps only the first reply of each second: ucl-open/av-dome#33.)

Sessions before 30 Oct 2026 have `Cameras\VideoData_Camera1.avi` and `.csv`, one file per run, and `BehaviorBoard\BehaviorBoard_*`. Before the clock was set (30 Oct 2026), the board counted from power-on, so file names read `1904-01-...` and Harp times are uptime, not UTC.

A camera preview window opens at Start, showing 5 frames a second. It is `Logging` > `RecordVideo` > `SampleInterval`; `scripts\deploy.ps1` gives a machine without an editor layout `config\main.layout`, which opens it. If it is closed or missing, double-click that node while running. A machine that already had a layout keeps it; to get the preview layout, delete `.bonsai\Settings\src\main.layout` and re-run deploy (or copy `config\main.layout` there). Close Bonsai without saving: a save writes the run's values into `main.bonsai`.

If no frame arrives for 15 s, the workflow stops with "No frame from the camera for 15 s ..." (usually the trigger cable).

## Session manifest

Every session folder gets a `manifest.json` (`Logging` > `WriteSessionManifest`, from [Coen-Lab/session-manifest](https://github.com/Coen-Lab/session-manifest); `src\Extensions\SessionManifest.cs` is a copy of that repo's file). It is written when the session folder exists and again when the run ends: the machine and `rig.yml` verbatim, the subject and session from the folder name, this repo's commit and whether the clone was dirty, how the run ended (`completed` when the run length's frames were written, `error` with a Watchdog's message, `stopped` when Bonsai was stopped first) and every file in the folder with its size. Its `status` is `partial`: the overnight copy (rig-setup's `rig-sync.ps1`) checks every listed file is present and closed, adds sizes and hashes, writes `complete`, and only then copies the session to the server, the manifest last. A listed file that is missing stops that session's copy and raises an alarm on the rig's health report. `ingest_script` is `coen-behaviour-box`, the name the server's ingest registry runs for this data. Errors on the board's logging chain do not reach the node, so a session whose board log failed reads `stopped`, not `error`.

## Live view

While it runs, the workflow streams over ZeroMQ for rig-setup's machines window and rig-control's window: data on TCP 5556, video on 5558, bound on every interface (rig-setup's `firewall:live-view` opens both to the local subnet). One node does it, `LiveView`, OpenRigs.LiveView's `StreamDevices` (from [ucl-open/coen-openrigs-custom](https://github.com/ucl-open/coen-openrigs-custom)), last in the workflow: it reads this machine's `rig.yml` when the workflow is built and streams each device there whose data the workflow publishes as `<Kind>-<Instance>.Data`, so the board's events are `BehaviorBoard-Main.Data` and the camera's frames `Camera-Box.Data`, and a device added under that convention is streamed without touching `LiveView`. Each message is a topic `<MACHINE-NAME>/<stream>/`, a JSON header (`rigId`, `sessionKey`, `stream`, `index`, `enc`, `type`) and the payload. The session key is `ready` until the session folder exists, then the folder's own name, `sub-<subject>/ses-<session>_date-<start>`. Streams:

- `Camera-Box.video`: the camera's frames from Start (in ready mode too), 5 a second, 320 x 240 JPEG.
- `BehaviorBoard-Main.encoder`: the raw encoder count (`AnalogData.Encoder`, 16-bit, wrapping), 10 times a second.
- `elapsed`: seconds since the session folder appeared, once a second.
- `liveview`: every 5 s, this workflow (its path, commit and whether the clone was dirty, as `manifest.json` records them) and the devices streamed and skipped, and why.

A device's rate, and a camera's frame size, can be changed in `rig.yml` under the device's `liveView:` (`rate`, `width`, `height`, or `enabled: false`); the template has `liveView: null`, the defaults. `LiveView` has its own `ConfigRoot`, the same folder as the workflow's: Bonsai cannot pass a workflow property into it, so a rig with another `ConfigRoot` changes both, and `--property:ConfigRoot` reaches `RigConfig` only.

Viewing never reaches the recording: a subscriber that is slow or joins late loses its own messages (the header's `index` shows the gap), and with none connected the messages are dropped. Another workflow already streaming on these ports stops this one at Start (`AddressAlreadyInUseException`); Stop and Start again in the same window is fine (tested with Start 0.7 s after Stop): the new run's messages carry its own session key, and each stream's `index` starts again at 0. To watch from another machine without the window, `uv run --no-project --with pyzmq python scripts\receive-stream.py 30 <rig>` prints what arrived in 30 s per stream.

## Checking a change without the rig

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check-workflow.ps1
```

On a deployed clone, with no Bonsai window and no hardware, in four steps: compiles `src\Extensions` as C# 5 (Bonsai compiles it with the .NET Framework's compiler, so `$"..."` and other C# 6 features fail there; `Extensions.csproj` sets `LangVersion` 5 for the same reason), builds `src\main.bonsai` with Bonsai's own builders (every type, selector, include, subject and mapping), runs `RigDevice` on `config\rig-template.yml`, both for the names the workflow asks for and for names it must refuse, and checks the other extensions and timings: `ExposureFitsTrigger`'s limit, `SessionKey` on a session folder's path, `Watchdog`'s own message, `CameraOverrides`' refusal, and that every timeout in `main.bonsai` is a `Watchdog` with a message of its own. Exit 0 when all four steps pass. It cannot check the camera, the board or the hour hand-over: those need the rig (`BACKLOG.md`, "Check on the rig").

## OpenRigs packages

The `OpenRigs.*` Bonsai packages are built locally into `local_packages\` until open-rigs publishes a release. `patches\README.md` records the base commit, the two camera fixes applied on top, and the package hashes.
