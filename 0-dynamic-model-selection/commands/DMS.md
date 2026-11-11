---
description: Route a task to the right Claude model by complexity (0 - Dynamic Model Selection). Use "/DMS on" or "/DMS off" to toggle automatic routing.
argument-hint: "[task | on | off | status]"
---
Load and follow the `0-dynamic-model-selection` skill (0 - Dynamic Model Selection).

Arguments: $ARGUMENTS

- No arguments or `status`: report the current mode, the routing tools this host has, and the current conversation's model.
- `on` / `off`: confirm the change to automatic routing. The DMS hook stores the setting.
- Anything else: treat it as the task. Classify it with Part A, route it with Part B, and report the route before the result.
