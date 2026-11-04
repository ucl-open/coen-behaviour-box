from pathlib import Path

from open_rigs.core import yaml
from open_rigs.devices.behavior_board import CameraTriggerController, RunningWheel

from ucl_open_coen_behaviour_box.rig import (
    BehaviorBoard,
    SpinnakerCamera,
    BehaviourBoxRig
)

TEMPLATE_PATH = Path("config/rig-template.yml")
SCHEMA_PATH = "../src/DataSchemas/ucl_open_coen_behaviour_box.json#/$defs/BehaviourBoxRig"
HEADER = """\
# Rig configuration. On a rig this file is <ConfigRoot>\\<MACHINE-NAME>\\rig.yml, copied from
# config/rig-template.yml by scripts/deploy.ps1: fill in every CHANGE-ME value there, and anything
# else that differs on this rig. Per-rig values are never committed. To change the template
# itself, edit examples/rig.py and run it again rather than editing config/rig-template.yml.
# Each device sits under its kind by name: the workflow drives behaviorBoard: main:
# (BehaviorBoard-Main in the data) and camera: box: (Camera-Box), and stops at startup if either
# is missing. The frame rate is behaviorBoard.main.cameraTriggerController.trigger0Frequency;
# camera.box.triggerFrequency and trigger1Frequency are not used by this rig. usbSerial is the
# board's USB serial, as the rig's hardware scan lists it for portName: the workflow stops at
# Start if the board on portName has another. rigId is the rig's code (B1 GEEK-BBOX1, D1 and D2
# the green domes, O1 and O2 the blue opto rigs, A1 PINK-ACUTE), the end of every session ID.
"""

# Placeholder values only: they must look wrong until a rig fills them in. The trigger rate,
# encoder resolution and wheel size are the box's design values; a rig changes them only if its
# hardware differs.
rig = BehaviourBoxRig(
    rig_id="CHANGE-ME",
    # The folder rig-sync copies to the server and rig-control reads; rig-setup's rig.yml row
    # is wrong for any other (S3-L2, 4 Nov 2026).
    root_path="C:\\Coen-Lab-Local\\Acquired-Data",
    behavior_board={
        "main": BehaviorBoard(
            port_name="COM-CHANGE-ME",
            usb_serial="CHANGE-ME",
            camera_trigger_controller=CameraTriggerController(trigger0_frequency=50, trigger1_frequency=50),
            running_wheel=RunningWheel(counts_per_rev=4096, wheel_diameter_mm=150),
        )
    },
    camera={
        "box": SpinnakerCamera(serial_number="CHANGE-ME", exposure_time=10000, gain=5, binning=1, trigger_frequency=50)
    },
)


def main(path: Path = TEMPLATE_PATH):
    path.parent.mkdir(parents=True, exist_ok=True)
    yaml.save(rig, path, schema_path=SCHEMA_PATH)
    directive, body = path.read_text(encoding="utf-8").split("\n", 1)
    path.write_text(directive + "\n" + HEADER + body, encoding="utf-8")
    print(f"Rig configuration template written to {path}")


if __name__ == "__main__":
    main()
