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
