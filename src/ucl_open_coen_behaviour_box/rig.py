from typing import Literal, Dict
from pydantic import Field

from open_rigs.core.rig import Rig

from ucl_open_coen_behaviour_box import __semver__


class UclOpenCoenBehaviourBoxRig(Rig):
    version: Literal[__semver__] = __semver__
    ...