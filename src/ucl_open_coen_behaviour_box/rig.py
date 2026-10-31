from typing import Dict, Literal, Optional
from pydantic import Field

from open_rigs.core.base import BaseSchema
from open_rigs.core.rig import Rig
from open_rigs.devices.behavior_board import BehaviorBoard as _BehaviorBoard
from open_rigs.video import SpinnakerCamera as _SpinnakerCamera

from ucl_open_coen_behaviour_box import __semver__


class LiveView(BaseSchema):
    """How OpenRigs.LiveView's StreamDevices streams this device; each setting left out keeps its default for the device's kind."""

    enabled: bool = Field(default=True, description="False: the device is not streamed at all.")
    rate: Optional[float] = Field(default=None, gt=0, le=1000, description="Messages per second (camera default 5, behavior board 10).")
    width: Optional[int] = Field(default=None, ge=1, le=4096, description="Width of the streamed frames, in pixels; video only (default 320).")
    height: Optional[int] = Field(default=None, ge=1, le=4096, description="Height of the streamed frames, in pixels; video only (default 240).")


# The device entries take a liveView: block for StreamDevices, which reads rig.yml itself. They
# keep open_rigs' names, so the generated C# classes keep theirs.
class BehaviorBoard(_BehaviorBoard):
    __doc__ = _BehaviorBoard.__doc__
    live_view: Optional[LiveView] = Field(default=None, description="Live view settings for this board (OpenRigs.LiveView).")


class SpinnakerCamera(_SpinnakerCamera):
    __doc__ = _SpinnakerCamera.__doc__
    live_view: Optional[LiveView] = Field(default=None, description="Live view settings for this camera (OpenRigs.LiveView).")


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
