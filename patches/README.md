# Locally built OpenRigs packages

`local_packages/` holds `OpenRigs.Core`, `OpenRigs.Devices`, `OpenRigs.Logging` and `OpenRigs.Video` at version `0.1.0-bbox.1`, built here because open-rigs has not published a release yet (ucl-open/ucl-open#12). The version is distinct from any upstream one, so a later restore never confuses the two.

Base: `open-rigs/open-rigs` branch `rig-config-resolver` at `3788bfbb0946bd5a8e5ade321da9815cc1ff1c07` (main plus the per-machine config operators `ResolveRigConfigDirectory`, `ReadRigConfig` and `ResolveRigFile`).

Patches applied on top, both reported upstream:

| Patch | Fixes | Upstream |
|---|---|---|
| `open-rigs-66-full-frame.patch` | `TriggeredSpinnaker` records a cropped frame when the camera's stored region is smaller than the sensor: the region is reset to full frame after binning | ucl-open/ucl-open#66 |
| `open-rigs-67-copy-chunkdata.patch` | Bonsai crashes when a frame waits in the Zip, because `ChunkData` is read after Spinnaker releases the image: the five chunk fields are copied inside the camera callback. This changes only the `OpenRigs.Devices` `TriggeredSpinnaker` include, which this workflow does not use; the `OpenRigs.Video.TriggeredSpinnaker` operator it uses already copies `FrameID` and `Timestamp` before the Zip | ucl-open/ucl-open#67 |

Build:

```powershell
git clone https://github.com/open-rigs/open-rigs; cd open-rigs
git checkout 3788bfbb0946bd5a8e5ade321da9815cc1ff1c07
git apply <this repo>/patches/open-rigs-66-full-frame.patch <this repo>/patches/open-rigs-67-copy-chunkdata.patch
foreach ($p in 'Core','Devices','Logging','Video') {
    dotnet pack "src/OpenRigs.$p/OpenRigs.$p.csproj" -c Release -p:Version=0.1.0-bbox.1 -o <this repo>/local_packages
}
```

SHA-256 of the packages as committed (built with .NET SDK 8.0.424 on 28 Oct 2026):

```
8d08926fadd8bcff1c9450c663ec81a8f11b644bcdbbb7204fdef9d729666ef9  OpenRigs.Core.0.1.0-bbox.1.nupkg
82ae3d13854ff68010ba59c81d65f6d9be7d0039fc39a2912f3c8ca567c9cbca  OpenRigs.Devices.0.1.0-bbox.1.nupkg
890852b421dad5438ec67082e61f51785090a7c0e1ec829309c918b11ca18a20  OpenRigs.Logging.0.1.0-bbox.1.nupkg
26b0e832a0b4bd83adf8533cf62c12f6995b9b8a6761c604cd62b6522661fe2a  OpenRigs.Video.0.1.0-bbox.1.nupkg
```

## Bonsai.FFmpeg 0.2.0-uniquepipe

`local_packages/Bonsai.FFmpeg.0.2.0-uniquepipe.nupkg` is copied unchanged from Coen-Lab/hw-behaviour-box, where it was built: [bonsai-rx/ffmpeg](https://github.com/bonsai-rx/ffmpeg) tag `v0.2.0` (`ee403aeca3d6ecb214487a5c41d94b2f2b541526`) plus `bonsai-ffmpeg-unique-pipe.patch`, which names each recording's pipe after the file stem plus a GUID, so a Start while the previous recording's ffmpeg is still draining no longer fails with "All pipe instances are busy." DLL SHA-256 `ecb50c0d0618e5e31969d9c7a45a1b82a7f362db97a5cc831e884087433a5403`; package SHA-256 `43e124e7608ff0ec32ced7edf5b5fd2ff34c4072d027ccd75c1d76fa1e950d00`. Licence in `THIRD-PARTY-NOTICES.md`.

FFmpeg replaces Bonsai.Vision's `VideoWriter` (what `OpenRigs.Logging:LogVideo` uses) because that writer encodes FMP4 on one thread inside Bonsai: on the box's Intel N150 at 1440 x 1080, 50 Hz it fell behind whenever the CPU was busy, queued about 1 GB of frames a minute in RAM, and crashed a 30-minute session at about 23 minutes (hw-behaviour-box 25a0bcd). FFmpeg encodes H.264 on Intel Quick Sync with flat memory.

## Switching to upstream

When open-rigs publishes a release containing both fixes and the config operators, set `rigs_version` in `.bonsai/Bonsai.config` to it, delete `local_packages/` and this folder, and remove the `local packages` source from `.bonsai/NuGet.config`.
