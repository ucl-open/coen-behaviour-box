# The behaviour box's rig schema is the lab's, in lib-open-rigs (open_rigs.rigs.behaviour_box),
# not this workflow's: every workflow on a behaviour box reads the same rig.yml, so they all take
# it from there. A setting of this experiment alone belongs in task.py.
from open_rigs.rigs.behaviour_box import BehaviorBoard, BehaviourBoxRig, LiveView, SpinnakerCamera

__all__ = ["BehaviorBoard", "BehaviourBoxRig", "LiveView", "SpinnakerCamera"]
