from pathlib import Path
from typing import Union
import json
import pydantic
import subprocess

from open_rigs.core import ExperimentSession
import ucl_open_coen_behaviour_box.rig
import ucl_open_coen_behaviour_box.task

SCHEMA_ROOT = Path("./src/DataSchemas/")
SCHEMA_FILE = SCHEMA_ROOT / "ucl_open_coen_behaviour_box.json"


def main():
    models = [
        ucl_open_coen_behaviour_box.task.UclOpenCoenBehaviourBoxTaskLogic,
        ucl_open_coen_behaviour_box.rig.BehaviourBoxRig,
        ExperimentSession
    ]
    model = pydantic.RootModel[Union[tuple(models)]]
    schema = model.model_json_schema(by_alias=True, mode="serialization", union_format="primitive_type_array")
    SCHEMA_ROOT.mkdir(parents=True, exist_ok=True)
    SCHEMA_FILE.write_text(json.dumps(schema, indent=2))
    print(f"Schema written to {SCHEMA_FILE}")
    # A failed sgen must fail this too: update-workflows would otherwise commit
    # the new schema beside a stale Generated.cs.
    code = subprocess.run(["dotnet", "bonsai.sgen", str(SCHEMA_FILE), "--output", "src/Extensions",
                           "--serializer", "json", "--serializer", "yaml"]).returncode
    if code:
        raise SystemExit(code)


if __name__ == "__main__":
    main()
