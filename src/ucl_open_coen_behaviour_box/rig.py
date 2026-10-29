from typing import Literal
from pydantic import Field

from open_rigs.core.rig import Rig
from open_rigs.devices.behavior_board import BehaviorBoard
from open_rigs.video import SpinnakerCamera

from ucl_open_coen_behaviour_box import __semver__


class UclOpenCoenBehaviourBoxRig(Rig):
    version: Literal[__semver__] = __semver__
    behavior_board: BehaviorBoard = Field(
        description="The Harp Behavior board: serial port, camera trigger on Trigger0 and running wheel on encoder port 2."
    )
    camera: SpinnakerCamera = Field(
        description="The triggered Spinnaker camera. Its frame rate is the board's trigger0_frequency."
    )
