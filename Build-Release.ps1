param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference='Stop'
$version='1.0.0'
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The .NET Framework C# compiler was not found.' }
$destination=[IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($destination)
$exe=Join-Path $destination 'ACC-Sectors.exe'
$payload=@('Overlay.ps1','Telemetry.cs','Broadcast.cs','BroadcastConfig.ps1','RegressionTests.ps1')
$compilerArgs=@('/nologo','/target:winexe','/platform:x64','/optimize+','/codepage:65001','/r:System.Windows.Forms.dll',('/out:'+$exe))
foreach($file in $payload) {
    $path=Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing release file: $file" }
    $compilerArgs+=('/resource:'+ $path + ',AccSectors.' + $file)
}
$compilerArgs+=(Join-Path $PSScriptRoot 'release\Launcher.cs')
& $compiler @compilerArgs
if ($LASTEXITCODE -ne 0) { throw 'Release compilation failed.' }
$check=Start-Process -FilePath $exe -ArgumentList '--self-test' -WindowStyle Hidden -Wait -PassThru
if ($check.ExitCode -ne 0) { throw 'Bundled EXE self-test failed. See %LOCALAPPDATA%\ACC Sectors\Data\launch.log.' }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'release\README-RU.txt') -Destination (Join-Path $destination 'README-RU.txt') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'CHANGELOG.md') -Destination (Join-Path $destination 'CHANGELOG.md') -Force
$zip=Join-Path $destination ("ACC-Sectors-v$version-win-x64.zip")
Compress-Archive -LiteralPath @($exe,(Join-Path $destination 'README-RU.txt'),(Join-Path $destination 'CHANGELOG.md')) -DestinationPath $zip -Force
@($exe,$zip) | ForEach-Object { $hash=Get-FileHash -LiteralPath $_ -Algorithm SHA256; $hash.Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($_) } | Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') -Encoding ASCII
Write-Host "Release $version built: $exe"
Write-Host "Archive: $zip"
