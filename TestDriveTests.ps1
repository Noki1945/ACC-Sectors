# Interactive test drive uses production Timing and wall-time finish hold.
$drive=New-Object AccOverlay.TestDrive
$drive.Timing.ShowDeltaGraph=$true
$d=$drive.Tick(0)
if (-not $d.GraphVisible -or $d.Graph.Segments.Length -lt 80) { throw 'Test mode must start with a usable finished graph' }
$plot=[AccOverlay.DeltaGraphPlot]::Create($d.Graph,214,50)
if ([string]::IsNullOrWhiteSpace($plot.Red) -or [string]::IsNullOrWhiteSpace($plot.Green)) { throw 'Test drive must exercise both graph colours' }
if (-not $drive.Tick(4999).Holding -or $drive.Tick(5000).Holding -or -not $drive.Driving) { throw 'Test drive did not preserve real 5000ms hold' }
for ($wall=5020;$wall -le 8000;$wall+=20) { $d=$drive.Tick($wall) }
if (-not $d.Holding -or $drive.Driving -or $drive.Timing.RecordedLaps -ne 3) { throw 'Test drive did not complete next lap in 3 seconds' }
$drive.Restart('Record'); $d=$drive.Timing.GetDisplay($drive.Now)
if ($d.Graph.FinalDelta -ne -5000 -or $drive.Timing.Best -ne 85000) { throw 'Test record scenario failed' }
$drive.Restart('Invalid')
if ($drive.Timing.Best -ne 90000 -or $drive.Timing.LastLap -ne 85000) { throw 'Test invalid lap changed personal best' }
$drive.Restart('PartialReference'); $d=$drive.Timing.GetDisplay($drive.Now)
if ($d.Graph.Segments.Length -lt 70 -or $d.Graph.Segments[0].X1 -lt 0.12-0.0001) { throw 'Test partial-reference scenario failed' }
$drive.Restart('NoData'); $d=$drive.Timing.GetDisplay($drive.Now)
if ($null -eq $d.Graph -or $d.Graph.Segments.Length -ne 0) { throw 'Test missing-reference scenario fabricated graph points' }
$drive.Restart('MissingPackets'); $d=$drive.Timing.GetDisplay($drive.Now)
if ($d.Graph.Segments.Length -eq 0) { throw 'Test packet gaps removed all usable data' }
foreach($s in $d.Graph.Segments) { if ($s.X1 -lt 0.55 -and $s.X2 -gt 0.40) { throw 'Test packet gap unexpectedly connected' } }
$drive.ResetSession()
if ($drive.Timing.GetDisplay($drive.Now).GraphVisible -or $drive.AutoRun) { throw 'Test reset did not clear graph and stop playback' }
# Seeded random laps are reproducible, monotonic and vary across finishes.
$a=New-Object AccOverlay.TestDrive -ArgumentList 12345
$b=New-Object AccOverlay.TestDrive -ArgumentList 12345
$a.Timing.ShowDeltaGraph=$true;$b.Timing.ShowDeltaGraph=$true
$a.Restart('Random');$b.Restart('Random')
$seen=New-Object 'System.Collections.Generic.HashSet[int]'
$a.Tick(0) | Out-Null;$b.Tick(0) | Out-Null
$previousBest=$a.Timing.Best
for($round=0;$round -lt 24;$round++) {
    if ($a.SimulatedLapTime -ne $b.SimulatedLapTime -or $a.SimulatedLapValid -ne $b.SimulatedLapValid) { throw 'Random seed does not reproduce lap profiles' }
    if ($a.SimulatedLapTime -lt 86000 -or $a.SimulatedLapTime -gt 98000) { throw 'Random lap duration out of bounds' }
    [void]$seen.Add($a.SimulatedLapTime)
    $start=$round*8000
    for($wall=$start+20;$wall -le $start+8000;$wall+=20) { $da=$a.Tick($wall);$db=$b.Tick($wall) }
    if (-not $da.Holding -or $null -eq $da.Graph -or $da.Graph.Segments.Length -lt 50 -or $da.Lap -ne $db.Lap) { throw 'Random drive lost a complete trace or reproducibility' }
    if ($a.SimulatedLapValid) { $previousBest=[Math]::Min($previousBest,$a.SimulatedLapTime) }
    if ($a.Timing.Best -ne $previousBest) { throw 'Random invalid/valid lap best tracking failed' }
}
if ($seen.Count -lt 20) { throw 'Random laps do not vary' }