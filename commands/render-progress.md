---
description: Open the live render progress bar for a render log (or -Demo to try it)
argument-hint: "<log file> [title]  |  demo"
---

Open the live render progress bar in a terminal the user can see, following the `render-progress` skill.

Arguments: $ARGUMENTS

- If the arguments are `demo` (or empty and no render is running), run the script with `-Demo`.
- Otherwise the first argument is the render log, and anything after it is the title. If no log is given, find the log of the render you started in this session.
- Script: `${CLAUDE_PLUGIN_ROOT}/scripts/render-progress.ps1` (use `pwsh -File`; on Windows PowerShell 5.1 use `powershell -ExecutionPolicy Bypass -File`).
