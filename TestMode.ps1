# A local control panel for synthetic telemetry. No ACC connection is opened.
[xml]$testXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="ACC Sectors — тест без игры" Width="440" SizeToContent="Height" ResizeMode="NoResize" Background="#141820" Foreground="White" FontFamily="Segoe UI" FontSize="14" Topmost="True">
 <StackPanel Margin="18">
  <TextBlock Text="ТЕСТ БЕЗ ACC" FontSize="18" FontWeight="SemiBold"/>
  <TextBlock Text="Круг за 3 секунды → результат и график на 5 секунд. Используется настоящий расчёт оверлея." TextWrapping="Wrap" Margin="0,8,0,14"/>
  <ComboBox Name="ScenarioChoice" Foreground="Black" SelectedIndex="6">
   <ComboBoxItem Tag="Normal" Content="Обычный круг — зелёные и красные участки"/>
   <ComboBoxItem Tag="Record" Content="Новый личный рекорд"/>
   <ComboBoxItem Tag="Invalid" Content="Недействительный быстрый круг"/>
   <ComboBoxItem Tag="MissingPackets" Content="Пропуски пакетов — разрыв линии"/>
   <ComboBoxItem Tag="PartialReference" Content="Прошлый круг записан частично"/>
   <ComboBoxItem Tag="NoData" Content="Нет точек прошлого круга"/>
   <ComboBoxItem Tag="Random" Content="Случайные круги — каждый раз новый результат"/>
  </ComboBox>
  <Button Name="RepeatScenario" Content="Показать финиш сейчас" Margin="0,12,0,6" Padding="8"/>
  <Button Name="DriveLap" Content="Проехать следующий круг за 3 секунды" Margin="0,0,0,6" Padding="8"/>
  <CheckBox Name="AutoRunToggle" Content="Повторять автоматически" IsChecked="True" Foreground="White" Margin="0,8,0,12"/>
  <Button Name="ResetSession" Content="Сбросить сессию и скрыть график" Padding="8"/>
  <TextBlock Name="TestStatus" TextWrapping="Wrap" Margin="0,12,0,8" FontSize="12"/>
  <TextBlock Text="График включён для теста. Переключатели и затемнение проверяйте через ⚙ Настройки основного окна. Тестовые настройки хранятся отдельно от игровых. Закрытие этой панели завершает тест." TextWrapping="Wrap" FontSize="12" Foreground="#C7D1DF"/>
 </StackPanel>
</Window>
'@
$script:testWindow=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $testXaml))
$script:testControls=@{}
@('ScenarioChoice','RepeatScenario','DriveLap','AutoRunToggle','ResetSession','TestStatus') | ForEach-Object { $script:testControls[$_]=$script:testWindow.FindName($_) }
function Restart-TestScenario {
    $script:testDrive.Restart([string]$script:testControls.ScenarioChoice.SelectedItem.Tag)
    $script:testDrive.AutoRun=[bool]$script:testControls.AutoRunToggle.IsChecked
}
$script:testControls.ScenarioChoice.Add_SelectionChanged({ Restart-TestScenario })
$script:testControls.RepeatScenario.Add_Click({ Restart-TestScenario })
$script:testControls.DriveLap.Add_Click({ $script:testDrive.StartLap() })
$script:testControls.AutoRunToggle.Add_Click({ $script:testDrive.AutoRun=[bool]$script:testControls.AutoRunToggle.IsChecked })
$script:testControls.ResetSession.Add_Click({ $script:testDrive.ResetSession(); $script:testControls.AutoRunToggle.IsChecked=$false })
Restart-TestScenario
$script:testClosing=$false
$window.Add_Closing({ $script:testClosing=$true })
$script:testWindow.Add_Closed({ if (-not $script:testClosing) { $window.Close() } })
$window.Add_Loaded({ $script:testWindow.Owner=$window; $script:testWindow.Left=$window.Left; $script:testWindow.Top=$window.Top+$window.ActualHeight+12; $script:testWindow.Show() })
