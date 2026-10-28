# render-progress: a live, modern terminal progress bar for long renders (Remotion, or anything that logs "N/M").
# Reads the render log twice a second and shows a gradient bar, %, frames, real fps, elapsed, time left,
# finish clock, CPU / RAM / GPU / VRAM meters (GPU via nvidia-smi) and a row of job steps.
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
if ($Sub -eq '') { $Sub = 'Live render  ' + [char]0x25CF + '  ' + (Split-Path $log -Leaf) }
while (-not (Test-Path $log)) { Start-Sleep -Milliseconds 500 }
$e = [char]27
$full = [char]0x2588; $part = @(' ', [char]0x258F, [char]0x258E, [char]0x258D, [char]0x258C, [char]0x258B, [char]0x258A, [char]0x2589)
$spin = @([char]0x280B, [char]0x2819, [char]0x2839, [char]0x2838, [char]0x283C, [char]0x2834, [char]0x2826, [char]0x2827, [char]0x2807, [char]0x280F)
$dot = [char]0x25CF; $check = [char]0x2714; $line = [string][char]0x2500
$width = 46
$start = (Get-Item $log).CreationTime
if ($Demo) { $start = $demoStart }
$hist = New-Object System.Collections.Queue
$tick = 0

# system meters: CPU and RAM via Windows perf counters, GPU via nvidia-smi (refreshed every other tick); missing ones are skipped
$cpuC = $null; try { $cpuC = New-Object System.Diagnostics.PerformanceCounter('Processor Information', '% Processor Utility', '_Total'); [void]$cpuC.NextValue() } catch {}
$memC = $null; try { $memC = New-Object System.Diagnostics.PerformanceCounter('Memory', 'Available MBytes') } catch {}
$ramTot = 0; try { $ramTot = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB } catch {}
$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
$cpu = 0; $ramUsed = 0; $gpu = $null
function Meter($v, $w = 14) {
    $v = [math]::Max(0, [math]::Min(100, $v)); $n = [math]::Round($v / 100 * $w)
    $c = if ($v -ge 90) { Rgb 255 90 70 } elseif ($v -ge 60) { Rgb 255 176 0 } else { Rgb 80 220 140 }
    $c + ([string]$full * $n) + (Rgb 55 55 62) + ([string][char]0x2591 * ($w - $n)) + "$e[0m"
}

function Rgb($r, $g, $b) { "$e[38;2;${r};${g};${b}m" }
function Fmt([TimeSpan]$t) { if ($t.TotalHours -ge 1) { '{0}h {1:D2}m {2:D2}s' -f [int][math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds } else { '{0}m {1:D2}s' -f $t.Minutes, $t.Seconds } }

# amber -> orange -> red gradient across the bar
function Grad($i, $n) {
    $t = $i / [math]::Max(1, $n - 1)
    $r = 255; $g = [int](196 - 120 * $t); $b = [int](40 - 20 * $t)
    Rgb $r $g $b
}

Write-Host "$e[?25l" -NoNewline  # hide cursor
Clear-Host
try {
    while ($true) {
        if ($Demo) { Set-Content $log ('Rendered {0}/9000' -f [math]::Min(9000, [int]((((Get-Date) - $demoStart).TotalSeconds) * 150 + 300 * [math]::Sin(((Get-Date) - $demoStart).TotalSeconds / 3)))) }
        $m = Get-Content $log -Tail 3 -ErrorAction SilentlyContinue | Select-String $Pattern | Select-Object -Last 1
        if ($m) {
            $done = [int]$m.Matches[0].Groups[1].Value
            $total = [int]$m.Matches[0].Groups[2].Value
            $pct = $done / $total
            $now = Get-Date
            $hist.Enqueue(@($now, $done)); while ($hist.Count -gt 40) { [void]$hist.Dequeue() }
            $first = $hist.Peek()
            $dt = ($now - $first[0]).TotalSeconds
            $fps = if ($dt -gt 2) { ($done - $first[1]) / $dt } else { 0 }
            $left = if ($fps -gt 0) { [TimeSpan]::FromSeconds(($total - $done) / $fps) } else { $null }
            $elapsed = $now - $start

            # bar with 1/8 sub-character precision
            $cells = $pct * $width
            $whole = [math]::Floor($cells); $frac = [int](($cells - $whole) * 8)
            $bar = ''
            for ($i = 0; $i -lt $width; $i++) {
                if ($i -lt $whole) { $bar += (Grad $i $width) + $full }
                elseif ($i -eq $whole -and $frac -gt 0) { $bar += (Grad $i $width) + $part[$frac] }
                else { $bar += (Rgb 55 55 62) + [char]0x2591 }
            }

            $dim = Rgb 120 120 130; $wht = Rgb 240 240 245; $amb = Rgb 255 176 0; $grn = Rgb 80 220 140; $rst = "$e[0m"
            $sp = $spin[$tick % $spin.Count]; $tick++
            if ($tick % 2 -eq 1) {
                if ($cpuC) { try { $cpu = [math]::Min(100, $cpuC.NextValue()) } catch {} }
                if ($memC -and $ramTot) { try { $ramUsed = $ramTot - $memC.NextValue() / 1024 } catch {} }
                if ($smi) { try { $q = (& nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits | Select-Object -First 1) -split ',\s*'; $gpu = @([int]$q[0], [int]$q[1], [int]$q[2], [int]$q[3]) } catch {} }
            }
            $ramPct = if ($ramTot) { $ramUsed / $ramTot * 100 } else { 0 }
            $sysA = "    ${dim}CPU   $rst" + (Meter $cpu) + ("  $wht{0,-16}$rst" -f ('{0:N0}%' -f $cpu))
            $sysB = "    ${dim}RAM   $rst" + (Meter $ramPct) + ("  $wht{0,-16}$rst" -f ('{0:N1} / {1:N1} GB' -f $ramUsed, $ramTot))
            if ($gpu) {
                $sysA += "  ${dim}GPU   $rst" + (Meter $gpu[0]) + ("  $wht{0,3}%$rst  ${dim}{1}" -f $gpu[0], $gpu[3]) + [char]0x00B0 + "C$rst"
                $sysB += "  ${dim}VRAM  $rst" + (Meter ($gpu[1] / [math]::Max(1, $gpu[2]) * 100)) + ("  $wht{0:N1}$dim / {1:N1} GB$rst" -f ($gpu[1] / 1024), ($gpu[2] / 1024))
            }
            $stepRow = '   '; $seen = $false; $hasRun = $Steps -match '\*'
            foreach ($st in ($Steps -split ',')) {
                $st = $st.Trim(); if (-not $st) { continue }
                if ($st.StartsWith('*')) { $stepRow += " $amb$sp$rst $wht$($st.Substring(1))$rst   "; $seen = $true }
                elseif ($hasRun -and -not $seen) { $stepRow += " $grn$check$rst $dim$st$rst   " }
                else { $stepRow += " $dim$dot $st$rst   " }
            }
            $eta = if ($left) { Fmt $left } else { '...' }
            $at = if ($left) { ($now + $left).ToString('HH\:mm') } else { '--:--' }

            $out = @(
                ""
                "  $amb$sp$rst  ${wht}$Title$rst"
                "     ${dim}$Sub$rst"
                ""
                "  ${dim}" + ($line * ($width + 12)) + "$rst"
                ""
                "    $bar$rst  $amb{0,6:P1}$rst" -f $pct
                ""
                ("    ${dim}Frames   $wht{0,7:N0}$dim / {1:N0}$rst" -f $done, $total)
                ("    ${dim}Speed    $wht{0,7:N1}$dim fps$rst" -f $fps)
                ("    ${dim}Elapsed  $wht{0,10}$rst" -f (Fmt $elapsed))
                ("    ${dim}Left     $amb{0,10}$rst   ${dim}done around $wht{1}$rst" -f $eta, $at)
                ""
                "  ${dim}" + ($line * ($width + 12)) + "$rst"
                ""
                $sysA
                $sysB
                ""
                "  ${dim}" + ($line * ($width + 12)) + "$rst"
                ""
                $stepRow
                ""
            )
            # redraw in place without flicker
            Write-Host ("$e[H" + (($out | ForEach-Object { "$_$e[K" }) -join "`n")) -NoNewline
            if ($done -ge $total) { break }
        }
        if ($FailOn -and (Select-String -Path $log -Pattern $FailOn -Quiet)) { Write-Host "`n`n    $(Rgb 255 90 70)x  Render failed - see $log$e[0m"; return }
        Start-Sleep -Milliseconds 500
    }
    Write-Host "`n`n    $(Rgb 80 220 140)$check  All frames rendered.$e[0m`n"
}
finally { Write-Host "$e[?25h" -NoNewline }
