# Owned WPF companion window; its visibility is driven only by Display.Holding.
Add-Type -AssemblyName System.Windows.Forms
[xml]$graphXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="230" Height="98" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True" ShowInTaskbar="False" ShowActivated="False" ResizeMode="NoResize" Focusable="False" Title="ACC Sectors — Delta" FontFamily="Segoe UI" Foreground="White">
 <Border Name="GraphBackground" Background="#4D141820" CornerRadius="12" BorderBrush="#39414F" BorderThickness="1" Padding="8,5">
  <Grid>
   <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
   <DockPanel><TextBlock Text="Δ КРУГА" FontSize="10"/><TextBlock Name="GraphFinal" Text="—" FontSize="13" FontWeight="SemiBold" HorizontalAlignment="Right"/></DockPanel>
   <Grid Grid.Row="1" Margin="0,3,0,1">
    <Canvas Name="GraphCanvas" ClipToBounds="True">
     <Line Name="GraphZero" Stroke="#B8C5D5" StrokeThickness="1"/>
     <Path Name="GraphGreen" Stroke="#50E3A4" StrokeThickness="1.2"/>
     <Path Name="GraphRed" Stroke="#FF6B7A" StrokeThickness="1.2"/>
     <Path Name="GraphNeutral" Stroke="White" StrokeThickness="1.2"/>
    </Canvas>
    <TextBlock Name="GraphScale" HorizontalAlignment="Left" VerticalAlignment="Top" FontSize="9" Foreground="#C7D1DF"/>
    <TextBlock Name="GraphNoData" Text="НЕТ ДАННЫХ" FontSize="11" Foreground="#C7D1DF" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
   </Grid>
   <DockPanel Grid.Row="2"><TextBlock Text="0%" FontSize="9" Foreground="#C7D1DF"/><TextBlock Text="100%" FontSize="9" Foreground="#C7D1DF" HorizontalAlignment="Right"/></DockPanel>
  </Grid>
 </Border>
</Window>
'@
$script:graphWindow=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $graphXaml))
$window.Add_Loaded({ $script:graphWindow.Owner=$window })
$script:graphControls=@{}
@('GraphBackground','GraphFinal','GraphCanvas','GraphZero','GraphGreen','GraphRed','GraphNeutral','GraphScale','GraphNoData') | ForEach-Object { $script:graphControls[$_]=$script:graphWindow.FindName($_) }
$script:drawnGraph=$null
$script:lastGraphWidth=0; $script:lastGraphHeight=0
function Set-DeltaGraphAppearance {
    if ($null -ne $script:graphWindow) { $script:graphControls.GraphBackground.Background=$controls.PanelBackground.Background }
}
function Set-DeltaGraphPosition {
    $handle=(New-Object Windows.Interop.WindowInteropHelper($window)).Handle
    $bounds=[Windows.Forms.Screen]::FromHandle($handle).WorkingArea
    $source=[Windows.PresentationSource]::FromVisual($window)
    if ($null -ne $source -and $null -ne $source.CompositionTarget) {
        $matrix=$source.CompositionTarget.TransformFromDevice
        $origin=$matrix.Transform((New-Object Windows.Point($bounds.Left,$bounds.Top)))
        $size=$matrix.Transform((New-Object Windows.Vector($bounds.Width,$bounds.Height)))
        $placement=[AccOverlay.DeltaGraphLayout]::Place($window.Left,$window.Top,$window.ActualWidth,$window.ActualHeight,$origin.X,$origin.Y,$size.X,$size.Y)
    } else { $placement=[AccOverlay.DeltaGraphLayout]::Place($window.Left,$window.Top,$window.Width,$window.Height,$bounds.Left,$bounds.Top,$bounds.Width,$bounds.Height) }
    if ($placement.Visible) {
        $script:graphWindow.Left=$placement.Left; $script:graphWindow.Top=$placement.Top
        $script:graphWindow.Width=$placement.Width; $script:graphWindow.Height=$placement.Height
    }
    return $placement.Visible
}
function Update-DeltaGraphView($display) {
    if ($null -eq $display -or -not [AccOverlay.DeltaGraphLayout]::ShouldShow($script:preferences.ShowDeltaGraph,$display.Holding,$display.Graph)) { $script:graphWindow.Hide(); return }
    Set-DeltaGraphAppearance
    if (-not $script:graphWindow.IsVisible) {
        if (-not (Set-DeltaGraphPosition)) { return }
        $script:graphWindow.Show()
        $script:graphWindow.UpdateLayout()
    }
    $width=$script:graphControls.GraphCanvas.ActualWidth; $height=$script:graphControls.GraphCanvas.ActualHeight
    if ([object]::ReferenceEquals($script:drawnGraph,$display.Graph) -and $width -eq $script:lastGraphWidth -and $height -eq $script:lastGraphHeight) { return }
    $data=$display.Graph; $script:drawnGraph=$data; $script:lastGraphWidth=$width; $script:lastGraphHeight=$height
    $script:graphControls.GraphFinal.Text=$(if ($data.Estimated -and $null -ne $data.FinalDelta) { '≈' } else { '' })+[AccOverlay.Timing]::Delta($data.FinalDelta)
    $script:graphControls.GraphFinal.Foreground=if ($null -eq $data.FinalDelta -or $data.FinalDelta -eq 0) { 'White' } elseif ($data.FinalDelta -lt 0) { '#50E3A4' } else { '#FF6B7A' }
    $script:graphWindow.ToolTip='Эталон: '+(Get-ComparisonLabel $data.ReferenceMode)+'. Прогресс трассы 0–100%; дельта в секундах.'
    $script:graphControls.GraphZero.X1=0; $script:graphControls.GraphZero.X2=$width
    $script:graphControls.GraphZero.Y1=$height/2; $script:graphControls.GraphZero.Y2=$height/2
    $script:graphControls.GraphNoData.Visibility=if ($data.Segments.Length -eq 0) { 'Visible' } else { 'Collapsed' }
    $script:graphControls.GraphZero.Visibility=if ($data.Segments.Length -eq 0) { 'Collapsed' } else { 'Visible' }
    $plot=[AccOverlay.DeltaGraphPlot]::Create($data,$width,$height)
    $script:graphControls.GraphScale.Text=if ($data.Segments.Length -gt 0) { '±'+$plot.ScaleSeconds.ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)+' с' } else { '' }
    foreach ($colour in @('Green','Red','Neutral')) {
        $path=$plot.$colour
        $script:graphControls[('Graph'+$colour)].Data=if ([string]::IsNullOrWhiteSpace($path)) { $null } else { [Windows.Media.Geometry]::Parse($path) }
    }
}
$window.Add_LocationChanged({ if ($script:graphWindow.IsVisible) { if (-not (Set-DeltaGraphPosition)) { $script:graphWindow.Hide() } } })
$window.Add_SizeChanged({ if ($script:graphWindow.IsVisible) { [void](Set-DeltaGraphPosition) } })
