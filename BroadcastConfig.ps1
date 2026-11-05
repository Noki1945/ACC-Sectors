function Initialize-LocalBroadcast {
    $script:broadcastRestartRequired=$false
    $directory=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Assetto Corsa Competizione\Config'
    if (-not (Test-Path -LiteralPath $directory)) { return (New-Object AccOverlay.Broadcast(0,'')) }
    $path=Join-Path $directory 'broadcasting.json'
    try {
        $encoding=New-Object Text.UnicodeEncoding($false,$true)
        if (Test-Path -LiteralPath $path) {
            $bytes=[IO.File]::ReadAllBytes($path)
            # ACC also creates UTF-16 files without a BOM.
            if ($bytes.Length -gt 1 -and ($bytes[1] -eq 0 -or ($bytes[0] -eq 255 -and $bytes[1] -eq 254))) { $encoding=[Text.Encoding]::Unicode }
            elseif ($bytes.Length -gt 1 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255) { $encoding=[Text.Encoding]::BigEndianUnicode }
            else { $encoding=New-Object Text.UTF8Encoding($false) }
            $text=$encoding.GetString($bytes).TrimStart([char]0xFEFF)
            $config=$text | ConvertFrom-Json
        } else { $config=[pscustomobject]@{ updListenerPort=0; connectionPassword=''; commandPassword='' } }
        $port=[int]$config.updListenerPort
        if ($port -le 0 -or $port -gt 65535) {
            if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath ($path+'.acc-sectors.bak'))) { Copy-Item -LiteralPath $path -Destination ($path+'.acc-sectors.bak') }
            $port=9000
            $config | Add-Member -NotePropertyName updListenerPort -NotePropertyValue $port -Force
            [IO.File]::WriteAllText($path,($config | ConvertTo-Json -Depth 10),$encoding)
        }
        $game=Get-Process -Name 'AC2-Win64-Shipping' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $game) { $script:broadcastRestartRequired=(Get-Item -LiteralPath $path).LastWriteTime -gt $game.StartTime }
        return (New-Object AccOverlay.Broadcast($port,[string]$config.connectionPassword))
    } catch {
        Write-Warning 'Не удалось включить данные лучшего круга заезда. Проверьте broadcasting.json в настройках ACC.'
        return (New-Object AccOverlay.Broadcast(0,''))
    }
}
