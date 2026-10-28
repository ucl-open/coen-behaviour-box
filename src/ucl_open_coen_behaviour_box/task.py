# Import core types
from typing import Literal
from pydantic import Field

from swc.aeon.io import reader
from swc.aeon.schema import BaseSchema, data_reader

from ucl_open_coen_behaviour_box import __semver__

# TODO - should inherit from some TaskParameters base class rather than BaseSchema
class UclOpenCoenBehaviourBoxTaskParameters(BaseSchema):
    ...


class UclOpenCoenBehaviourBoxTaskLogic(BaseSchema):
    version: Literal[__semver__] = __semver__
    name: Literal["UclOpenCoenBehaviourBox"] = Field(default="UclOpenCoenBehaviourBox", description="Name of the task logic", frozen=True)
    task_parameters: UclOpenCoenBehaviourBoxTaskParameters = Field(description="Parameters of the task logic")
    ...