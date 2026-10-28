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

Nothing machine-specific is committed. The workflow reads `<ConfigRoot>\<MACHINE-NAME>\rig.yml` at startup (`ConfigRoot` defaults to `C:\RigConfigs`) and refuses to start if it is missing. `deploy.cmd` creates it from `config\rig-template.yml` the first time; fill in that machine's camera serial number, exposure, gain and data path there.

## OpenRigs packages

The `OpenRigs.*` Bonsai packages are built locally into `local_packages\` until open-rigs publishes a release. `patches\README.md` records the base commit, the two camera fixes applied on top, and the package hashes.
