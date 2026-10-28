# render-progress

A live, modern terminal progress bar for long renders, packaged as a **Claude Code plugin**.
When Claude starts a render (Remotion, a video export, an audio mix, anything that logs `done/total`), it opens this bar in a terminal tab, so you can see how much is done and how much is left at a glance.

```
  ⠼  My Video
     Final render  ●  GPU  ●  x265 / HEVC  ●  1920x1080 @ 30 fps
  ──────────────────────────────────────────────────────────

    █████████████████████████▋░░░░░░░░░░░░░░░░░░░░   55.8%

    Frames    20,718 / 37,106
    Speed        7.5 fps
    Elapsed     36m 13s
    Left        36m 38s   done around 20:36

  ──────────────────────────────────────────────────────────

    CPU   ██████████████  100%              GPU   █████░░░░░░░░░   34%  59°C
    RAM   ██████████████  15.0 / 15.3 GB    VRAM  ████████░░░░░░  2.3 / 4.0 GB

  ──────────────────────────────────────────────────────────

    ✔ Build    ⠼ Render    ● Encode    ● Deliver
```

In a real terminal the bar is an amber-to-red gradient, the meters turn green, amber or red with load, and the spinner animates. It redraws in place twice a second, without flicker.

## Features

- A framed bar (rounded border) that fills with an amber gradient at 1/8-character precision, plus the percentage.
- A responsive layout: everything fits the terminal width, with two meter columns when there is room and one when narrow.
- Frames done / total, the **measured** speed (fps over the last ~20 s), elapsed time, time left, and the clock time it will finish.
- **CPU, RAM, GPU and VRAM meters**, plus the GPU temperature (NVIDIA, via `nvidia-smi`). Meters with no data are hidden.
- A row of job steps (`-Steps "Build,*Render,Encode,Deliver"`).
- It reads any log file, so it never slows down or touches the render itself.

## Install (Claude Code)

```
/plugin marketplace add harshvardhanart/render-progress
/plugin install render-progress@render-progress
```

From then on, Claude shows the bar whenever it renders something. You can also open it yourself with `/render-progress <log file> [title]`, or try it with `/render-progress demo`.

## Use it without Claude

You only need PowerShell: Windows PowerShell 5.1, or PowerShell 7 (`pwsh`) on Windows, macOS or Linux.

```powershell
# try it
pwsh -File scripts/render-progress.ps1 -Demo

# watch a real render
npx remotion render Main out/video.mp4 > render.log 2>&1      # in one terminal
pwsh -File scripts/render-progress.ps1 -Log render.log -Title "My video"   # in another
```

| Option | Meaning |
|---|---|
| `-Log <file>` | The log to watch (required unless `-Demo`). |
| `-Title`, `-Sub` | The heading and the small line under it. |
| `-Steps "A,*B,C"` | The job steps. `*` marks the running step; the steps before it show as done. |
| `-Pattern <regex>` | Two groups (done, total). Default: `(\d+)\s*/\s*(\d+)`, which matches Remotion's `Rendered 123/4567`. |
| `-FailOn <regex>` | Stop with a "Render failed" message when this appears in the log. |
| `-Demo` | A fake render, to see how it looks. |

The CPU and RAM meters use Windows performance counters, and the GPU meters need an NVIDIA GPU. On other systems those meters are simply hidden.

## License

MIT, free to use, change and share. Pull requests are welcome.
