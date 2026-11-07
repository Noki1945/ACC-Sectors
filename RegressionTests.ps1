# Own lap records must survive missing split fields and sparse position samples.
function Sample($laps,$sector,$current,$last,$position) {
    $f=Frame $laps $sector 0 $last; $f.Current=$current; $f.Position=$position; return $f
}
# ACC may advance the lap counter before resetting the clock and position.
$t=New-Object AccOverlay.Timing
for ($i=0;$i -le 99;$i++) { $f=Sample 0 0 ($i*900) 0 ($i/100.0); $t.Update($f,[long]($i*900)) }
$t.Update((Sample 0 2 89980 0 0.999),89980)
$t.Update((Sample 1 2 89990 90000 0.999),89990)
$t.Update((Sample 1 0 20 90000 0.0002),90020)
$t.Update((Sample 1 0 1200 90000 0.013),91200)
$t.Update((Sample 1 1 45000 90000 0.5),135000)
if ($t.History.Count -ne 1 -or $null -eq $t.LiveDifference -or [Math]::Abs($t.LiveDifference) -gt 1) { throw 'Counter-before-clock packets erased the previous-lap trace' }
# A delayed position reset must not add an end-of-track point at 20 ms.
$t=New-Object AccOverlay.Timing
for ($i=0;$i -le 99;$i++) { $f=Sample 0 0 ($i*900) 0 ($i/100.0); $t.Update($f,[long]($i*900)) }
$t.Update((Sample 0 2 89980 0 0.999),89980)
$t.Update((Sample 1 0 20 90000 0.999),90020)
$t.Update((Sample 1 0 40 90000 0.0004),90040)
$d=$t.GetDisplay(96000)
if ($d.Lap -ne 40 -or $t.ReferenceSamples -lt 90 -or ($null -ne $d.LapDelta -and [Math]::Abs($d.LapDelta) -gt 100)) { throw 'Delayed position reset polluted the new lap' }
$t=New-Object AccOverlay.Timing
$t.Update((Sample 0 0 0 0 0),0)
$t.Update((Sample 0 0 29980 0 0.32),29980)
$t.Update((Sample 0 1 30020 0 0.323),30020)
$t.Update((Sample 0 1 60980 0 0.65),60980)
$t.Update((Sample 0 2 61020 0 0.66),61020)
$t.Update((Sample 0 2 92980 0 0.999),92980)
$t.Update((Sample 1 0 20 93000 0.0002),93020)
if ($t.History.Count -ne 1 -or $t.History[0].Total -ne 93000 -or $t.History[0].Sectors[1] -ne 31000) { throw 'Own lap history was not recorded without split fields' }
$t.Update((Sample 1 0 28980 93000 0.31),121980)
$d=$t.GetDisplay(121980)
if ($null -eq $d.LapDelta -or -not $d.LapDeltaEstimated) { throw 'Sparse first-sector reference must provide a marked estimate' }
$t.Update((Sample 1 1 29020 93000 0.312),122020)
$d=$t.GetDisplay(122020)
if ($d.Differences[0] -ne -1000 -or -not $d.EstimatedDifferences[0] -or $d.LapDelta -ne -1000 -or $d.Forecast -ne 92000) { throw 'Local sector comparison / forecast fallback failed' }
$t.Update((Sample 1 1 50000 93000 0.5),143000)
if ($t.GetDisplay(143000).LapDelta -ne -1000) { throw 'Completed-sector delta disappeared in a position gap' }
$t.Update((Sample 1 1 59990 93000 0.65),152990)
$t.Update((Sample 1 2 60030 93000 0.66),153030)
$t.Update((Sample 1 2 91980 93000 0.999),184980)
$t.Update((Sample 2 0 20 92000 0.0002),185020)
if ($t.History.Count -ne 2 -or $t.LapDifference -ne -1000 -or $t.History[0].Sectors[0] -ne 30020) { throw 'Lap subtraction or independent record snapshots failed' }
$d=$t.GetDisplay(190020)
if ($null -ne $d.Differences[0] -or $t.History.Count -ne 2) { throw 'Display reset must not erase recorded laps' }
$t.Reset(); if ($t.History.Count -ne 0) { throw 'Session reset retained stale lap records' }
# Missing/sentinel last-lap values must not create absurd times.
$t=New-Object AccOverlay.Timing
$t.Update((Sample 0 0 0 ([int]::MaxValue) 0),0)
$t.Update((Sample 0 2 89980 ([int]::MaxValue) 0.999),89980)
$t.Update((Sample 1 0 20 ([int]::MaxValue) 0.0002),90020)
$t.Update((Sample 1 0 620 ([int]::MaxValue) 0.007),90620)
if ($t.History.Count -ne 1 -or $t.History[0].Total -ne 90000 -or -not $t.History[0].EstimatedTotal) { throw 'Local lap-clock fallback or sentinel filtering failed' }

# Additional regressions for stable comparisons and ACC protocol v4.
$t=New-Object AccOverlay.Timing
$t.Update((Frame 0 0 0),0); $t.Update((Frame 0 1 30000),30000); $t.Update((Frame 0 2 61000),61000); $t.Update((Frame 1 0 0 93000),93000)
$t.Update((Frame 1 1 29000),122000); $t.Update((Frame 1 2 60010),153010); $t.Update((Frame 2 0 0 92000),185000)
$d=$t.GetDisplay(189999)
if (-not $d.Holding -or $d.Differences[0] -ne -1000 -or $d.Differences[1] -ne 10 -or $d.LapDelta -ne -1000) { throw 'Comparisons must remain visible during finish hold' }
$d=$t.GetDisplay(190000)
if ($d.Holding -or $null -ne $d.Differences[0] -or $null -ne $d.Differences[1] -or $null -ne $d.Differences[2]) { throw 'Comparisons must reset exactly 5 seconds after finish' }
$f=Frame 2 0 0 92000; $f.Current=6000; $t.Update($f,191000)
$d=$t.GetDisplay(191000)
if ($null -ne $d.Differences[0] -or $d.Sectors[0] -ne 6000) { throw 'Old comparisons reappeared on the new lap' }
$f=Frame 2 1 28000 92000; $f.Current=30000; $t.Update($f,215000)
$d=$t.GetDisplay(215000)
if ($d.Differences[0] -ne -1000 -or $null -ne $d.Differences[1] -or $null -ne $d.Differences[2]) { throw 'Only newly completed sector comparisons should appear' }
$f=Frame 2 1 28000; $f.Current=31000; $f.Remaining=500; $t.Update($f)
if ($t.LastLap -ne 92000 -or $t.Previous[0] -ne 29000) { throw 'Missing lap value or session-time jitter erased history' }
$t=New-Object AccOverlay.Timing
$f=Frame 0 0 30000; $f.Current=30000; $t.Update($f)
$f=Frame 0 1 30000; $f.Current=30020; $t.Update($f)
if ($t.GetDisplay().Sectors[0] -ne 30000) { throw 'Split arriving before sector index was lost' }
$f=Frame 0 2 30000; $f.Current=61020; $t.Update($f)
$f=Frame 0 2 61000; $f.Current=61040; $t.Update($f)
if ($t.Sectors[1] -ne 31000) { throw 'Late split retry failed' }

function New-BroadcastPacket([int]$time,[int]$session=1,[bool]$valid=$true) {
    $stream=New-Object IO.MemoryStream
    $writer=New-Object IO.BinaryWriter($stream)
    $writer.Write([byte]2); $writer.Write([uint16]0); $writer.Write([uint16]$session)
    $writer.Write([byte]4); $writer.Write([byte]5)
    $writer.Write([single]1000); $writer.Write([single]100000); $writer.Write([int]0)
    # Three UTF-8 strings, with uint16 byte lengths.
    1..3 | ForEach-Object { $writer.Write([uint16]0) }
    $writer.Write([byte]0); $writer.Write([single]43200000)
    1..5 | ForEach-Object { $writer.Write([byte]0) }
    $writer.Write([int]$time); $writer.Write([uint16]1); $writer.Write([uint16]0)
    $writer.Write([byte]3); 1..3 | ForEach-Object { $writer.Write([int]30000) }
    $writer.Write([byte](-not $valid)); $writer.Write([byte]$valid)
    $writer.Write([byte]0); $writer.Write([byte]0)
    $packet=$stream.ToArray(); $writer.Dispose(); $stream.Dispose()
    return ,$packet
}
$server=New-Object Net.Sockets.UdpClient (New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,0))
$server.Client.ReceiveTimeout=1000
$broadcast=New-Object AccOverlay.Broadcast($server.Client.LocalEndPoint.Port,'fixture')
try {
    $broadcast.Poll()
    $sender=New-Object Net.IPEndPoint([Net.IPAddress]::Any,0)
    $registration=$server.Receive([ref]$sender)
    if ($registration[0] -ne 1 -or $registration[1] -ne 4) { throw 'Incorrect ACC registration protocol' }
    $packet=New-BroadcastPacket 89000
    [void]$server.Send($packet,$packet.Length,$sender)
    $broadcast.Poll()
    if ($broadcast.Best -ne 89000 -or -not $broadcast.Fresh) { throw 'Session best did not arrive over UDP' }
    $broadcast.Process((New-BroadcastPacket 85000 1 $false))
    if ($broadcast.Best -ne 89000) { throw 'Invalid session lap was accepted' }
    $broadcast.Process((New-BroadcastPacket ([int]::MaxValue)))
    if ($broadcast.Best -ne 89000) { throw 'Missing session lap erased best' }
    $broadcast.Process((New-BroadcastPacket ([int]::MaxValue) 2))
    if ($broadcast.Best -ne 0) { throw 'Previous session best leaked into new session' }
    $broadcast.Process((New-BroadcastPacket 88000 2))
    if ($broadcast.Best -ne 88000) { throw 'New session best failed' }
} finally { $broadcast.Dispose(); $server.Close() }
