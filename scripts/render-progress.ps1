# render-progress: a live, modern terminal progress bar for long renders (Remotion, or anything that logs "N/M").
# Reads the render log twice a second and shows a framed bar, %, frames, real fps, elapsed, time left,
# finish clock, CPU / RAM / GPU / VRAM meters (GPU via nvidia-smi) and a row of job steps.
# The layout follows the terminal width: two meter columns when there is room, one when narrow.
#
# Usage:
#   pwsh -File render-progress.ps1 -Log render.log [-Title "My video"] [-Sub "Final render"] [-Steps "Build,*Render,Encode,Deliver"]
#   pwsh -File render-progress.ps1 -Demo        # fake render, to try it out
#
# -Pattern   regex with two groups (done, total); default matches "123/4567" (Remotion prints "Rendered 123/4567").
# -Steps     comma list; prefix the running step with *, steps before it show as done.
# -FailOn    regex that stops the bar when it appears in the log.
# MIT License. https://github.com/harshvardhanart/render-progress
param(
    [string]$Log = '',
    [string]$Title = 'Render',
    [string]$Sub = '',
    [string]$Pattern = '(\d+)\s*/\s*(\d+)',
    [string]$Steps = 'Prepare,*Rendering,Encode,Done',
    [string]$FailOn = '',
    [switch]$Demo
)
if ($Demo) {
    $Log = Join-Path ([System.IO.Path]::GetTempPath()) 'render-progress-demo.log'
    Set-Content $Log 'Rendered 0/9000'
    if ($Title -eq 'Render') { $Title = 'Demo render' }
    $demoStart = Get-Date
}
if ($Log -eq '') { Write-Host 'render-progress: pass -Log <file> (or -Demo to try it).'; exit 1 }
$log = $Log
$dotC = [char]0x25CF
if ($Sub -eq '') { $Sub = 'Live render  ' + $dotC + '  ' + (Split-Path $log -Leaf) }
while (-not (Test-Path $log)) { Start-Sleep -Milliseconds 500 }

$e = [char]27
$full = [string][char]0x2588
$part = @('', [char]0x258F, [char]0x258E, [char]0x258D, [char]0x258C, [char]0x258B, [char]0x258A, [char]0x2589)
$spin = @([char]0x280B, [char]0x2819, [char]0x2839, [char]0x2838, [char]0x283C, [char]0x2834, [char]0x2826, [char]0x2827, [char]0x2807, [char]0x280F)
$check = [char]0x2714; $hl = [string][char]0x2500
$tl = [char]0x256D; $tr = [char]0x256E; $bl = [char]0x2570; $br = [char]0x256F; $vl = [char]0x2502
$start = (Get-Item $log).CreationTime
if ($Demo) { $start = $demoStart }
$hist = New-Object System.Collections.Queue
$tick = 0; $lastW = 0

function Rgb($r, $g, $b) { "$e[38;2;${r};${g};${b}m" }
$rst = "$e[0m"; $dim = Rgb 120 120 130; $wht = Rgb 240 240 245; $amb = Rgb 255 176 0; $grn = Rgb 80 220 140; $red = Rgb 255 90 70; $frm = Rgb 90 90 100
function Fmt([TimeSpan]$t) { if ($t.TotalHours -ge 1) { '{0}h {1:D2}m {2:D2}s' -f [int][math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds } else { '{0}m {1:D2}s' -f $t.Minutes, $t.Seconds } }
function Pad([string]$s, [int]$n) { if ($s.Length -ge $n) { $s.Substring(0, $n) } else { $s + (' ' * ($n - $s.Length)) } }
# amber -> orange -> red gradient across the bar
function Grad($i, $n) { $t = $i / [math]::Max(1, $n - 1); Rgb 255 ([int](196 - 120 * $t)) ([int](40 - 20 * $t)) }
function LoadColor($v) { if ($v -ge 90) { $red } elseif ($v -ge 60) { $amb } else { $grn } }

# one meter cell, fixed visible width: label(6) + bar(m) + gap(2) + value(vw)
function Cell([string]$label, $pct, [string]$value, [int]$m, [int]$vw) {
    $v = [math]::Max(0, [math]::Min(100, $pct)); $n = [int][math]::Round($v / 100 * $m)
    "$dim$(Pad $label 6)$rst" + (LoadColor $v) + ($full * $n) + $frm + ([string][char]0x2591 * ($m - $n)) + $rst + "  $wht$(Pad $value $vw)$rst"
}
# strip the trailing padding of the last cell on a line, so a narrow terminal never wraps it
function Tail([string]$s) { $s -replace ' +(\x1b\[0m)$', '$1' }

# system meters: CPU and RAM via Windows perf counters, GPU via nvidia-smi (refreshed every other tick); missing ones are skipped
$cpuC = $null; try { $cpuC = New-Object System.Diagnostics.PerformanceCounter('Processor Information', '% Processor Utility', '_Total'); [void]$cpuC.NextValue() } catch {}
$memC = $null; try { $memC = New-Object System.Diagnostics.PerformanceCounter('Memory', 'Available MBytes') } catch {}
$ramTot = 0; try { $ramTot = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB } catch {}
$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
$cpu = $null; $ramUsed = $null; $gpu = $null

Write-Host "$e[?25l" -NoNewline  # hide cursor
Clear-Host
try {
    while ($true) {
        if ($Demo) { Set-Content $log ('Rendered {0}/9000' -f [math]::Min(9000, [int]((((Get-Date) - $demoStart).TotalSeconds) * 150 + 300 * [math]::Sin(((Get-Date) - $demoStart).TotalSeconds / 3)))) }
        $m = Get-Content $log -Tail 3 -ErrorAction SilentlyContinue | Select-String $Pattern | Select-Object -Last 1
        if ($m) {
            $done = [int]$m.Matches[0].Groups[1].Value
            $total = [math]::Max(1, [int]$m.Matches[0].Groups[2].Value)
            $pct = [math]::Min(1.0, [double]$done / $total)
            $now = Get-Date
            $hist.Enqueue(@($now, $done)); while ($hist.Count -gt 40) { [void]$hist.Dequeue() }
            $first = $hist.Peek()
            $dt = ($now - $first[0]).TotalSeconds
            $fps = if ($dt -gt 2) { ($done - $first[1]) / $dt } else { 0 }
            $left = if ($fps -gt 0) { [TimeSpan]::FromSeconds(($total - $done) / $fps) } else { $null }
            $elapsed = $now - $start
            $sp = $spin[$tick % $spin.Count]; $tick++

            if ($tick % 2 -eq 1) {
                if ($cpuC) { try { $cpu = [math]::Min(100, $cpuC.NextValue()) } catch {} }
                if ($memC -and $ramTot) { try { $ramUsed = $ramTot - $memC.NextValue() / 1024 } catch {} }
                if ($smi) { try { $q = (& nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits | Select-Object -First 1) -split ',\s*'; $gpu = @([int]$q[0], [int]$q[1], [int]$q[2], [int]$q[3]) } catch {} }
            }

            # ---- responsive layout: everything is sized from the terminal width ----
            $tw = 80; try { $tw = $Host.UI.RawUI.WindowSize.Width } catch {}
            if ($tw -ne $lastW) { Clear-Host; $lastW = $tw }
            $W = [math]::Max(30, [math]::Min(96, $tw - 3))        # content width: 2-space margin, never wider than the terminal
            $ind = '  '

            # framed bar: rounded border, the inside fills with the percentage, the empty part stays blank
            $pctTxt = '{0,6:P1}' -f $pct
            $inner = $W - 2 - 2 - $pctTxt.Length                   # border chars + gap before the %
            $cells = $pct * $inner
            $whole = [int][math]::Floor($cells); $frac = [int](($cells - $whole) * 8)
            $fill = ''
            for ($i = 0; $i -lt $whole; $i++) { $fill += (Grad $i $inner) + $full }
            $used = $whole
            if ($whole -lt $inner -and $frac -gt 0) { $fill += (Grad $whole $inner) + $part[$frac]; $used++ }
            $fill += ' ' * ($inner - $used)
            $top = "$ind$frm$tl" + ($hl * $inner) + "$tr$rst"
            $mid = "$ind$frm$vl$rst$fill$frm$vl$rst  $amb$pctTxt$rst"
            $bot = "$ind$frm$bl" + ($hl * $inner) + "$br$rst"

            # stats: label column + value column, left-aligned
            $eta = if ($left) { Fmt $left } else { '...' }
            $at = if ($left) { ($now + $left).ToString('HH\:mm') } else { '--:--' }
            $stats = @(
                "$ind  $dim$(Pad 'Frames' 10)$rst$wht$('{0:N0}' -f $done)$rst$dim / $('{0:N0}' -f $total)$rst"
                "$ind  $dim$(Pad 'Speed' 10)$rst$wht$('{0:N1}' -f $fps)$rst$dim fps$rst"
                "$ind  $dim$(Pad 'Elapsed' 10)$rst$wht$(Fmt $elapsed)$rst"
                "$ind  $dim$(Pad 'Left' 10)$rst$amb$eta$rst$dim   done around $rst$wht$at$rst"
            )

            # meters: a fixed grid; two columns when they fit, one column when narrow
            $vw = 15
            $two = $W -ge (2 + 2 * (6 + 10 + 2 + $vw) + 4)
            $mw = if ($two) { [int][math]::Floor(($W - 2 - 4 - 2 * (6 + 2 + $vw)) / 2) } else { [math]::Max(4, $W - 2 - (6 + 2 + $vw)) }
            $mw = [math]::Min($mw, 24)
            $ramPct = if ($ramTot -and $null -ne $ramUsed) { $ramUsed / $ramTot * 100 } else { $null }
            $cCpu = if ($null -ne $cpu) { Cell 'CPU' $cpu ('{0:N0}%' -f $cpu) $mw $vw } else { $null }
            $cRam = if ($null -ne $ramPct) { Cell 'RAM' $ramPct ('{0:N1} / {1:N1} GB' -f $ramUsed, $ramTot) $mw $vw } else { $null }
            $cGpu = if ($gpu) { Cell 'GPU' $gpu[0] ('{0}%  {1}{2}C' -f $gpu[0], $gpu[3], [char]0x00B0) $mw $vw } else { $null }
            $cVrm = if ($gpu) { Cell 'VRAM' ($gpu[1] / [math]::Max(1, $gpu[2]) * 100) ('{0:N1} / {1:N1} GB' -f ($gpu[1] / 1024), ($gpu[2] / 1024)) $mw $vw } else { $null }
            $blank = ' ' * (6 + $mw + 2 + $vw)
            $meters = @()
            if ($two) {
                foreach ($pair in @(@($cCpu, $cGpu), @($cRam, $cVrm))) {
                    if (-not $pair[0] -and -not $pair[1]) { continue }
                    $l = if ($pair[0]) { $pair[0] } else { $blank }
                    $r = if ($pair[1]) { $pair[1] } else { '' }
                    $meters += Tail "$ind  $l    $r"
                }
            }
            else { foreach ($c in @($cCpu, $cRam, $cGpu, $cVrm)) { if ($c) { $meters += Tail "$ind  $c" } } }

            # steps: equal-width cells, wrapped to the content width
            $list = @($Steps -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $hasRun = $Steps -match '\*'
            $cw = 2 + (($list | ForEach-Object { $_.TrimStart('*').Length } | Measure-Object -Maximum).Maximum) + 3
            $perRow = [math]::Max(1, [math]::Floor(($W - 2) / $cw))
            $stepRows = @(); $row = "$ind  "; $k = 0; $seen = $false
            foreach ($st in $list) {
                $name = Pad $st.TrimStart('*') ($cw - 2)
                if ($st.StartsWith('*')) { $row += "$amb$sp$rst $wht$name$rst"; $seen = $true }
                elseif ($hasRun -and -not $seen) { $row += "$grn$check$rst $dim$name$rst" }
                else { $row += "$frm$dotC$rst $dim$name$rst" }
                $k++
                if ($k % $perRow -eq 0) { $stepRows += $row; $row = "$ind  " }
            }
            if ($k % $perRow -ne 0) { $stepRows += $row }

            $rule = "$ind$frm" + ($hl * $W) + $rst
            $tTxt = if ($Title.Length -gt $W - 3) { $Title.Substring(0, $W - 4) + [char]0x2026 } else { $Title }
            $sTxt = if ($Sub.Length -gt $W - 3) { $Sub.Substring(0, $W - 4) + [char]0x2026 } else { $Sub }
            $out = @("", "$ind$amb$sp$rst  $wht$tTxt$rst", "$ind   $dim$sTxt$rst", "", $top, $mid, $bot, "") + $stats + @("", $rule, "") + $meters
            if ($meters.Count) { $out += @("", $rule, "") }
            $out += $stepRows + @("")

            # redraw in place without flicker; clear the rest of each line and anything below
            Write-Host ("$e[H" + (($out | ForEach-Object { "$_$e[K" }) -join "`n") + "$e[J") -NoNewline
            if ($done -ge $total) { break }
        }
        if ($FailOn -and (Select-String -Path $log -Pattern $FailOn -Quiet)) { Write-Host "`n`n  $red x  Render failed - see $log$rst"; return }
        Start-Sleep -Milliseconds 500
    }
    Write-Host "`n  $grn$check  All frames rendered.$rst`n"
}
finally { Write-Host "$e[?25h" -NoNewline }
