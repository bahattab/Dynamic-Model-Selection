---
description: Route a task to the right Claude model only when it clearly saves cost (0 - Dynamic Model Selection). "/DMS on" or "/DMS off" toggles automatic routing; "/DMS status" shows the route log.
argument-hint: "[task | on | off | status]"
---
Load and follow the `0-dynamic-model-selection` skill (0 - Dynamic Model Selection).

Arguments: $ARGUMENTS

- No arguments or `status`: report the mode, the routing tools this host has, the current conversation's model, and the route-log summary from `scripts/dms-report.sh` (or `scripts\dms-report.ps1` on Windows) in the skill folder.
- `on` / `off`: confirm the change to automatic routing in one line. The DMS hook stores the setting.
- Anything else: treat it as the task. Apply the clear-win gate; route only if it passes, otherwise answer in place.
