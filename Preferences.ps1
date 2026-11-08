function Read-OverlayPreferences([string]$Path) {
    $result=@{ BackgroundOpacity=0.30; ShowLastLap=$true; TrafficMode='Track'; ComparisonMode='Automatic'; ShowDeltaGraph=$false }
    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    try {
        $saved=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $saved.BackgroundOpacity) {
            $opacity=[double]$saved.BackgroundOpacity
            if (-not [double]::IsNaN($opacity) -and -not [double]::IsInfinity($opacity)) { $result.BackgroundOpacity=[Math]::Max(0.0,[Math]::Min(1.0,$opacity)) }
        }
        if ($saved.ShowLastLap -is [bool]) { $result.ShowLastLap=$saved.ShowLastLap }
        if ($saved.ShowDeltaGraph -is [bool]) { $result.ShowDeltaGraph=$saved.ShowDeltaGraph }
        foreach ($choice in @('Track','Position')) { if ($saved.TrafficMode -eq $choice) { $result.TrafficMode=$choice; break } }
        foreach ($choice in @('Automatic','Previous','PersonalBest')) { if ($saved.ComparisonMode -eq $choice) { $result.ComparisonMode=$choice; break } }
    } catch { Write-Warning 'Не удалось прочитать настройки. Используются безопасные значения по умолчанию.' }
    return $result
}
function Write-OverlayPreferences($Value,[string]$Path) {
    $Value | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8
}
