from typing import Dict, Literal
from pydantic import Field

from open_rigs.core.rig import Rig
from open_rigs.devices.behavior_board import BehaviorBoard
from open_rigs.video import SpinnakerCamera

from ucl_open_coen_behaviour_box import __semver__


# Each kind of device is a group of named entries, so rig.yml binds a name to its hardware
# (port, serial number) and the workflow asks for the names it drives: an entry it does not
# ask for is ignored, a name it asks for and does not find stops it at startup. The name in
# the data is the kind and the entry joined by a hyphen: behaviorBoard: main: is
# BehaviorBoard-Main.
class UclOpenCoenBehaviourBoxRig(Rig):
    version: Literal[__semver__] = __semver__
    behavior_board: Dict[str, BehaviorBoard] = Field(
        description="Harp Behavior boards by name. This workflow drives main (BehaviorBoard-Main): serial port, camera trigger on Trigger0 and running wheel on encoder port 2."
    )
    camera: Dict[str, SpinnakerCamera] = Field(
        description="Triggered Spinnaker cameras by name. This workflow drives box (Camera-Box), whose frame rate is the board's trigger0_frequency."
    )
