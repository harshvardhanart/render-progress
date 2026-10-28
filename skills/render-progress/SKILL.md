---
name: render-progress
description: Show the user a live, modern progress bar (gradient bar, %, frames, fps, elapsed, time left, finish time, CPU/RAM/GPU/VRAM meters, job steps) in a terminal tab whenever a render runs - Remotion, video exports, audio mixes, or any long job that logs "N/M" progress. Use it every time you start a render or the user asks how far a render is, wants to watch progress, or asks for a progress bar.
---

# Render progress bar

Whenever you start a render or another long job that prints `done/total` progress, show the user a live bar instead of tailing the log.

## 1. Make the job write its progress to a log file

Send the render's output to a file and run it in the background, for example:

```bash
npx remotion render Main out/video.mp4 > out/render.log 2>&1
ffmpeg -i in.mov out.mp4 -progress - -nostats 2>&1 | tee out/render.log   # see "ffmpeg" below
```

## 2. Open the bar in a terminal the user can see

Run the script in a terminal tab the user can watch. In the Claude desktop app, use a Terminal-panel tab titled "render progress" and link the tab in your reply. In a plain terminal, tell the user the command to run in a second window.

```powershell
pwsh -File "${CLAUDE_PLUGIN_ROOT}/scripts/render-progress.ps1" -Log out/render.log -Title "My video" -Sub "Final render  GPU  x265" -Steps "Build,*Render,Encode,Deliver"
```

- On Windows PowerShell 5.1 use `powershell -ExecutionPolicy Bypass -File ...`.
- `-Steps` is a comma list. Prefix the running step with `*`: the steps before it show as done, the steps after it as pending.
- `-Pattern` is a regex with two groups (done, total). The default matches `123/4567`, so Remotion ("Rendered 123/4567") works out of the box. For other tools, pass a pattern for a line that has both numbers.
- `-FailOn` is a regex. The bar stops when it appears in the log (e.g. `"RENDER FAILED|Error:"`).
- `-Demo` shows a fake render so the user can try the look.

## 3. Close it when you are done

When the render ends the bar prints "All frames rendered" and exits by itself. Stop or close the tab if you opened it.

## What it shows

- A framed bar (rounded border) that fills with an amber gradient at 1/8-character precision, and the percentage.
- Frames done / total, measured fps (over the last ~20 s), elapsed, time left, and the clock time it will finish.
- CPU and RAM meters (Windows performance counters), plus GPU utilisation, temperature and VRAM (NVIDIA, via `nvidia-smi`). A meter is hidden when its data is not available.
- The job steps row. The layout fits the terminal width: two meter columns when there is room, one when narrow.

## ffmpeg

ffmpeg does not print `done/total`. Either compute frames from `-progress` output with a small wrapper, or pass `-Pattern` for a line your wrapper writes, e.g. `frame=(\d+) of (\d+)`.
