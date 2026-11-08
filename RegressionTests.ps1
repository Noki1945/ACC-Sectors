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

function New-BroadcastPacket([int]$time,[int]$session=1,[bool]$valid=$true,[int]$sessionType=4) {
    $stream=New-Object IO.MemoryStream
    $writer=New-Object IO.BinaryWriter($stream)
    $writer.Write([byte]2); $writer.Write([uint16]0); $writer.Write([uint16]$session)
    $writer.Write([byte]$sessionType); $writer.Write([byte]5)
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
function New-TrafficPacket([int]$id,[single]$spline,[int]$laps,[int]$rank,[int]$location=1,[int]$best=100000,[int]$last=100000,[bool]$validBest=$true) {
    $stream=New-Object IO.MemoryStream; $w=New-Object IO.BinaryWriter($stream)
    $w.Write([byte]3); $w.Write([uint16]$id); $w.Write([uint16]0); $w.Write([byte]1); $w.Write([byte]2)
    1..3 | ForEach-Object { $w.Write([single]0) }
    $w.Write([byte]$location); $w.Write([uint16]0); $w.Write([uint16]$rank); $w.Write([uint16]$rank); $w.Write([uint16]1)
    $w.Write($spline); $w.Write([uint16]$laps); $w.Write([int]0)
    foreach ($kind in @(0,1,2)) {
        $w.Write([int]$(if ($kind -eq 0) { $best } else { $last })); $w.Write([uint16]$id); $w.Write([uint16]0); $w.Write([byte]0)
        $w.Write([byte]$(if ($kind -eq 0 -and -not $validBest) { 1 } else { 0 })); $w.Write([byte]$(if ($kind -eq 0) { $validBest } else { $true })); $w.Write([byte]0); $w.Write([byte]0)
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

# Classification neighbors are exact adjacent ranks, including cars in pits.
$client=New-Object AccOverlay.Broadcast(0,'')
try {
    $client.Process((New-BroadcastPacket 100000 1 $true 10))
    $client.Process((New-TrafficPacket 42 0.5 10 5))
    $client.Process((New-TrafficPacket 101 0.2 11 4))
    $client.Process((New-TrafficPacket 202 0.9 9 6))
    $client.Process((New-TrafficPacket 9 0.501 9 8))
    $pair=$client.GetTraffic(42,100000,[AccOverlay.TrafficMode]::Position)
    if ($pair.AheadId -ne 101 -or $pair.BehindId -ne 202 -or -not $pair.AheadEstimated -or [Math]::Abs($pair.AheadSeconds-70) -gt 0.001) { throw 'Classification rank / unwrapped race progress failed' }
    if ($client.GetTraffic(42,100000,[AccOverlay.TrafficMode]::Track).AheadId -ne 9) { throw 'Track mode was changed by classification mode' }
    $client.Process((New-TrafficPacket 101 0.2 11 4 2))
    $pair=$client.GetTraffic(42,100000,[AccOverlay.TrafficMode]::Position)
    if ($pair.AheadId -ne 101 -or $null -ne $pair.AheadSeconds) { throw 'Pitted classification neighbor must remain selected without a fabricated race interval' }
    $client.Process((New-TrafficPacket 42 0.5 10 4))
    $client.Process((New-TrafficPacket 101 0.2 10 5))
    $client.Process((New-TrafficPacket 303 0.4 11 3))
    $pair=$client.GetTraffic(42,100000,[AccOverlay.TrafficMode]::Position)
    if ($pair.AheadId -ne 303 -or $pair.BehindId -ne 101) { throw 'Position changes did not select new classification neighbors' }
    $client.Process((New-TrafficPacket 304 0.3 11 3))
    if ($null -ne $client.GetTraffic(42,100000,[AccOverlay.TrafficMode]::Position).AheadId) { throw 'Asynchronous duplicate ranks must not guess a neighbor' }
    if ($null -ne $client.GetTraffic(42,100000,[AccOverlay.TrafficMode]::Position,[DateTime]::UtcNow.AddSeconds(3)).BehindId) { throw 'Stale classification data was not hidden' }
    $client.Process((New-BroadcastPacket 100000 2 $true 4))
    $client.Process((New-TrafficPacket 42 0.5 0 2 1 100000))
    $client.Process((New-TrafficPacket 101 0.2 0 1 2 99000))
    $client.Process((New-TrafficPacket 202 0.9 0 3 1 102000))
    $pair=$client.GetTraffic(42,100000,[AccOverlay.TrafficMode]::Position)
    if ($pair.AheadSeconds -ne 1 -or $pair.BehindSeconds -ne 2 -or $pair.AheadEstimated -or $pair.BehindEstimated) { throw 'Qualifying intervals must use valid personal-best lap differences' }
    $client.Process((New-TrafficPacket 101 0.2 0 1 1 98000 100000 $false))
    if ($null -ne $client.GetTraffic(42,100000,[AccOverlay.TrafficMode]::Position).AheadSeconds) { throw 'Invalid qualifying best was used as an interval' }
    $client.Process((New-BroadcastPacket 100000 3 $true 10))
    $client.Process((New-TrafficPacket 42 0.5 10 1))
    $client.Process((New-TrafficPacket 202 0.4 10 2))
    if ($null -ne $client.GetTraffic(42,100000,[AccOverlay.TrafficMode]::Position).AheadId) { throw 'Leader must not have a classified car ahead' }
    $client.Process((New-TrafficPacket 42 0.5 10 3))
    if ($null -ne $client.GetTraffic(42,100000,[AccOverlay.TrafficMode]::Position).BehindId) { throw 'Missing trailing rank must not choose an unrelated car' }
    $client.Process((New-BroadcastPacket 100000 3 $true 4))
    if ($null -ne $client.GetTraffic(42,100000,[AccOverlay.TrafficMode]::Position).AheadId) { throw 'Session type change retained old classification data' }
} finally { $client.Dispose() }

# Reference modes: record full positional traces and freeze reference per lap.
function Feed-TestLap($timing,[int]$number,[int]$duration,[int]$last,[int]$best,[bool]$valid=$true,[int]$session=0,[int]$sessionIndex=0) {
    for ($i=0;$i -lt 100;$i++) {
        $f=Sample $number ([int][Math]::Floor($i/34.0)) ([int]($duration*$i/100.0)) $last ($i/100.0)
        $f.Best=$best; $f.Valid=$valid; $f.Session=$session; $f.SessionIndex=$sessionIndex
        $timing.Update($f)
    }
    $f=Sample ($number+1) 0 0 $duration 0
    $f.Best=$best; $f.Valid=$true; $f.Session=$session; $f.SessionIndex=$sessionIndex
    $timing.Update($f)
}
$t=New-Object AccOverlay.Timing
Feed-TestLap $t 0 90000 0 0
Feed-TestLap $t 1 95000 90000 90000
$t.Mode=[AccOverlay.ComparisonMode]::PersonalBest
$f=Sample 2 1 40000 95000 0.5; $f.Best=90000; $t.Update($f)
if ($t.LiveDifference -ne -5000 -or $t.GetDisplay(999999999999).Forecast -ne 85000) { throw 'Personal-best positional delta / forecast failed' }
$t.Mode=[AccOverlay.ComparisonMode]::Previous
if ($t.LiveDifference -ne -7500) { throw 'Manual reference change did not apply immediately' }
$t.Mode=[AccOverlay.ComparisonMode]::PersonalBest
Feed-TestLap $t 2 85000 95000 90000
if ($t.GetDisplay().LapDelta -ne -5000) { throw 'New personal record was compared against itself' }
$f=Sample 3 1 40000 85000 0.5; $f.Best=85000; $t.Update($f)
if ($t.LiveDifference -ne -2500) { throw 'New personal-best reference was not selected for the next lap' }
Feed-TestLap $t 3 80000 85000 85000 $false
$f=Sample 4 1 40000 80000 0.5; $f.Best=85000; $t.Update($f)
if ($t.LiveDifference -ne -2500) { throw 'Invalid lap replaced the personal reference' }
$t=New-Object AccOverlay.Timing; $t.Mode=[AccOverlay.ComparisonMode]::PersonalBest
$f=Sample 5 0 0 95000 0; $f.Best=80000; $t.Update($f)
Feed-TestLap $t 5 90000 95000 80000
$f=Sample 6 1 40000 90000 0.5; $f.Best=80000; $t.Update($f)
$d=$t.GetDisplay(999999999999)
if ($null -ne $d.LapDelta -or $d.Forecast -ne 0 -or $t.HasReference) { throw 'Unknown pre-launch personal-best points were fabricated or replaced by previous lap' }
foreach ($session in @(0,1,2,3,7,4,-1,99)) {
    $expected=if ($session -in @(1,3,7)) { 'PersonalBest' } else { 'Previous' }
    if ([AccOverlay.Timing]::ResolveMode([AccOverlay.ComparisonMode]::Automatic,$session).ToString() -ne $expected) { throw 'Automatic session mapping failed' }
    if ([AccOverlay.Timing]::ResolveMode([AccOverlay.ComparisonMode]::Previous,$session) -ne [AccOverlay.ComparisonMode]::Previous) { throw 'Automatic mode overrode a manual choice' }
}
$t=New-Object AccOverlay.Timing
foreach ($session in @(0,1,2)) {
    $f=Sample 0 0 0 0 0; $f.Session=$session; $t.Update($f)
    $expected=if ($session -eq 1) { 'PersonalBest' } else { 'Previous' }
    if ($t.EffectiveMode.ToString() -ne $expected -or $t.RecordedLaps -ne 0) { throw 'Live session transition retained incompatible reference data' }
}
# Clock and last-lap time can arrive half a second apart at the finish.
$t=New-Object AccOverlay.Timing
$t.Update((Sample 0 0 0 95000 0),0)
$t.Update((Sample 0 2 89980 95000 0.999),89980)
$t.Update((Sample 1 0 20 95000 0.0002),90020)
$t.Update((Sample 1 0 350 95000 0.004),90350)
if ($t.RecordedLaps -ne 0) { throw 'Stale last-lap time was committed before the delayed result arrived' }
$t.Update((Sample 1 0 550 90000 0.006),90550)
if ($t.RecordedLaps -ne 1 -or $t.History[0].Total -ne 90000 -or $t.History[0].EstimatedTotal) { throw 'Delayed official lap result failed to refine the pending finish' }
# Best-lap references must disappear on session changes and on replay entry.
$t=New-Object AccOverlay.Timing; $t.Mode=[AccOverlay.ComparisonMode]::PersonalBest
Feed-TestLap $t 0 90000 0 0
if (-not $t.HasReference) { throw 'Recorded valid best trace missing' }
$f=Sample 1 0 100 90000 0.001; $f.SessionIndex=4; $t.Update($f)
if ($t.HasReference -or $t.RecordedLaps -ne 0) { throw 'Best trace leaked across sessions' }
$f.Status=1; $t.Update($f)
if ($t.HasReference -or $t.RecordedLaps -ne 0) { throw 'Replay retained live reference data' }

# The same loader/writer is used by the UI and by these compatibility tests.
$preferenceFile=Join-Path $env:TEMP ('acc-preferences-'+[Guid]::NewGuid().ToString('N')+'.json')
try {
    [IO.File]::WriteAllText($preferenceFile,'{"BackgroundOpacity":0.65,"ShowLastLap":false}')
    $prefs=Read-OverlayPreferences $preferenceFile
    if ($prefs.TrafficMode -ne 'Track' -or $prefs.ComparisonMode -ne 'Automatic' -or $prefs.BackgroundOpacity -ne 0.65 -or $prefs.ShowLastLap) { throw 'Old preference compatibility failed' }
    $prefs.TrafficMode='Position'; $prefs.ComparisonMode='PersonalBest'
    Write-OverlayPreferences $prefs $preferenceFile
    $loaded=Read-OverlayPreferences $preferenceFile
    if ($loaded.TrafficMode -ne 'Position' -or $loaded.ComparisonMode -ne 'PersonalBest' -or $loaded.BackgroundOpacity -ne 0.65) { throw 'New preferences did not persist' }
    [IO.File]::WriteAllText($preferenceFile,'{"TrafficMode":"unknown","ComparisonMode":"unknown"}')
    $loaded=Read-OverlayPreferences $preferenceFile
    if ($loaded.TrafficMode -ne 'Track' -or $loaded.ComparisonMode -ne 'Automatic') { throw 'Unknown preference values must use defaults' }
} finally { if (Test-Path -LiteralPath $preferenceFile) { Remove-Item -LiteralPath $preferenceFile } }

# Delta graph: same finish hold clock, immutable snapshot and start-of-lap reference.
function Feed-GraphLap($model,[int]$number,[int]$duration,[long]$start,[int]$last,[int]$best) {
    for ($i=0;$i -lt 100;$i++) {
        $f=Sample $number ([int][Math]::Floor($i/34.0)) ([int]($duration*$i/100.0)) $last ($i/100.0)
        $f.Best=$best; $f.Valid=$true
        $model.Update($f,($start+$f.Current))
    }
    $f=Sample ($number+1) 0 0 $duration 0; $f.Best=$best; $f.Valid=$true
    $model.Update($f,($start+$duration))
}
$t=New-Object AccOverlay.Timing
if ($t.ShowDeltaGraph) { throw 'Graph must default to disabled' }
$t.Mode=[AccOverlay.ComparisonMode]::PersonalBest
Feed-GraphLap $t 0 90000 0 0 0
Feed-GraphLap $t 1 85000 90000 90000 90000
$d=$t.GetDisplay(175000)
if ($d.GraphVisible -or $null -eq $d.Graph -or $d.Graph.FinalDelta -ne -5000 -or $d.Graph.Segments.Length -lt 90) { throw 'Completed graph or frozen previous personal best failed' }
$t.ShowDeltaGraph=$true
$d=$t.GetDisplay(175000); $snapshot=$d.Graph
if (-not $d.GraphVisible -or $d.Graph.ReferenceMode -ne [AccOverlay.ComparisonMode]::PersonalBest) { throw 'Live graph enabling failed' }
if (-not $t.GetDisplay(179999).GraphVisible -or $t.GetDisplay(180000).GraphVisible -or $t.GetDisplay(180000).Holding) { throw 'Graph and finish hold must expire together at exactly 5000ms' }
$t.Mode=[AccOverlay.ComparisonMode]::Previous
if (-not [object]::ReferenceEquals($snapshot,$t.GetDisplay(176000).Graph)) { throw 'Graph changed during finish display' }
$t.ShowDeltaGraph=$false
if ($t.GetDisplay(176000).GraphVisible) { throw 'Live graph disabling failed' }
$t.ShowDeltaGraph=$true
$f=Sample 2 0 10 85000 0.0001; $f.SessionIndex=9; $t.Update($f,176000)
if ($t.GetDisplay(176000).GraphVisible -or $null -ne $t.GetDisplay(176000).Graph) { throw 'Session reset retained graph' }
foreach ($status in @(0,1)) {
    $t=New-Object AccOverlay.Timing; $t.ShowDeltaGraph=$true
    Feed-GraphLap $t 0 90000 0 0 0
    $f=Sample 1 0 5 90000 0.0001; $f.Status=$status; $t.Update($f,90005)
    if ($t.GetDisplay(90005).GraphVisible) { throw 'Menu/replay retained graph' }
}
$t=New-Object AccOverlay.Timing; $t.ShowDeltaGraph=$true
$f=Sample 0 1 45000 0 0.5; $t.Update($f,45000)
$f=Sample 1 0 0 90000 0; $t.Update($f,90000)
if ($null -ne $t.GetDisplay(90000).Graph) { throw 'Incomplete lap produced a graph' }
$none=[AccOverlay.DeltaGraphData]::Build($true,$null,$null,90000,$null,$null,85000,[AccOverlay.ComparisonMode]::PersonalBest,$false)
if ($none.Segments.Length -ne 0 -or $none.FinalDelta -ne 5000) { throw 'Missing trace must produce no data, never fabricated points' }
$p=[float[]]@(0..100 | ForEach-Object { $_/100.0 })
$times=[int[]]@(0..100 | ForEach-Object { $_*900 })
$reference=[int[]]@(0..100 | ForEach-Object { $_*950 })
$g=[AccOverlay.DeltaGraphData]::Build($true,$p,$times,90000,$p,$reference,95000,[AccOverlay.ComparisonMode]::Previous,$false)
if ($g.Segments[-1].Y2 -ne -5) { throw 'Graph must match samples by track progress' }
$plot=[AccOverlay.DeltaGraphPlot]::Create($g,214,50)
if ([string]::IsNullOrWhiteSpace($plot.Green) -or -not [string]::IsNullOrWhiteSpace($plot.Red)) { throw 'Faster graph must be green' }
$gapPositions=[float[]]@($p[0..20]+$p[40..100]); $gapTimes=[int[]]@($times[0..20]+$times[40..100])
$g=[AccOverlay.DeltaGraphData]::Build($true,$p,$times,90000,$gapPositions,$gapTimes,90000,[AccOverlay.ComparisonMode]::Previous,$false)
foreach($segment in $g.Segments) { if ($segment.X1 -lt 0.39 -and $segment.X2 -gt 0.21) { throw 'Graph interpolated across missing packets' } }
$r=[AccOverlay.DeltaGraphLayout]::Place(100,100,516,244,0,0,1920,1080)
$l=[AccOverlay.DeltaGraphLayout]::Place(1300,100,516,244,0,0,1920,1080)
if (-not $r.Visible -or $r.OnLeft -or $r.Left -ne 622 -or [Math]::Abs($r.Height-97.6) -gt 0.001 -or [Math]::Abs($r.Top-173.2) -gt 0.001 -or -not $l.OnLeft -or $l.Left -ne 1064) { throw 'Graph positioning/size failed' }
if ([AccOverlay.DeltaGraphLayout]::Place(0,0,516,244,0,0,600,800).Visible) { throw 'Graph must hide when no side fits' }
if (-not [AccOverlay.DeltaGraphLayout]::Place(-1800,100,516,244,-1920,0,1920,1080).Visible) { throw 'Negative monitor coordinates failed' }
$preferenceFile=Join-Path $env:TEMP ('acc-graph-prefs-'+[Guid]::NewGuid().ToString('N')+'.json')
try {
    $prefs=Read-OverlayPreferences $preferenceFile
    if ($prefs.ShowDeltaGraph) { throw 'Graph preference default failed' }
    [IO.File]::WriteAllText($preferenceFile,'{"ShowLastLap":true}')
    if ((Read-OverlayPreferences $preferenceFile).ShowDeltaGraph) { throw 'Old preferences enabled graph' }
    $prefs.ShowDeltaGraph=$true; Write-OverlayPreferences $prefs $preferenceFile
    if (-not (Read-OverlayPreferences $preferenceFile).ShowDeltaGraph) { throw 'Graph preference did not persist' }
} finally { if (Test-Path -LiteralPath $preferenceFile) { Remove-Item -LiteralPath $preferenceFile } }
# A first/out lap can have thousands of useful points but no start-line sample.
# Draw only the overlapping range; never extrapolate missing start/end sections.
$partialPositions=[float[]]$p[12..95]; $partialTimes=[int[]]$reference[12..95]
$g=[AccOverlay.DeltaGraphData]::Build($true,$p,$times,90000,$partialPositions,$partialTimes,95000,[AccOverlay.ComparisonMode]::Previous,$false)
if ($g.Segments.Length -lt 70) { throw 'Partial previous-lap trace discarded all usable overlap' }
foreach ($segment in $g.Segments) {
    if ($segment.X1 -lt $partialPositions[0] -or $segment.X2 -gt $partialPositions[-1]) { throw 'Partial reference was extrapolated' }
}
$t=New-Object AccOverlay.Timing; $t.ShowDeltaGraph=$true
for($i=12;$i -lt 100;$i++) {
    $f=Sample 0 ([int][Math]::Floor($i/34.0)) ($i*950) 0 ($i/100.0); $t.Update($f,($i*950))
}
$f=Sample 1 0 0 95000 0; $t.Update($f,95000)
if ($null -ne $t.GetDisplay(95000).Graph) { throw 'Incomplete current lap must still not display a graph' }
Feed-GraphLap $t 1 90000 95000 95000 0
$d=$t.GetDisplay(185000)
if (-not $d.GraphVisible -or $d.Graph.Segments.Length -lt 70 -or $d.Graph.FinalDelta -ne -5000) { throw 'Full lap after partially recorded out lap lost the graph' }
# Source-only interactive tester checks are excluded from the bundled EXE.
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'TestDriveTests.ps1')) { . (Join-Path $PSScriptRoot 'TestDriveTests.ps1') }
