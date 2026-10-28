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
    tracking_threshold: int = Field(
        default=35,
        ge=0,
        le=255,
        description="Pixels darker than this are treated as the mouse. Depends on the box's lighting: raise it for a lighter image or animal, lower it for a darker one.",
    )
