param([switch]$Demo, [switch]$SelfTest, [switch]$Preview, [ValidateRange(0,10000)][int]$PreviewDelayMs=400, [string]$DataDirectory)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($DataDirectory)) { $DataDirectory=$PSScriptRoot }
[void][IO.Directory]::CreateDirectory($DataDirectory)
Add-Type -Path @((Join-Path $PSScriptRoot 'Telemetry.cs'),(Join-Path $PSScriptRoot 'Broadcast.cs'),(Join-Path $PSScriptRoot 'DeltaGraph.cs'))
. (Join-Path $PSScriptRoot 'Preferences.ps1')
if ($SelfTest) {
    function Frame($laps,$sector,$split,$last=0) {
        $f = New-Object AccOverlay.Frame
        $f.Status=2; $f.Laps=$laps; $f.Sector=$sector; $f.Split=$split; $f.Last=$last
        return $f
    }
    $t=New-Object AccOverlay.Timing
    $t.Update((Frame 0 0 0)); $t.Update((Frame 0 1 30000)); $t.Update((Frame 0 2 61000)); $t.Update((Frame 1 0 0 93000))
    if ($t.Previous[2] -ne 32000) { throw 'Third sector failed' }
    $t.Update((Frame 1 1 29000)); $t.Update((Frame 1 2 60010)); $t.Update((Frame 2 0 0 92000))
    if ($t.Differences[0] -ne -1000 -or $t.Differences[1] -ne 10 -or $t.LapDifference -ne -1000) { throw 'Comparison failed' }
    $t.Update((Frame 0 0 0)); if ($t.LapDifference -ne $null -or $t.Previous[0] -ne 0) { throw 'Reset failed' }
    # Regression: actual cumulative values from the user's Brands Hatch lap.
    $t=New-Object AccOverlay.Timing
    $t.Update((Frame 0 0 0)); $t.Update((Frame 0 1 59750)); $t.Update((Frame 0 2 83755)); $t.Update((Frame 1 0 0 122560))
    if ($t.Sectors[0] -ne 59750 -or $t.Sectors[1] -ne 24005 -or $t.Sectors[2] -ne 38805 -or $t.LastLap -ne 122560) { throw 'Cumulative split regression failed' }
    # Split and last-lap fields may update one packet after sector/lap counters.
    $t=New-Object AccOverlay.Timing
    $t.Update((Frame 0 0 0)); $t.Update((Frame 0 1 30000)); $t.Update((Frame 0 2 30000)); $t.Update((Frame 0 2 61000))
    $t.Update((Frame 1 0 0)); $t.Update((Frame 1 0 0 93000))
    if ($t.Sectors[1] -ne 31000 -or $t.Sectors[2] -ne 32000) { throw 'Delayed telemetry regression failed' }
    $t=New-Object AccOverlay.Timing
    $t.Update((Frame 0 2 61000)); $t.Update((Frame 1 0 0 93000))
    if ($t.Sectors[2] -ne 0) { throw 'Unknown sector must remain empty' }
    $t=New-Object AccOverlay.Timing
    $t.Update((Frame 0 0 0)); $t.Update((Frame 1 0 0 90000))
    for ($i=1;$i -lt 100;$i++) { $f=Frame 1 0 0; $f.Position=$i/100.0; $f.Current=$i*900; $t.Update($f) }
    $t.Update((Frame 2 0 0 90000))
    $f=Frame 2 0 0; $f.Position=0.505; $f.Current=45000; $t.Update($f)
    if ([Math]::Abs($t.LiveDifference + 450) -gt 1) { throw 'Live delta interpolation failed' }
    # Live sectors use their own elapsed time, and finish results hold for 5 s.
    $t=New-Object AccOverlay.Timing
    $f=Frame 0 0 0; $t.Update($f,0)
    $f=Frame 0 0 0; $f.Current=20000; $t.Update($f,20000)
    if ($t.GetDisplay(20000).Sectors[0] -ne 20000) { throw 'Live S1 failed' }
    $f=Frame 0 0 0; $f.Current=25000; $t.Update($f,25000)
    if ($t.GetDisplay(25000).Sectors[0] -ne 25000) { throw 'Live S1 advancement failed' }
    $f=Frame 0 1 30000; $f.Current=35000; $t.Update($f,35000)
    $d=$t.GetDisplay(35000)
    if ($d.Sectors[0] -ne 30000 -or $d.Sectors[1] -ne 5000) { throw 'Live S2 subtraction failed' }
    $f=Frame 0 2 61000; $f.Current=70000; $t.Update($f,70000)
    if ($t.GetDisplay(70000).Sectors[2] -ne 9000) { throw 'Live S3 subtraction failed' }
    $f=Frame 1 0 0 93000; $f.Current=100; $t.Update($f,93000)
    $d=$t.GetDisplay(97999)
    if (-not $d.Holding -or $d.Sectors[2] -ne 32000 -or $d.Lap -ne 93000) { throw 'Finish hold failed' }
    $f=Frame 1 0 0 93000; $f.Current=5100; $t.Update($f,98000)
    $d=$t.GetDisplay(98000)
    if ($d.Holding -or $d.Sectors[0] -ne 5100 -or $d.Sectors[1] -ne 0 -or $d.Sectors[2] -ne 0) { throw 'Hold release / background timing failed' }
    # Official best survives a missing packet; invalid local laps are labelled.
    $t=New-Object AccOverlay.Timing; $f=Frame 0 0 0; $f.Best=90000; $t.Update($f)
    $f=Frame 0 0 0; $t.Update($f)
    if ($t.Best -ne 90000 -or $t.BestIsObserved) { throw 'Best retention failed' }
    $t=New-Object AccOverlay.Timing; $f=Frame 0 0 0; $f.Valid=$false; $t.Update($f)
    $f=Frame 1 0 0 93000; $t.Update($f)
    if ($t.Best -ne 93000 -or -not $t.BestIsObserved) { throw 'Observed invalid best labelling failed' }
    $t=New-Object AccOverlay.Timing; $t.Update((Frame 0 0 0)); $t.Update((Frame 1 0 0 93000))
    if ($t.Best -ne 93000 -or $t.BestIsObserved) { throw 'Valid local best fallback failed' }
    $f=Frame 1 0 0 93000; $f.SessionIndex=1; $t.Update($f)
    if ($t.HasReference -or $t.LapDifference -ne $null) { throw 'Session identity reset failed' }
    # Partial recorded laps are usable only where an actual reference exists.
    $t=New-Object AccOverlay.Timing
    for ($i=50;$i -lt 100;$i++) { $f=Frame 0 1 30000; $f.Current=$i*900; $f.Position=$i/100.0; $t.Update($f) }
    $t.Update((Frame 1 0 0 90000))
    $f=Frame 1 0 0 90000; $f.Position=0.10; $f.Current=8900; $t.Update($f)
    if ($null -ne $t.LiveDifference) { throw 'Missing reference must not fabricate a delta' }
    $f=Frame 1 1 30000 90000; $f.Position=0.505; $f.Current=45000; $t.Update($f)
    if ([Math]::Abs($t.LiveDifference + 450) -gt 1) { throw 'Partial reference interpolation failed' }
    # The position and clock may wrap before the lap counter at the finish.
    $t=New-Object AccOverlay.Timing
    for ($i=0;$i -le 99;$i++) { $f=Frame 0 0 0; $f.Current=$i*900; $f.Position=$i/100.0; $t.Update($f,[long]($i*900)) }
    $f=Frame 0 0 0; $f.Position=0.001; $f.Current=90; $t.Update($f,90090)
    $f=Frame 1 0 0 90000; $f.Position=0.002; $f.Current=180; $t.Update($f,90180)
    $f=Frame 1 0 0 90000; $f.Position=0.505; $f.Current=45000; $t.Update($f,135000)
    if ([Math]::Abs($t.LiveDifference + 450) -gt 1) { throw 'Finish packet ordering lost the delta trace' }
    # Validate the actual shared-memory offsets and UTF-16 best-time fallback.
    $bytes=New-Object byte[] 1412
    function Put-Int($offset,$value) { [BitConverter]::GetBytes([int]$value).CopyTo($bytes,$offset) }
    Put-Int 4 2; Put-Int 132 4; Put-Int 140 25001; Put-Int 144 93000; Put-Int 1320 7; Put-Int 1408 1
    [BitConverter]::GetBytes([single]0.25).CopyTo($bytes,248)
    [Text.Encoding]::Unicode.GetBytes('1:32.037').CopyTo($bytes,72)
    $decoded=[AccOverlay.Reader]::Decode($bytes)
    if ($decoded.Best -ne 92037 -or $decoded.Current -ne 25001 -or $decoded.Laps -ne 4 -or $decoded.Position -ne 0.25 -or $decoded.SessionIndex -ne 7 -or -not $decoded.Valid) { throw 'Graphics decoding failed' }
    . (Join-Path $PSScriptRoot 'RegressionTests.ps1')
    Write-Host 'Timing and broadcasting tests passed'; exit
}
Add-Type -AssemblyName PresentationFramework
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="516" Height="190" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True" ResizeMode="NoResize" ShowInTaskbar="True" Title="ACC Sectors" FontFamily="Segoe UI" Foreground="#FFFFFF">
 <Border Name="PanelBackground" Background="#4D141820" CornerRadius="12" BorderBrush="#39414F" BorderThickness="1" Padding="13,9">
  <StackPanel>
   <Grid Margin="0,0,0,7">
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <TextBlock Text="ACC / SECTORS" FontSize="13" Foreground="#FFFFFF"/>
    <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center" Margin="8,0">
     <TextBlock Name="GapAhead" Text="↑ —" FontSize="13" Foreground="White" ToolTip="Ближайшая машина впереди на трассе независимо от позиции и количества кругов. ≈ — оценка секунд по расстоянию вдоль трассы."/>
     <TextBlock Text=" / " FontSize="13" Foreground="White" Margin="5,0"/>
     <TextBlock Name="GapBehind" Text="↓ —" FontSize="13" Foreground="White" ToolTip="Ближайшая машина сзади на трассе независимо от позиции и количества кругов. ≈ — оценка секунд по расстоянию вдоль трассы."/>
    </StackPanel>
    <TextBlock Grid.Column="2" Name="State" Text="ОЖИДАНИЕ ACC" FontSize="13" HorizontalAlignment="Right" Foreground="#FFFFFF"/>
   </Grid>
   <UniformGrid Columns="4">
    <StackPanel><TextBlock Text="S1" FontSize="13" Foreground="#FFFFFF"/><TextBlock Name="S0" Text="--.---" FontSize="26" FontWeight="SemiBold"/><TextBlock Name="D0" Text="—" FontSize="22" FontWeight="SemiBold"/></StackPanel>
    <StackPanel><TextBlock Text="S2" FontSize="13" Foreground="#FFFFFF"/><TextBlock Name="S1" Text="--.---" FontSize="26" FontWeight="SemiBold"/><TextBlock Name="D1" Text="—" FontSize="22" FontWeight="SemiBold"/></StackPanel>
    <StackPanel><TextBlock Text="S3" FontSize="13" Foreground="#FFFFFF"/><TextBlock Name="S2" Text="--.---" FontSize="26" FontWeight="SemiBold"/><TextBlock Name="D2" Text="—" FontSize="22" FontWeight="SemiBold"/></StackPanel>
    <StackPanel><TextBlock Text="КРУГ" FontSize="13"/><TextBlock Name="Lap" Text="--:--.---" FontSize="25" FontWeight="SemiBold"/><TextBlock Name="LapDelta" Text="—" FontSize="22" FontWeight="SemiBold"/><TextBlock Name="Forecast" Text="ПРОГН. —" FontSize="12" Margin="0,3,0,0"/></StackPanel>
   </UniformGrid>
   <TextBlock Name="Best" Text="BEST  --:--.--- / --:--.---" FontSize="17" Margin="0,9,0,0"/>
   <DockPanel Margin="0,4,0,0"><StackPanel Name="LastLapRow" Orientation="Horizontal"><TextBlock Text="ПРОШЛЫЙ КРУГ  " FontSize="16"/><TextBlock Name="LastLap" Text="--:--.---" FontSize="17" FontWeight="SemiBold"/></StackPanel><TextBlock Name="Laps" Text="КРУГОВ  0" FontSize="15" HorizontalAlignment="Right"/></DockPanel>
   <Button Name="SettingsButton" Content="⚙ Настройки" HorizontalAlignment="Left" Margin="0,7,0,0" Padding="7,2" FontSize="12" Foreground="White" Background="#402D3645" BorderBrush="#68788D" Cursor="Hand" ToolTip="Затемнение фона и отображение прошлого круга"/>
  </StackPanel>
 </Border>
</Window>
'@
$window=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$controls=@{}; @('State','GapAhead','GapBehind','S0','S1','S2','D0','D1','D2','Best','Laps','LastLap','Lap','LapDelta','Forecast','PanelBackground','LastLapRow','SettingsButton') | ForEach-Object { $controls[$_]=$window.FindName($_) }
. (Join-Path $PSScriptRoot 'DeltaGraph.ps1')
$script:preferencesPath=Join-Path $DataDirectory 'preferences.json'
$script:preferences=Read-OverlayPreferences $script:preferencesPath
function Save-Preferences {
    try { Write-OverlayPreferences $script:preferences $script:preferencesPath }
    catch { Write-Warning 'Не удалось сохранить настройки панели.' }
}
function Apply-Preferences {
    $alpha=[byte][Math]::Round(255*$script:preferences.BackgroundOpacity)
    $controls.PanelBackground.Background=New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb($alpha,20,24,32))
    $controls.LastLapRow.Visibility=if ($script:preferences.ShowLastLap) { 'Visible' } else { 'Collapsed' }
    $window.Height=244
    if ($null -ne $timing) { $timing.Mode=[AccOverlay.ComparisonMode]$script:preferences.ComparisonMode; $timing.ShowDeltaGraph=$script:preferences.ShowDeltaGraph }
    Update-ComparisonLabel
    Set-DeltaGraphAppearance
    if (-not $script:preferences.ShowDeltaGraph) { $script:graphWindow.Hide() }
    elseif ($null -ne $script:lastDisplay) { Update-DeltaGraphView $script:lastDisplay }
}
$script:settingsWindow=$null
function Get-ComparisonLabel($mode) {
    if ($mode -eq [AccOverlay.ComparisonMode]::PersonalBest) { return 'Личный лучший круг' }
    return 'Предыдущий круг'
}
function Update-ComparisonLabel {
    if ($null -ne $script:settingsControls -and $null -ne $timing) {
        $label=Get-ComparisonLabel $timing.EffectiveMode
        $script:settingsControls.ActiveComparison.Text='Сейчас: '+$label
    }
}
function Show-OverlaySettings {
    if ($null -ne $script:settingsWindow) { [void]$script:settingsWindow.Activate(); return }
    [xml]$settingsXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Настройки ACC Sectors" Width="400" SizeToContent="Height" ResizeMode="NoResize" WindowStartupLocation="CenterOwner" Background="#141820" Foreground="White" FontFamily="Segoe UI" FontSize="14" ShowInTaskbar="False" Topmost="True">
 <StackPanel Margin="20">
  <TextBlock Text="Внешний вид" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,14"/>
  <DockPanel><TextBlock Text="Затемнение фона"/><TextBlock Name="OpacityValue" HorizontalAlignment="Right"/></DockPanel>
  <Slider Name="OpacitySlider" Minimum="0" Maximum="100" TickFrequency="5" SmallChange="1" LargeChange="10" Margin="0,10,0,3"/>
  <TextBlock Text="0% — прозрачный · 100% — непрозрачный" FontSize="12" Foreground="#D7DFEB" Margin="0,0,0,20"/>
  <CheckBox Name="ShowLastLapToggle" Content="Показывать прошлый круг" Foreground="White"/>
  <TextBlock Text="Время последнего завершённого круга под строкой BEST." TextWrapping="Wrap" FontSize="12" Foreground="#D7DFEB" Margin="23,7,0,15"/>
  <TextBlock Text="Соседние машины" Margin="0,0,0,6"/>
  <ComboBox Name="TrafficModeChoice" Foreground="Black" SelectedIndex="0" Margin="0,0,0,14">
   <ComboBoxItem Tag="Track" Content="На трассе"/><ComboBoxItem Tag="Position" Content="По позиции"/>
  </ComboBox>
  <TextBlock Text="Сравнение времени круга" Margin="0,0,0,6"/>
  <ComboBox Name="ComparisonChoice" Foreground="Black" SelectedIndex="0">
   <ComboBoxItem Tag="Automatic" Content="Автоматически"/><ComboBoxItem Tag="Previous" Content="Предыдущий круг"/><ComboBoxItem Tag="PersonalBest" Content="Личный лучший круг"/>
  </ComboBox>
  <TextBlock Name="ActiveComparison" FontSize="12" Margin="0,6,0,15" Foreground="#D7DFEB"/>
  <CheckBox Name="ShowDeltaGraphToggle" Content="Показывать график дельты после круга" Foreground="White" Margin="0,0,0,15"/>
  <TextBlock Text="Изменения применяются и сохраняются сразу." TextWrapping="Wrap" FontSize="12" Margin="0,0,0,16"/>
  <Button Name="DoneButton" Content="Готово" HorizontalAlignment="Right" Padding="20,6" MinWidth="90"/>
 </StackPanel>
</Window>
'@
    $script:settingsWindow=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $settingsXaml))
    $script:settingsWindow.Owner=$window
    $script:settingsControls=@{}
    @('OpacityValue','OpacitySlider','ShowLastLapToggle','DoneButton','TrafficModeChoice','ComparisonChoice','ActiveComparison','ShowDeltaGraphToggle') | ForEach-Object { $script:settingsControls[$_]=$script:settingsWindow.FindName($_) }
    $script:settingsControls.OpacitySlider.Value=$script:preferences.BackgroundOpacity*100
    $script:settingsControls.OpacityValue.Text=('{0:0}%' -f ($script:preferences.BackgroundOpacity*100))
        $script:settingsControls.ShowLastLapToggle.IsChecked=$script:preferences.ShowLastLap
    $script:settingsControls.TrafficModeChoice.SelectedIndex=if ($script:preferences.TrafficMode -eq 'Position') { 1 } else { 0 }
    $script:settingsControls.ComparisonChoice.SelectedIndex=@('Automatic','Previous','PersonalBest').IndexOf($script:preferences.ComparisonMode)
    Update-ComparisonLabel
    $script:settingsControls.TrafficModeChoice.Add_SelectionChanged({
        $script:preferences.TrafficMode=[string]$script:settingsControls.TrafficModeChoice.SelectedItem.Tag
        Apply-Preferences; Save-Preferences
    })
    $script:settingsControls.ComparisonChoice.Add_SelectionChanged({
        $script:preferences.ComparisonMode=[string]$script:settingsControls.ComparisonChoice.SelectedItem.Tag
        Apply-Preferences; Save-Preferences
    })
    $script:settingsControls.ShowDeltaGraphToggle.IsChecked=$script:preferences.ShowDeltaGraph
    $script:settingsControls.ShowDeltaGraphToggle.Add_Click({
        $script:preferences.ShowDeltaGraph=[bool]$script:settingsControls.ShowDeltaGraphToggle.IsChecked
        Apply-Preferences; Save-Preferences
    })
    $script:settingsControls.OpacitySlider.Add_ValueChanged({
        $script:preferences.BackgroundOpacity=[double]$_.NewValue/100
        $script:settingsControls.OpacityValue.Text=('{0:0}%' -f $_.NewValue)
        Apply-Preferences; Save-Preferences
    })
    $script:settingsControls.ShowLastLapToggle.Add_Click({
        $script:preferences.ShowLastLap=[bool]$script:settingsControls.ShowLastLapToggle.IsChecked
        Apply-Preferences; Save-Preferences
    })
    $script:settingsControls.DoneButton.Add_Click({ $script:settingsWindow.Close() })
    $script:settingsWindow.Add_KeyDown({ if ($_.Key -eq 'Escape') { $script:settingsWindow.Close(); $_.Handled=$true } })
    $script:settingsWindow.Add_Closed({ $script:settingsWindow=$null; $script:settingsControls=$null })
    $script:settingsWindow.Show()
}
$controls.SettingsButton.Add_Click({ Show-OverlaySettings })
$reader=New-Object AccOverlay.Reader; $timing=New-Object AccOverlay.Timing
Apply-Preferences
. (Join-Path $PSScriptRoot 'BroadcastConfig.ps1')
$broadcast=if ($Demo -or $Preview) { New-Object AccOverlay.Broadcast(0,'') } else { Initialize-LocalBroadcast }
function Get-DemoFrame([long]$clock) {
    $f=New-Object AccOverlay.Frame
    $f.Status=2
    if ($clock -lt 93000) { $f.Laps=0; $f.Current=[int]$clock; $duration=93000; $secondSplit=61000 }
    else { $f.Laps=1+[int][Math]::Floor(($clock-93000)/90000.0); $f.Current=[int](($clock-93000) % 90000); $duration=90000; $secondSplit=60000 }
    $f.Sector=if ($f.Current -lt 30000) { 0 } elseif ($f.Current -lt $secondSplit) { 1 } else { 2 }
    $f.Position=$f.Current/[double]$duration
    $f.Split=if ($f.Sector -eq 1) { 30000 } elseif ($f.Sector -eq 2) { $secondSplit } else { 0 }
    $f.Last=if ($f.Laps -ge 2) { 90000 } elseif ($f.Laps -eq 1) { 93000 } else { 0 }; $f.Best=$f.Last
    return $f
}
if ($Preview) { $Demo=$true; $script:preferences.ShowDeltaGraph=$true; Apply-Preferences }
if ($Demo) {
    for ($demoSeed=0; $demoSeed -le 183000; $demoSeed+=500) { $timing.Update((Get-DemoFrame $demoSeed),[long]$demoSeed) }
    $demoClock=[Diagnostics.Stopwatch]::StartNew()
}
$window.Left=40; $window.Top=160
$settings=Join-Path $DataDirectory 'position.json'
if (Test-Path $settings) { try { $p=Get-Content $settings -Raw | ConvertFrom-Json; $window.Left=[Math]::Max(0,[Math]::Min([double]$p.Left,[System.Windows.SystemParameters]::VirtualScreenWidth-$window.Width)); $window.Top=[Math]::Max(0,[Math]::Min([double]$p.Top,[System.Windows.SystemParameters]::VirtualScreenHeight-$window.Height)) } catch {} }
$window.Add_MouseLeftButtonDown({ $window.DragMove() })
$window.Add_KeyDown({ if ($_.Key -eq 'Escape') { $window.Close() } })
$menu=New-Object Windows.Controls.ContextMenu
$close=New-Object Windows.Controls.MenuItem; $close.Header='Закрыть'; $close.Add_Click({$window.Close()}); [void]$menu.Items.Add($close); $window.ContextMenu=$menu
function Color($delta) { if ($null -eq $delta -or [Math]::Abs($delta) -le 20) { '#FFFFFF' } elseif ($delta -lt 0) { '#50E3A4' } else { '#FF6B7A' } }
$script:lastPacket=$null; $script:lastChange=[DateTime]::UtcNow
$script:lastDiagnostic=[DateTime]::MinValue
$timer=New-Object Windows.Threading.DispatcherTimer; $timer.Interval=[TimeSpan]::FromMilliseconds(16)
$timer.Add_Tick({
 try {
    if ($Demo) {
        $demoTime=183000+$demoClock.ElapsedMilliseconds
        $timing.Update((Get-DemoFrame $demoTime),[long]$demoTime)
        $display=$timing.GetDisplay([long]$demoTime); $controls.State.Text='ДЕМО'
    } else {
        $f=$reader.Read()
        if ($null -eq $f) { $controls.State.Text='ОЖИДАНИЕ ACC'; $controls.GapAhead.Text='↑ —'; $controls.GapBehind.Text='↓ —'; Update-DeltaGraphView ($timing.GetDisplay()); return }
        if ($script:lastPacket -ne $f.Packet) { $script:lastChange=[DateTime]::UtcNow; $script:lastPacket=$f.Packet }
        if (([DateTime]::UtcNow-$script:lastChange).TotalSeconds -gt 5) { $controls.State.Text='НЕТ ТЕЛЕМЕТРИИ'; $controls.GapAhead.Text='↑ —'; $controls.GapBehind.Text='↓ —'; $reader.Dispose(); Update-DeltaGraphView ($timing.GetDisplay()); return }
        $timing.Update($f)
        $display=$timing.GetDisplay()
        $controls.State.Text= switch ($f.Status) { 0 {'ОЖИДАНИЕ ACC'} 1 {'ПОВТОР'} 2 {'LIVE'} 3 {'ПАУЗА'} default {'ОЖИДАНИЕ ACC'} }
    }
    $script:lastDisplay=$display
    Update-DeltaGraphView $display
    if (-not $Demo) { $broadcast.Poll() }
    if ($Demo) {
        if ($script:preferences.TrafficMode -eq 'Position') { $controls.GapAhead.Text='↑ 0.950'; $controls.GapBehind.Text='↓ 1.600' }
        else { $controls.GapAhead.Text='↑ ≈1.234'; $controls.GapBehind.Text='↓ ≈0.875' }
    }
    elseif ($f.Status -eq 2 -or $f.Status -eq 3) {
        $traffic=$broadcast.GetTraffic($f.PlayerCarId,$timing.LastLap,[AccOverlay.TrafficMode]$script:preferences.TrafficMode)
        $controls.GapAhead.Text='↑ '+[AccOverlay.TrafficPair]::Format($traffic.AheadSeconds,$traffic.AheadMeters,$traffic.AheadEstimated)
        $controls.GapBehind.Text='↓ '+[AccOverlay.TrafficPair]::Format($traffic.BehindSeconds,$traffic.BehindMeters,$traffic.BehindEstimated)
        $controls.GapAhead.ToolTip=$(if ($script:preferences.TrafficMode -eq 'Position') { 'Участник на одну позицию выше в классификации. ' } else { 'Ближайшая впереди на трассе, включая круговых. ' })+'≈ — оценка интервала. '+$broadcast.Status
        $controls.GapBehind.ToolTip=$(if ($script:preferences.TrafficMode -eq 'Position') { 'Участник на одну позицию ниже в классификации. ' } else { 'Ближайшая сзади на трассе, включая круговых. ' })+'≈ — оценка интервала. '+$broadcast.Status
    }
    else { $controls.GapAhead.Text='↑ —'; $controls.GapBehind.Text='↓ —' }
    Update-ComparisonLabel
    if ($display.Holding) { $controls.State.Text=if ($Demo) { 'ДЕМО / ФИНИШ' } else { 'ФИНИШ / 5 С' } }
    for ($i=0;$i -lt 3;$i++) {
        $controls["S$i"].Text=if ($display.Sectors[$i] -gt 0 -or $display.ActiveSector -eq $i) { ($display.Sectors[$i]/1000.0).ToString('0.000',[Globalization.CultureInfo]::InvariantCulture) } else { '--.---' }
        $controls["D$i"].Text=$(if ($display.EstimatedDifferences[$i] -and $null -ne $display.Differences[$i]) { '≈' } else { '' })+[AccOverlay.Timing]::Delta($display.Differences[$i]); $controls["S$i"].Foreground='#FFFFFF'; $controls["D$i"].Foreground=Color $display.Differences[$i]
    }
    $controls.Lap.Text=if ($display.Lap -eq 0 -and $display.ActiveSector -ge 0) { '0:00.000' } else { [AccOverlay.Timing]::Time($display.Lap) }
    $controls.LapDelta.Text=if ($null -eq $display.LapDelta -and -not $display.Holding) { if ($timing.HasReference) { 'НЕТ ТОЧКИ' } else { 'НЕТ ЗАПИСИ' } } else { $(if ($display.LapDeltaEstimated -and $null -ne $display.LapDelta) { '≈' } else { '' })+[AccOverlay.Timing]::Delta($display.LapDelta) }
    $controls.LapDelta.FontSize=if ($null -eq $display.LapDelta -and -not $display.Holding) { 12 } else { 22 }
    $controls.LapDelta.Foreground=Color $display.LapDelta
    $controls.Forecast.Text=if ($display.Forecast -gt 0) { 'ПРОГН. '+[AccOverlay.Timing]::Time($display.Forecast) } else { 'ПРОГН. —' }
    $controls.Forecast.ToolTip='Эталон: '+(Get-ComparisonLabel $display.ReferenceMode)+'. При отсутствии точек личного рекорда прогноз недоступен.'
    $bestLabel=if ($timing.BestIsObserved) { 'BEST*  ' } else { 'BEST  ' }
    $sessionBest=if ($Demo) { 89000 } elseif ($broadcast.Fresh) { $broadcast.Best } else { 0 }
    $sessionText=if ($sessionBest -gt 0) { [AccOverlay.Timing]::Time($sessionBest) } elseif ($script:broadcastRestartRequired -and -not $broadcast.Fresh) { 'ПЕРЕЗАПУСТИ ACC' } elseif (-not $Demo -and -not $broadcast.Fresh) { 'НЕТ СВЯЗИ' } else { '--:--.---' }
    $controls.Best.Text=$bestLabel+[AccOverlay.Timing]::Time($timing.Best)+' / '+$sessionText
    $controls.Laps.Text='КРУГОВ  '+$timing.Laps
    $sessionHint=if ($script:broadcastRestartRequired -and -not $broadcast.Fresh) { 'Перезапустите ACC для получения лучшего круга заезда.' } else { $broadcast.Status }
    $controls.Best.ToolTip='Слева — мой лучший круг; справа — лучший действительный круг среди всех участников текущей сессии. '+$sessionHint
    if ($timing.BestIsObserved) { $controls.Best.ToolTip+=' BEST* — замеченный круг, действительность которого ещё не подтверждена.' }
    $controls.LastLap.Text=[AccOverlay.Timing]::Time($timing.LastLap)
    for ($i=0;$i -lt 3;$i++) { $controls["D$i"].ToolTip='Новый завершённый сектор минус сохранённый сектор прошлого круга. ≈ — граница восстановлена по отсчётам игры. После финиша результат держится 5 секунд.' }
    $controls.LapDelta.ToolTip='Эталон: '+(Get-ComparisonLabel $display.ReferenceMode)+'. '+$(if ($display.Holding) { 'Итоговая разница с эталоном, выбранным на старте круга.' } else { $display.DeltaStatus+'. Записано кругов: '+$timing.RecordedLaps+'. Точек эталона: '+$timing.ReferenceSamples })
    if (-not $Demo -and ([DateTime]::UtcNow-$script:lastDiagnostic).TotalSeconds -ge 2) {
        $script:lastDiagnostic=[DateTime]::UtcNow
        try {
            @{ UpdatedUtc=[DateTime]::UtcNow.ToString('o'); Laps=$timing.Laps; Current=$f.Current; Sector=$f.Sector; Position=$f.Position; RecordedLaps=$timing.RecordedLaps; ReferenceSamples=$timing.ReferenceSamples; PreviousSectors=$timing.Previous; DisplaySectors=$display.Sectors; LapDelta=$display.LapDelta; DeltaStatus=$display.DeltaStatus; Holding=$display.Holding } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $DataDirectory 'timing-status.json') -Encoding UTF8
        } catch { }
    }
 } catch { $controls.State.Text='ОШИБКА ДАННЫХ'; Write-Warning $_ }
})
$window.Add_Closed({ $timer.Stop(); $reader.Dispose(); $broadcast.Dispose(); if ($null -ne $script:graphWindow) { $script:graphWindow.Close() }; try { @{Left=$window.Left;Top=$window.Top} | ConvertTo-Json | Set-Content $settings } catch {} })
if ($Preview) {
    $Demo=$true
    $window.Add_ContentRendered({
        $capture=New-Object Windows.Threading.DispatcherTimer
        $capture.Interval=[TimeSpan]::FromMilliseconds($PreviewDelayMs)
        $capture.Add_Tick({
            $bmp=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
            $bmp.Render($window)
            $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
            $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
            $stream=[IO.File]::Create((Join-Path $DataDirectory 'preview.png')); $encoder.Save($stream); $stream.Dispose()
            if ($script:graphWindow.IsVisible) {
                $graphBmp=New-Object Windows.Media.Imaging.RenderTargetBitmap([int][Math]::Ceiling($script:graphWindow.ActualWidth),[int][Math]::Ceiling($script:graphWindow.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $graphBmp.Render($script:graphWindow)
                $graphEncoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                $graphEncoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($graphBmp))
                $graphStream=[IO.File]::Create((Join-Path $DataDirectory 'preview-graph.png')); $graphEncoder.Save($graphStream); $graphStream.Dispose()
                $onLeft=$script:graphWindow.Left -lt $window.Left
                $combinedWidth=[int][Math]::Ceiling($window.ActualWidth+6+$script:graphWindow.ActualWidth)
                $visual=New-Object Windows.Media.DrawingVisual
                $drawing=$visual.RenderOpen()
                $mainX=if ($onLeft) { $script:graphWindow.ActualWidth+6 } else { 0 }
                $graphX=if ($onLeft) { 0 } else { $window.ActualWidth+6 }
                $drawing.DrawImage($bmp,(New-Object Windows.Rect($mainX,0,$window.ActualWidth,$window.ActualHeight)))
                $drawing.DrawImage($graphBmp,(New-Object Windows.Rect($graphX,(($window.ActualHeight-$script:graphWindow.ActualHeight)/2),$script:graphWindow.ActualWidth,$script:graphWindow.ActualHeight)))
                $drawing.Close()
                $combined=New-Object Windows.Media.Imaging.RenderTargetBitmap($combinedWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $combined.Render($visual)
                $combinedEncoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                $combinedEncoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($combined))
                $combinedStream=[IO.File]::Create((Join-Path $DataDirectory 'preview-with-graph.png')); $combinedEncoder.Save($combinedStream); $combinedStream.Dispose()
            }
            $this.Stop(); $window.Close()
        })
        $capture.Start()
    })
}
$timer.Start(); [void]$window.ShowDialog()
