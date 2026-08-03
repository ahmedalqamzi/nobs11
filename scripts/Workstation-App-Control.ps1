#requires -Version 7.2
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$SmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$optionalManager = Join-Path $PSScriptRoot 'Manage-OptionalApps.ps1'
$installedManager = Join-Path $PSScriptRoot 'Manage-InstalledApps.ps1'
$startupManager = Join-Path $PSScriptRoot 'Manage-UserStartup.ps1'
$catalogPath = Join-Path $projectRoot 'config\optional-apps.json'
$required = @($optionalManager, $installedManager, $startupManager, $catalogPath)
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missing.Count -gt 0) { throw "App Control is incomplete: $($missing -join ', ')" }

$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$catalogByName = @{}
foreach ($app in $catalog.apps) { $catalogByName[[string]$app.name] = $app }
$pwshPath = (Get-Process -Id $PID).Path

function Invoke-ControlScript {
    param(
        [Parameter(Mandatory)][string]$Script,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pwshPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $Script) + $Arguments) {
        [void]$startInfo.ArgumentList.Add([string]$argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    $errorTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = $outputTask.GetAwaiter().GetResult().Trim()
        Error = $errorTask.GetAwaiter().GetResult().Trim()
    }
}

function Convert-JsonArray {
    param([string]$Json)
    if (-not $Json) { return @() }
    return @($Json | ConvertFrom-Json)
}

if ($SelfTest) {
    $installedResult = Invoke-ControlScript $installedManager @('-Action', 'Audit', '-Json')
    $managedResult = Invoke-ControlScript $optionalManager @('-Action', 'Audit', '-Json')
    $startupResult = Invoke-ControlScript $startupManager @('-Action', 'Audit', '-Json')
    foreach ($result in @($installedResult, $managedResult, $startupResult)) {
        if ($result.ExitCode -ne 0) { throw "App Control data audit failed: $($result.Error) $($result.Output)" }
    }
    $installed = @(Convert-JsonArray $installedResult.Output)
    $managed = @(Convert-JsonArray $managedResult.Output)
    $startup = @(Convert-JsonArray $startupResult.Output)
    [ordered]@{
        Status = 'pass'
        InstalledApps = $installed.Count
        ManagedApps = $managed.Count
        StartupItems = $startup.Count
        Runtime = $projectRoot
    } | ConvertTo-Json
    return
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="App Control" Width="1080" Height="720" MinWidth="900" MinHeight="600"
        WindowStartupLocation="CenterScreen" Background="#202020" Foreground="#F3F3F3"
        FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <SolidColorBrush x:Key="WindowBrush" Color="#202020"/>
    <SolidColorBrush x:Key="SidebarBrush" Color="#181818"/>
    <SolidColorBrush x:Key="SurfaceBrush" Color="#292929"/>
    <SolidColorBrush x:Key="HoverBrush" Color="#333333"/>
    <SolidColorBrush x:Key="SelectedBrush" Color="#3A3A3A"/>
    <SolidColorBrush x:Key="BorderBrush" Color="#414141"/>
    <SolidColorBrush x:Key="TextBrush" Color="#F3F3F3"/>
    <SolidColorBrush x:Key="SecondaryBrush" Color="#B8B8B8"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#60CDFF"/>
    <SolidColorBrush x:Key="DangerBrush" Color="#FF99A4"/>

    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
    </Style>
    <Style x:Key="NavButton" TargetType="Button">
      <Setter Property="Height" Value="42"/>
      <Setter Property="Margin" Value="8,2"/>
      <Setter Property="Padding" Value="14,0"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Border" Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Border" Property="Background" Value="{StaticResource HoverBrush}"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Border" Property="Opacity" Value="0.75"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ActionButton" TargetType="Button">
      <Setter Property="Height" Value="34"/>
      <Setter Property="MinWidth" Value="92"/>
      <Setter Property="Padding" Value="14,0"/>
      <Setter Property="Margin" Value="8,0,0,0"/>
      <Setter Property="Background" Value="#353535"/>
      <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
      <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Border" Property="Background" Value="#404040"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Border" Property="Opacity" Value="0.75"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.38"/><Setter Property="Cursor" Value="Arrow"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ActionButton}">
      <Setter Property="Foreground" Value="{StaticResource DangerBrush}"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Height" Value="34"/>
      <Setter Property="Padding" Value="10,5"/>
      <Setter Property="Background" Value="#2B2B2B"/>
      <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
      <Setter Property="CaretBrush" Value="{StaticResource TextBrush}"/>
      <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="DataGrid">
      <Setter Property="Background" Value="{StaticResource WindowBrush}"/>
      <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
      <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="GridLinesVisibility" Value="Horizontal"/>
      <Setter Property="HorizontalGridLinesBrush" Value="#343434"/>
      <Setter Property="RowBackground" Value="{StaticResource WindowBrush}"/>
      <Setter Property="AlternatingRowBackground" Value="#232323"/>
      <Setter Property="HeadersVisibility" Value="Column"/>
      <Setter Property="AutoGenerateColumns" Value="False"/>
      <Setter Property="CanUserAddRows" Value="False"/>
      <Setter Property="CanUserDeleteRows" Value="False"/>
      <Setter Property="CanUserResizeRows" Value="False"/>
      <Setter Property="SelectionMode" Value="Single"/>
      <Setter Property="SelectionUnit" Value="FullRow"/>
      <Setter Property="RowHeaderWidth" Value="0"/>
      <Setter Property="RowHeight" Value="38"/>
      <Setter Property="ColumnHeaderHeight" Value="34"/>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="#252525"/>
      <Setter Property="Foreground" Value="{StaticResource SecondaryBrush}"/>
      <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="Padding" Value="10,0"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="10,0"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#3A3A3A"/>
          <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="DataGridRow">
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="#3A3A3A"/></Trigger>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#303030"/></Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="196"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Border Grid.Column="0" Background="{StaticResource SidebarBrush}" BorderBrush="#303030" BorderThickness="0,0,1,0">
      <DockPanel>
        <StackPanel DockPanel.Dock="Top" Margin="18,22,18,18">
          <TextBlock Text="App Control" FontSize="20" FontWeight="SemiBold"/>
          <TextBlock Text="Workstation" Foreground="{StaticResource SecondaryBrush}" FontSize="12" Margin="0,3,0,0"/>
        </StackPanel>
        <StackPanel DockPanel.Dock="Top">
          <Button x:Name="NavApps" Style="{StaticResource NavButton}" Content="Installed apps"/>
          <Button x:Name="NavStartup" Style="{StaticResource NavButton}" Content="Startup"/>
          <Button x:Name="NavProcesses" Style="{StaticResource NavButton}" Content="Processes"/>
        </StackPanel>
        <StackPanel DockPanel.Dock="Bottom" Margin="20,0,20,20">
          <Separator Background="#343434" Margin="0,0,0,14"/>
          <TextBlock Text="Runs only while this window is open." Foreground="{StaticResource SecondaryBrush}" FontSize="11" TextWrapping="Wrap"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <Grid Grid.Column="1" Margin="28,24,28,16">
      <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="28"/></Grid.RowDefinitions>

      <Grid x:Name="AppsPage" Grid.Row="0">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="0,0,0,18">
          <TextBlock Text="Installed apps" FontSize="28" FontWeight="Light"/>
          <TextBlock Text="Search, inspect, disable managed background activity, or run an app's registered uninstaller." Foreground="{StaticResource SecondaryBrush}" Margin="0,6,0,0"/>
        </StackPanel>
        <Grid Grid.Row="1" Margin="0,0,0,12">
          <Grid.ColumnDefinitions><ColumnDefinition Width="340"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <TextBox x:Name="AppSearch" Grid.Column="0" ToolTip="Search name, publisher, or source"/>
          <TextBlock x:Name="AppCount" Grid.Column="2" Foreground="{StaticResource SecondaryBrush}" VerticalAlignment="Center"/>
        </Grid>
        <DataGrid x:Name="AppsGrid" Grid.Row="2">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="2*"/>
            <DataGridTextColumn Header="Publisher" Binding="{Binding Publisher}" Width="1.35*"/>
            <DataGridTextColumn Header="Version" Binding="{Binding Version}" Width="0.8*"/>
            <DataGridTextColumn Header="Type" Binding="{Binding Source}" Width="0.8*"/>
            <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="0.9*"/>
          </DataGrid.Columns>
        </DataGrid>
        <Border Grid.Row="3" Background="{StaticResource SurfaceBrush}" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" CornerRadius="4" Padding="14" Margin="0,12,0,0">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
              <TextBlock x:Name="AppDetailTitle" Text="Select an app" FontWeight="SemiBold"/>
              <TextBlock x:Name="AppDetailText" Text="App details and available actions will appear here." Foreground="{StaticResource SecondaryBrush}" FontSize="12" Margin="0,4,0,0" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
              <Button x:Name="RefreshApps" Style="{StaticResource ActionButton}" Content="Refresh"/>
              <Button x:Name="DisableApp" Style="{StaticResource ActionButton}" Content="Disable background" IsEnabled="False"/>
              <Button x:Name="UninstallApp" Style="{StaticResource DangerButton}" Content="Uninstall" IsEnabled="False"/>
            </StackPanel>
          </Grid>
        </Border>
      </Grid>

      <Grid x:Name="StartupPage" Grid.Row="0" Visibility="Collapsed">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="0,0,0,18">
          <TextBlock Text="Startup" FontSize="28" FontWeight="Light"/>
          <TextBlock Text="Reversible control for startup entries. Disabled items are retained locally so they can be restored." Foreground="{StaticResource SecondaryBrush}" Margin="0,6,0,0"/>
        </StackPanel>
        <Grid Grid.Row="1" Margin="0,0,0,12">
          <Grid.ColumnDefinitions><ColumnDefinition Width="340"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <TextBox x:Name="StartupSearch" Grid.Column="0" ToolTip="Search startup items"/>
          <TextBlock x:Name="StartupCount" Grid.Column="2" Foreground="{StaticResource SecondaryBrush}" VerticalAlignment="Center"/>
        </Grid>
        <DataGrid x:Name="StartupGrid" Grid.Row="2">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="1.4*"/>
            <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="0.65*"/>
            <DataGridTextColumn Header="Source" Binding="{Binding Source}" Width="1.2*"/>
            <DataGridTextColumn Header="Command or path" Binding="{Binding Command}" Width="2*"/>
          </DataGrid.Columns>
        </DataGrid>
        <Border Grid.Row="3" Background="{StaticResource SurfaceBrush}" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" CornerRadius="4" Padding="14" Margin="0,12,0,0">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel>
              <TextBlock x:Name="StartupDetailTitle" Text="Select a startup item" FontWeight="SemiBold"/>
              <TextBlock x:Name="StartupDetailText" Text="Nothing is changed until you confirm an action." Foreground="{StaticResource SecondaryBrush}" FontSize="12" Margin="0,4,0,0" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
              <Button x:Name="RefreshStartup" Style="{StaticResource ActionButton}" Content="Refresh"/>
              <Button x:Name="ToggleStartup" Style="{StaticResource ActionButton}" Content="Disable" IsEnabled="False"/>
            </StackPanel>
          </Grid>
        </Border>
      </Grid>

      <Grid x:Name="ProcessesPage" Grid.Row="0" Visibility="Collapsed">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="0,0,0,18">
          <TextBlock Text="Processes" FontSize="28" FontWeight="Light"/>
          <TextBlock Text="Current-session processes sorted by memory. Core Windows processes are shown but protected from termination." Foreground="{StaticResource SecondaryBrush}" Margin="0,6,0,0"/>
        </StackPanel>
        <Grid Grid.Row="1" Margin="0,0,0,12">
          <Grid.ColumnDefinitions><ColumnDefinition Width="340"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <TextBox x:Name="ProcessSearch" Grid.Column="0" ToolTip="Search processes"/>
          <TextBlock x:Name="ProcessCount" Grid.Column="2" Foreground="{StaticResource SecondaryBrush}" VerticalAlignment="Center"/>
        </Grid>
        <DataGrid x:Name="ProcessesGrid" Grid.Row="2">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Process" Binding="{Binding Name}" Width="1.5*"/>
            <DataGridTextColumn Header="PID" Binding="{Binding Id}" Width="0.6*"/>
            <DataGridTextColumn Header="Memory" Binding="{Binding Memory}" Width="0.75*"/>
            <DataGridTextColumn Header="Publisher" Binding="{Binding Publisher}" Width="1.8*"/>
            <DataGridTextColumn Header="Control" Binding="{Binding Control}" Width="0.8*"/>
          </DataGrid.Columns>
        </DataGrid>
        <Border Grid.Row="3" Background="{StaticResource SurfaceBrush}" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" CornerRadius="4" Padding="14" Margin="0,12,0,0">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel>
              <TextBlock x:Name="ProcessDetailTitle" Text="Select a process" FontWeight="SemiBold"/>
              <TextBlock x:Name="ProcessDetailText" Text="Ending a process can discard unsaved work." Foreground="{StaticResource SecondaryBrush}" FontSize="12" Margin="0,4,0,0"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
              <Button x:Name="RefreshProcesses" Style="{StaticResource ActionButton}" Content="Refresh"/>
              <Button x:Name="EndProcess" Style="{StaticResource DangerButton}" Content="End process" IsEnabled="False"/>
            </StackPanel>
          </Grid>
        </Border>
      </Grid>

      <TextBlock x:Name="StatusText" Grid.Row="1" Text="Ready" Foreground="{StaticResource SecondaryBrush}" FontSize="11" VerticalAlignment="Bottom"/>
    </Grid>
  </Grid>
</Window>
'@

$reader = [Xml.XmlNodeReader]::new([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$names = @(
    'NavApps','NavStartup','NavProcesses','AppsPage','StartupPage','ProcessesPage','StatusText',
    'AppSearch','AppCount','AppsGrid','AppDetailTitle','AppDetailText','RefreshApps','DisableApp','UninstallApp',
    'StartupSearch','StartupCount','StartupGrid','StartupDetailTitle','StartupDetailText','RefreshStartup','ToggleStartup',
    'ProcessSearch','ProcessCount','ProcessesGrid','ProcessDetailTitle','ProcessDetailText','RefreshProcesses','EndProcess'
)
$ui = @{}
foreach ($name in $names) { $ui[$name] = $window.FindName($name) }

$script:allApps = @()
$script:allStartup = @()
$script:allProcesses = @()
$script:managedState = @{}
$script:refreshErrors = @{}
$script:currentPage = 'Apps'
$selectedBrush = $window.Resources['SelectedBrush']
$transparentBrush = [Windows.Media.Brushes]::Transparent

function Set-Status {
    param([Parameter(Mandatory)][string]$Text, [switch]$Busy)
    $ui.StatusText.Text = $Text
    [Windows.Automation.AutomationProperties]::SetHelpText($ui.StatusText, '')
    $window.Cursor = if ($Busy) { [Windows.Input.Cursors]::Wait } else { [Windows.Input.Cursors]::Arrow }
    [Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)
}

function Show-Error {
    param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)]$Result)
    $detail = @($Result.Error, $Result.Output) | Where-Object { $_ } | Select-Object -First 1
    if (-not $detail) { $detail = "The action exited with code $($Result.ExitCode)." }
    [Windows.MessageBox]::Show($window, [string]$detail, $Title, 'OK', 'Error') | Out-Null
}

function Show-Page {
    param([Parameter(Mandatory)][ValidateSet('Apps','Startup','Processes')][string]$Page)
    $script:currentPage = $Page
    foreach ($entry in @{
        Apps = @{ Page = $ui.AppsPage; Nav = $ui.NavApps }
        Startup = @{ Page = $ui.StartupPage; Nav = $ui.NavStartup }
        Processes = @{ Page = $ui.ProcessesPage; Nav = $ui.NavProcesses }
    }.GetEnumerator()) {
        $active = $entry.Key -eq $Page
        $entry.Value.Page.Visibility = if ($active) { 'Visible' } else { 'Collapsed' }
        $entry.Value.Nav.Background = if ($active) { $selectedBrush } else { $transparentBrush }
        $entry.Value.Nav.FontWeight = if ($active) { 'SemiBold' } else { 'Normal' }
    }
}

function Apply-AppFilter {
    $needle = $ui.AppSearch.Text.Trim()
    $filtered = @(
        if ($needle) {
            $script:allApps | Where-Object { $_.Name -like "*$needle*" -or $_.Publisher -like "*$needle*" -or $_.Source -like "*$needle*" }
        }
        else { $script:allApps }
    )
    $ui.AppsGrid.ItemsSource = $filtered
    $ui.AppCount.Text = "$($filtered.Count) apps"
}

function Apply-StartupFilter {
    $needle = $ui.StartupSearch.Text.Trim()
    $filtered = @(
        if ($needle) {
            $script:allStartup | Where-Object { $_.Name -like "*$needle*" -or $_.Source -like "*$needle*" -or $_.Command -like "*$needle*" }
        }
        else { $script:allStartup }
    )
    $ui.StartupGrid.ItemsSource = $filtered
    $ui.StartupCount.Text = "$($filtered.Count) items"
}

function Apply-ProcessFilter {
    $needle = $ui.ProcessSearch.Text.Trim()
    $filtered = @(
        if ($needle) {
            $script:allProcesses | Where-Object { $_.Name -like "*$needle*" -or $_.Publisher -like "*$needle*" }
        }
        else { $script:allProcesses }
    )
    $ui.ProcessesGrid.ItemsSource = $filtered
    $ui.ProcessCount.Text = "$($filtered.Count) processes"
}

function Refresh-Apps {
    [void]$script:refreshErrors.Remove('Apps')
    Set-Status 'Reading installed applications…' -Busy
    try {
        $installedResult = Invoke-ControlScript $installedManager @('-Action','Audit','-Json')
        $managedResult = Invoke-ControlScript $optionalManager @('-Action','Audit','-Json')
        if ($installedResult.ExitCode -ne 0) { Show-Error 'Could not read installed apps' $installedResult; return }
        if ($managedResult.ExitCode -ne 0) { Show-Error 'Could not read managed state' $managedResult; return }
        $installed = @(Convert-JsonArray $installedResult.Output)
        $managed = @(Convert-JsonArray $managedResult.Output)
        $script:managedState = @{}
        foreach ($state in $managed) { $script:managedState[[string]$state.Name] = $state }
        $script:allApps = @(
            foreach ($app in $installed) {
                $status = 'Installed'
                $backgroundActive = $false
                if ($app.ManagedName -and $script:managedState.ContainsKey([string]$app.ManagedName)) {
                    $state = $script:managedState[[string]$app.ManagedName]
                    $backgroundActive = [bool]$state.BackgroundActive
                    if ([int]$state.Running -gt 0) { $status = 'Running' }
                    elseif ([int]$state.StartupEntries -gt 0) { $status = 'Starts with Windows' }
                    elseif ($backgroundActive) { $status = 'Background service active' }
                    else { $status = 'Background disabled' }
                }
                [pscustomobject]@{
                    Id = [string]$app.Id
                    Name = [string]$app.Name
                    Publisher = if ([string]$app.Publisher) { [string]$app.Publisher } else { 'Unknown publisher' }
                    Version = [string]$app.Version
                    Scope = [string]$app.Scope
                    Source = [string]$app.Source
                    CanUninstall = [bool]$app.CanUninstall
                    ManagedName = [string]$app.ManagedName
                    BackgroundActive = $backgroundActive
                    Status = $status
                }
            }
        )
        Apply-AppFilter
        $ui.AppsGrid.SelectedItem = $null
        Set-Status "Installed apps refreshed at $(Get-Date -Format 'HH:mm:ss')."
    }
    catch {
        $script:refreshErrors['Apps'] = $_.Exception.ToString()
        [Windows.MessageBox]::Show($window, $_.Exception.Message, 'Could not refresh installed apps', 'OK', 'Error') | Out-Null
        Set-Status 'Installed-app refresh failed.'
        [Windows.Automation.AutomationProperties]::SetHelpText($ui.StatusText, $script:refreshErrors['Apps'])
    }
}

function Refresh-Startup {
    [void]$script:refreshErrors.Remove('Startup')
    Set-Status 'Reading startup entries…' -Busy
    try {
        $result = Invoke-ControlScript $startupManager @('-Action','Audit','-Json')
        if ($result.ExitCode -ne 0) { Show-Error 'Could not read startup entries' $result; return }
        $script:allStartup = @(Convert-JsonArray $result.Output)
        Apply-StartupFilter
        $ui.StartupGrid.SelectedItem = $null
        Set-Status "Startup entries refreshed at $(Get-Date -Format 'HH:mm:ss')."
    }
    catch {
        $script:refreshErrors['Startup'] = $_.Exception.ToString()
        [Windows.MessageBox]::Show($window, $_.Exception.Message, 'Could not refresh startup entries', 'OK', 'Error') | Out-Null
        Set-Status 'Startup refresh failed.'
        [Windows.Automation.AutomationProperties]::SetHelpText($ui.StatusText, $script:refreshErrors['Startup'])
    }
}

function Refresh-Processes {
    [void]$script:refreshErrors.Remove('Processes')
    Set-Status 'Reading current-session processes…' -Busy
    try {
        $criticalNames = @('audiodg','csrss','dwm','explorer','fontdrvhost','lsass','services','sihost','smss','StartMenuExperienceHost','System','taskhostw','wininit','winlogon')
        $sessionId = (Get-Process -Id $PID).SessionId
        $cimProcesses = @(Get-CimInstance Win32_Process -Filter "SessionId=$sessionId" -ErrorAction SilentlyContinue)
        $script:allProcesses = @(
            foreach ($cim in $cimProcesses) {
                $process = Get-Process -Id $cim.ProcessId -ErrorAction SilentlyContinue
                if (-not $process) { continue }
                $rawName = $process.ProcessName
                $publisher = ''
                try { $publisher = [string]$process.MainModule.FileVersionInfo.CompanyName } catch {}
                $canStop = $process.Id -ne $PID -and $rawName -notin $criticalNames
                [pscustomobject]@{
                    Name = $rawName
                    Id = [int]$process.Id
                    Memory = ('{0:N0} MB' -f ($process.WorkingSet64 / 1MB))
                    MemoryBytes = [long]$process.WorkingSet64
                    Publisher = if ($publisher) { $publisher } else { 'Unknown publisher' }
                    Control = if ($canStop) { 'Available' } else { 'Protected' }
                    CanStop = $canStop
                }
            }
        ) | Sort-Object MemoryBytes -Descending
        Apply-ProcessFilter
        $ui.ProcessesGrid.SelectedItem = $null
        Set-Status "Processes refreshed at $(Get-Date -Format 'HH:mm:ss')."
    }
    catch {
        $script:refreshErrors['Processes'] = $_.Exception.ToString()
        [Windows.MessageBox]::Show($window, $_.Exception.Message, 'Could not refresh processes', 'OK', 'Error') | Out-Null
        Set-Status 'Process refresh failed.'
        [Windows.Automation.AutomationProperties]::SetHelpText($ui.StatusText, $script:refreshErrors['Processes'])
    }
}

$ui.AppsGrid.Add_SelectionChanged({
    $app = $ui.AppsGrid.SelectedItem
    if (-not $app) {
        $ui.AppDetailTitle.Text = 'Select an app'
        $ui.AppDetailText.Text = 'App details and available actions will appear here.'
        $ui.DisableApp.Content = 'Disable background'
        $ui.DisableApp.IsEnabled = $false
        $ui.UninstallApp.IsEnabled = $false
        return
    }
    $ui.AppDetailTitle.Text = $app.Name
    $managedText = if ($app.ManagedName) { " • $($app.Status.ToLowerInvariant())" } else { '' }
    $ui.AppDetailText.Text = "$($app.Publisher) • $($app.Version) • $($app.Scope)$managedText"
    $ui.DisableApp.Content = if ($app.ManagedName -and -not $app.BackgroundActive) { 'Background disabled' } else { 'Disable background' }
    $ui.DisableApp.IsEnabled = [bool]$app.ManagedName -and [bool]$app.BackgroundActive
    $ui.UninstallApp.IsEnabled = [bool]$app.CanUninstall
})

$ui.StartupGrid.Add_SelectionChanged({
    $item = $ui.StartupGrid.SelectedItem
    if (-not $item) {
        $ui.StartupDetailTitle.Text = 'Select a startup item'
        $ui.StartupDetailText.Text = 'Nothing is changed until you confirm an action.'
        $ui.ToggleStartup.IsEnabled = $false
        return
    }
    $ui.StartupDetailTitle.Text = $item.Name
    $ui.StartupDetailText.Text = "$($item.Source) • $($item.Command)"
    $ui.ToggleStartup.Content = if ($item.Status -eq 'Enabled') { 'Disable' } else { 'Restore' }
    $ui.ToggleStartup.IsEnabled = $true
})

$ui.ProcessesGrid.Add_SelectionChanged({
    $process = $ui.ProcessesGrid.SelectedItem
    if (-not $process) {
        $ui.ProcessDetailTitle.Text = 'Select a process'
        $ui.ProcessDetailText.Text = 'Ending a process can discard unsaved work.'
        $ui.EndProcess.IsEnabled = $false
        return
    }
    $ui.ProcessDetailTitle.Text = "$($process.Name)  (PID $($process.Id))"
    $ui.ProcessDetailText.Text = "$($process.Memory) • $($process.Publisher) • $($process.Control)"
    $ui.EndProcess.IsEnabled = [bool]$process.CanStop
})

$ui.NavApps.Add_Click({ Show-Page Apps })
$ui.NavStartup.Add_Click({ Show-Page Startup; if ($script:allStartup.Count -eq 0) { Refresh-Startup } })
$ui.NavProcesses.Add_Click({ Show-Page Processes; if ($script:allProcesses.Count -eq 0) { Refresh-Processes } })
$ui.AppSearch.Add_TextChanged({ Apply-AppFilter })
$ui.StartupSearch.Add_TextChanged({ Apply-StartupFilter })
$ui.ProcessSearch.Add_TextChanged({ Apply-ProcessFilter })
$ui.RefreshApps.Add_Click({ Refresh-Apps })
$ui.RefreshStartup.Add_Click({ Refresh-Startup })
$ui.RefreshProcesses.Add_Click({ Refresh-Processes })

$ui.DisableApp.Add_Click({
    $app = $ui.AppsGrid.SelectedItem
    if (-not $app -or -not $app.ManagedName -or -not $app.BackgroundActive) { return }
    $message = "Disable startup and current background activity for $($app.Name)?`n`nThe application remains installed and can still run when you open it or when another app explicitly launches it. Automatic cataloged services are set to manual and can request administrator approval."
    if ([Windows.MessageBox]::Show($window, $message, 'Confirm background change', 'YesNo', 'Warning') -ne 'Yes') { return }
    Set-Status "Disabling $($app.Name)…" -Busy
    $result = Invoke-ControlScript $optionalManager @('-Action','DisableStartup','-Name',$app.ManagedName,'-Force')
    $failed = $result.ExitCode -ne 0
    if ($failed) { Show-Error 'Background action did not complete' $result }
    Refresh-Apps
    Refresh-Startup
    if ($failed) { Set-Status "Could not fully disable background activity for $($app.Name)." }
    else { Set-Status "Background and startup activity disabled for $($app.Name)." }
})

$ui.UninstallApp.Add_Click({
    $app = $ui.AppsGrid.SelectedItem
    if (-not $app -or -not $app.CanUninstall) { return }
    $warning = if ($app.ManagedName -and $catalogByName.ContainsKey([string]$app.ManagedName)) { "`n`n$($catalogByName[[string]$app.ManagedName].warning)" } else { '' }
    $message = "Uninstall $($app.Name)?`n`nPublisher: $($app.Publisher)`nType: $($app.Source)$warning`n`nWindows may request administrator approval."
    if ([Windows.MessageBox]::Show($window, $message, 'Confirm uninstall', 'YesNo', 'Warning') -ne 'Yes') { return }
    Set-Status "Uninstalling $($app.Name)…" -Busy
    $result = if ($app.ManagedName) {
        Invoke-ControlScript $optionalManager @('-Action','Uninstall','-Name',$app.ManagedName,'-Force')
    } else {
        Invoke-ControlScript $installedManager @('-Action','Uninstall','-Id',$app.Id,'-Force')
    }
    if ($result.ExitCode -ne 0) { Show-Error 'Uninstall did not complete' $result }
    Refresh-Apps
    Refresh-Startup
    Refresh-Processes
})

$ui.ToggleStartup.Add_Click({
    $item = $ui.StartupGrid.SelectedItem
    if (-not $item) { return }
    $action = if ($item.Status -eq 'Enabled') { 'Disable' } else { 'Enable' }
    $verb = if ($action -eq 'Disable') { 'disable' } else { 'restore' }
    if ([Windows.MessageBox]::Show($window, "Safely $verb $($item.Name)?", "Confirm $verb", 'YesNo', 'Question') -ne 'Yes') { return }
    Set-Status "$($verb.Substring(0,1).ToUpperInvariant())$($verb.Substring(1))ing $($item.Name)…" -Busy
    $result = Invoke-ControlScript $startupManager @('-Action',$action,'-Id',$item.Id,'-Force')
    if ($result.ExitCode -ne 0) { Show-Error 'Startup action did not complete' $result }
    Refresh-Startup
})

$ui.EndProcess.Add_Click({
    $selected = $ui.ProcessesGrid.SelectedItem
    if (-not $selected -or -not $selected.CanStop) { return }
    if ([Windows.MessageBox]::Show($window, "End $($selected.Name) (PID $($selected.Id))?`n`nUnsaved work in this process will be lost.", 'Confirm end process', 'YesNo', 'Warning') -ne 'Yes') { return }
    try {
        $current = Get-Process -Id $selected.Id -ErrorAction Stop
        if ($current.ProcessName -ne $selected.Name) { throw 'The selected PID now belongs to a different process. Refresh and try again.' }
        Stop-Process -Id $selected.Id -Force -ErrorAction Stop
        Set-Status "Ended $($selected.Name)."
    }
    catch { [Windows.MessageBox]::Show($window, $_.Exception.Message, 'Could not end process', 'OK', 'Error') | Out-Null }
    Refresh-Processes
})

Show-Page Apps
if ($SmokeTest) {
    Refresh-Apps
    Refresh-Startup
    Refresh-Processes
    if ($script:refreshErrors.Count -gt 0) {
        throw "App Control smoke test refresh failed: $($script:refreshErrors.Values -join ' | ')"
    }
    [ordered]@{
        Status = 'pass'
        InstalledRows = $ui.AppsGrid.Items.Count
        StartupRows = $ui.StartupGrid.Items.Count
        ProcessRows = $ui.ProcessesGrid.Items.Count
        ExternalSettingsLinks = 0
    } | ConvertTo-Json
    $window.Close()
    return
}

$window.Add_ContentRendered({ Refresh-Apps })
[void]$window.ShowDialog()
