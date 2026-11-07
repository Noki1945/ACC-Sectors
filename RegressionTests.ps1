# Decode and format the two independent ACC gaps without swapping directions.
$gapPage=New-Object byte[] 1588
[BitConverter]::GetBytes([int]2).CopyTo($gapPage,4)
[BitConverter]::GetBytes([int]1234).CopyTo($gapPage,1580)
[BitConverter]::GetBytes([int]875).CopyTo($gapPage,1584)
[BitConverter]::GetBytes([int]42).CopyTo($gapPage,1216)
$gapFrame=[AccOverlay.Reader]::Decode($gapPage)
if ($gapFrame.GapAhead -ne 1234 -or $gapFrame.GapBehind -ne 875 -or [AccOverlay.Timing]::Gap($gapFrame.GapAhead) -ne '1.234' -or [AccOverlay.Timing]::Gap($gapFrame.GapBehind) -ne '0.875') { throw 'Front/rear gap decoding or units failed' }
if ($gapFrame.PlayerCarId -ne 42) { throw 'Player identity offset failed' }
if ([AccOverlay.Timing]::Gap(61001) -ne '1:01.001') { throw 'Long gap formatting failed' }
if ([AccOverlay.Timing]::Gap(-19398) -ne '19.398') { throw 'Signed rear gap must display its magnitude' }
foreach ($missing in @(0,-1,[int]::MaxValue,[int]::MinValue)) { if ([AccOverlay.Timing]::Gap($missing) -ne [string][char]0x2014) { throw 'Missing gap must not display zero or an invalid number' } }
$oldGapFrame=[AccOverlay.Reader]::Decode((New-Object byte[] 1412))
if ($oldGapFrame.GapAhead -ne 0 -or $oldGapFrame.GapBehind -ne 0) { throw 'Short graphics snapshot must leave gaps unavailable' }

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

# Track neighbors must be chosen independently of race rank and lap count.
function New-TrafficPacket([int]$id,[single]$spline,[int]$laps,[int]$rank,[int]$location=1) {
    $stream=New-Object IO.MemoryStream; $w=New-Object IO.BinaryWriter($stream)
    $w.Write([byte]3); $w.Write([uint16]$id); $w.Write([uint16]0); $w.Write([byte]1); $w.Write([byte]2)
    1..3 | ForEach-Object { $w.Write([single]0) }
    $w.Write([byte]$location); $w.Write([uint16]0); $w.Write([uint16]$rank); $w.Write([uint16]$rank); $w.Write([uint16]1)
    $w.Write($spline); $w.Write([uint16]$laps); $w.Write([int]0)
    1..3 | ForEach-Object {
        $w.Write([int]100000); $w.Write([uint16]$id); $w.Write([uint16]0); $w.Write([byte]0)
        $w.Write([byte]0); $w.Write([byte]1); $w.Write([byte]0); $w.Write([byte]0)
    }
    $packet=$stream.ToArray(); $w.Dispose(); $stream.Dispose(); return ,$packet
}
$trafficClient=New-Object AccOverlay.Broadcast(0,'')
try {
    $trafficClient.Process((New-BroadcastPacket 100000))
    $trafficClient.Process((New-TrafficPacket 42 0.5 10 8))
    $trafficClient.Process((New-TrafficPacket 7 0.49 99 1))
    $trafficClient.Process((New-TrafficPacket 8 0.51 0 99))
    $trafficClient.Process((New-TrafficPacket 9 0.8 10 7))
    $trafficClient.Process((New-TrafficPacket 10 0.5005 10 9 2))
    $pair=$trafficClient.GetTraffic(42,100000)
    if ($pair.AheadId -ne 8 -or $pair.BehindId -ne 7 -or [Math]::Abs($pair.AheadSeconds-1) -gt 0.001 -or [Math]::Abs($pair.BehindSeconds-1) -gt 0.001) { throw 'Lapped cars or race ranks incorrectly affected track neighbors' }
    if ($null -ne $trafficClient.GetTraffic(999,100000).AheadId) { throw 'Unknown player identity must not guess a focused car' }
    $trafficClient.Process((New-BroadcastPacket 100000 2))
    $trafficClient.Process((New-TrafficPacket 42 0.99 10 8))
    $trafficClient.Process((New-TrafficPacket 20 0.01 0 99))
    $trafficClient.Process((New-TrafficPacket 21 0.97 99 1))
    $pair=$trafficClient.GetTraffic(42,100000)
    if ($pair.AheadId -ne 20 -or $pair.BehindId -ne 21 -or [Math]::Abs($pair.AheadSeconds-2) -gt 0.001) { throw 'Start/finish wrap selected the wrong track neighbor' }
    $trafficClient.Process((New-BroadcastPacket 100000 3))
    if ($null -ne $trafficClient.GetTraffic(42,100000).AheadId) { throw 'Old traffic leaked into the next session' }
} finally { $trafficClient.Dispose() }
