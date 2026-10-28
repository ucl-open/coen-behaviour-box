# Backlog

## Raise upstream (open-rigs/open-rigs)

Found while building this workflow on 28 Oct 2026. Open each with the line `*Comment/research by Claude, read/edited by Pip.*` and a fix diff where it is short.

- **CameraTriggerController counts the register-dump reply as a trigger.** Comment on open-rigs#4, which already covers the Camera1 subject parsing the Camera0 register and StartCameras not starting output 1. Both trigger subjects parse every `BehaviorEvents` message, so with `DumpRegisters` on, the Read reply of `Camera0Frame` becomes one extra trigger at startup and the first CSV row comes out early (measured on the box before hw-behaviour-box added the filter). Fix: `FilterMessageType` (Include, Event) before each `Parse`. This repo filters locally in the `Camera` group.
- **RunningWheel takes a Difference in Displacement mode.** New issue. The include sets `EncoderMode` to `Displacement` (change since the last reading, by the Harp Behavior spec) and still runs `Difference`, `ConvertSigned` and `Accumulate`, which suits `Position` (a running count). Both hw-behaviour-box and av-dome's `ActiveExperiments` branch replaced the include with an inline copy set to `Position`. Fix: `Position` with the chain as is, or `Displacement` without the `Difference`. Confirm with the wheel check below first. Not the same as ucl-open/acquisition#9 (encoder reset racing the subscription).
- **LogVideo's CSV columns do not exist on TriggeredSpinnaker's trigger overload.** New issue. `LogVideo` selects `Value.ChunkData.ExposureTime` and `.Gain`, which `Bonsai.Spinnaker`'s frame has but `OpenRigs.Video.VideoChunkData` (FrameID and Timestamp only) does not, so the shared logger cannot record the operator's output. Fix: add `ExposureTime` and `Gain` to `VideoChunkData`, copied in the callback with the other two, or drop them from the selector.
- **FFmpeg writer for LogVideo.** Already tracked in ucl-open/av-dome#25 (live compression, H.264) and ucl-open/support#9 (standard video compression). Add this repo as a second user: Bonsai.Vision's writer crashed 30-minute sessions on the box's N150, FFmpeg on Quick Sync does not.

## Check on the rig

- **Wheel distance.** Turn the wheel exactly 10 turns during a recording: `WheelDistance` in `LogData.csv` should rise by about 471 cm (150 mm wheel). If it does not, the include's Displacement mode is the cause; patch it to `Position` in the local `OpenRigs.Devices` (0.1.0-bbox.2, recorded in `patches/`).
- **Run panel.** It opens by double-clicking `RunPanel`, because the template ignores `*.layout`. Decide after the first runs whether to track a layout so it opens on Start.
- **Start-up order.** Video and CSV are subscribed only once `PathPrefix` exists; check the first session's files have the expected names and the run length's frame count (30 min = 90,000 rows).

## Later

- Switch to released OpenRigs packages once open-rigs publishes one with the camera fixes and the config operators (`patches/README.md`).
- Move `copier.yml` handling to upstream once roadmap#38's fix lands, then `copier update` from `gh:open-rigs/open-rigs`.
