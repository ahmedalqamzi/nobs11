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
        Title="NoBS11 Control" Width="1080" Height="720" MinWidth="900" MinHeight="600"
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
          <TextBlock Text="NoBS11 Control" FontSize="20" FontWeight="SemiBold"/>
          <TextBlock Text="Runs on demand" Foreground="{StaticResource SecondaryBrush}" FontSize="12" Margin="0,3,0,0"/>
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
          <TextBlock Text="Reversible control for startup entries. Disabled items are retained locally so they can be restored." FÛMü¶‰žËkºwµç]¥¹‘½ÝÌ¹%¹ÁÕÐ¹ÕÉÍ½ÉÍtèé]…¥Ðô•±Í”ìm]¥¹‘½ÝÌ¹%¹ÁÕÐ¹ÕÉÍ½ÉÍtèéÉÉ½Üô(€€€m]¥¹‘½ÝÌ¹Q¡É•…‘¥¹œ¹¥ÍÁ…Ñ¡•ÉtèéÕÉÉ•¹Ñ¥ÍÁ…Ñ¡•È¹%¹Ù½­”¡mÑ¥½¹uíô°m]¥¹‘½ÝÌ¹Q¡É•…‘¥¹œ¹¥ÍÁ…Ñ¡•ÉAÉ¥½É¥Ñåtèé	…­É½Õ¹¤)ô()™Õ¹Ñ¥½¸M¡½ÜµÉÉ½Èì(€€€Á…É…´¡mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘Q¥Ñ±”°mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥t‘I•ÍÕ±Ð¤(€€€€‘‘•Ñ…¥°€ô  ‘I•ÍÕ±Ð¹ÉÉ½È°€‘I•ÍÕ±Ð¹=ÕÑÁÕÐ¤ð]¡•É”µ=‰©•Ðì€‘|ôðM•±•Ðµ=‰©•Ð€µ¥ÉÍÐ€Ä(€€€¥˜€ µ¹½Ð€‘‘•Ñ…¥°¤ì€‘‘•Ñ…¥°€ô€‰Q¡”…Ñ¥½¸•á¥Ñ•Ý¥Ñ ½‘”€ ‘I•ÍÕ±Ð¹á¥Ñ½‘”¤¸ˆô(€€€m]¥¹‘½ÝÌ¹5•ÍÍ…•	½átèéM¡½Ü ‘Ý¥¹‘½Ü°mÍÑÉ¥¹t‘‘•Ñ…¥°°€‘Q¥Ñ±”°€=,œ°€ÉÉ½Èœ¤ð=ÕÐµ9Õ±°)ô()™Õ¹Ñ¥½¸M¡½ÜµA…”ì(€€€Á…É…´¡mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umY…±¥‘…Ñ•M•Ð ÁÁÌœ°MÑ…ÉÑÕÀœ°AÉ½•ÍÍ•Ìœ¥umÍÑÉ¥¹t‘A…”¤(€€€€‘ÍÉ¥ÁÐéÕÉÉ•¹ÑA…”€ô€‘A…”(€€€™½É•… € ‘•¹ÑÉä¥¸ì(€€€€€€€ÁÁÌ€ôìA…”€ô€‘Õ¤¹ÁÁÍA…”ì9…Ø€ô€‘Õ¤¹9…ÙÁÁÌô(€€€€€€€MÑ…ÉÑÕÀ€ôìA…”€ô€‘Õ¤¹MÑ…ÉÑÕÁA…”ì9…Ø€ô€‘Õ¤¹9…ÙMÑ…ÉÑÕÀô(€€€€€€€AÉ½•ÍÍ•Ì€ôìA…”€ô€‘Õ¤¹AÉ½•ÍÍ•ÍA…”ì9…Ø€ô€‘Õ¤¹9…ÙAÉ½•ÍÍ•Ìô(€€€ô¹•Ñ¹Õµ•É…Ñ½È ¤¤ì(€€€€€€€€‘…Ñ¥Ù”€ô€‘•¹ÑÉä¹-•ä€µ•Ä€‘A…”(€€€€€€€€‘•¹ÑÉä¹Y…±Õ”¹A…”¹Y¥Í¥‰¥±¥Ñä€ô¥˜€ ‘…Ñ¥Ù”¤ì€Y¥Í¥‰±”œô•±Í”ì€½±±…ÁÍ•œô(€€€€€€€€‘•¹ÑÉä¹Y…±Õ”¹9…Ø¹	…­É½Õ¹€ô¥˜€ ‘…Ñ¥Ù”¤ì€‘Í•±•Ñ•‘	ÉÕÍ ô•±Í”ì€‘ÑÉ…¹ÍÁ…É•¹Ñ	ÉÕÍ ô(€€€€€€€€‘•¹ÑÉä¹Y…±Õ”¹9…Ø¹½¹Ñ]•¥¡Ð€ô¥˜€ ‘…Ñ¥Ù”¤ì€M•µ¥	½±œô•±Í”ì€9½Éµ…°œô(€€€ô)ô()™Õ¹Ñ¥½¸ÁÁ±äµÁÁ¥±Ñ•Èì(€€€€‘¹••‘±”€ô€‘Õ¤¹ÁÁM•…É ¹Q•áÐ¹QÉ¥´ ¤(€€€€‘™¥±Ñ•É•€ô  (€€€€€€€¥˜€ ‘¹••‘±”¤ì(€€€€€€€€€€€€‘ÍÉ¥ÁÐé…±±ÁÁÌð]¡•É”µ=‰©•Ðì€‘|¹9…µ”€µ±¥­”€ˆ¨‘¹••‘±”¨ˆ€µ½È€‘|¹AÕ‰±¥Í¡•È€µ±¥­”€ˆ¨‘¹••‘±”¨ˆ€µ½È€‘|¹M½ÕÉ”€µ±¥­”€ˆ¨‘¹••‘±”¨ˆô(€€€€€€€ô(€€€€€€€•±Í”ì€‘ÍÉ¥ÁÐé…±±ÁÁÌô(€€€€¤(€€€€‘Õ¤¹ÁÁÍÉ¥¹%Ñ•µÍM½ÕÉ”€ô€‘™¥±Ñ•É•(€€€€‘Õ¤¹ÁÁ½Õ¹Ð¹Q•áÐ€ô€ˆ ‘™¥±Ñ•É•¹½Õ¹Ð¤…ÁÁÌˆ)ô()™Õ¹Ñ¥½¸ÁÁ±äµMÑ…ÉÑÕÁ¥±Ñ•Èì(€€€€‘¹••‘±”€ô€‘Õ¤¹MÑ…ÉÑÕÁM•…É ¹Q•áÐ¹QÉ¥´ ¤(€€€€‘™¥±Ñ•É•€ô  (€€€€€€€¥˜€ ‘¹••‘±”¤ì(€€€€€€€€€€€€‘ÍÉ¥ÁÐé…±±MÑ…ÉÑÕÀð]¡•É”µ=‰©•Ðì€‘|¹9…µ”€µ±¥­”€ˆ¨‘¹••‘±”¨ˆ€µ½È€‘|¹M½ÕÉ”€µ±¥­”€ˆ¨‘¹••‘±”¨ˆ€µ½È€‘|¹½µµ…¹€µ±¥­”€ˆ¨‘¹••‘±”¨ˆô(€€€€€€€ô(€€€€€€€•±Í”ì€‘ÍÉ¥ÁÐé…±±MÑ…ÉÑÕÀô(€€€€¤(€€€€‘Õ¤¹MÑ…ÉÑÕÁÉ¥¹%Ñ•µÍM½ÕÉ”€ô€‘™¥±Ñ•É•(€€€€‘Õ¤¹MÑ…ÉÑÕÁ½Õ¹Ð¹Q•áÐ€ô€ˆ ‘™¥±Ñ•É•¹½Õ¹Ð¤¥Ñ•µÌˆ)ô()™Õ¹Ñ¥½¸ÁÁ±äµAÉ½•ÍÍ¥±Ñ•Èì(€€€€‘¹••‘±”€ô€‘Õ¤¹AÉ½•ÍÍM•…É ¹Q•áÐ¹QÉ¥´ ¤(€€€€‘™¥±Ñ•É•€ô  (€€€€€€€¥˜€ ‘¹••‘±”¤ì(€€€€€€€€€€€€‘ÍÉ¥ÁÐé…±±AÉ½•ÍÍ•Ìð]¡•É”µ=‰©•Ðì€‘|¹9…µ”€µ±¥­”€ˆ¨‘¹••‘±”¨ˆ€µ½È€‘|¹AÕ‰±¥Í¡•È€µ±¥­”€ˆ¨‘¹••‘±”¨ˆô(€€€€€€€ô(€€€€€€€•±Í”ì€‘ÍÉ¥ÁÐé…±±AÉ½•ÍÍ•Ìô(€€€€¤(€€€€‘Õ¤¹AÉ½•ÍÍ•ÍÉ¥¹%Ñ•µÍM½ÕÉ”€ô€‘™¥±Ñ•É•(€€€€‘Õ¤¹AÉ½•ÍÍ½Õ¹Ð¹Q•áÐ€ô€ˆ ‘™¥±Ñ•É•¹½Õ¹Ð¤ÁÉ½•ÍÍ•Ìˆ)ô()™Õ¹Ñ¥½¸I•™É•Í µÁÁÌì(€€€mÙ½¥‘t‘ÍÉ¥ÁÐéÉ•™É•Í¡ÉÉ½ÉÌ¹I•µ½Ù” ÁÁÌœ¤(€€€M•ÐµMÑ…ÑÕÌ€I•…‘¥¹œ¥¹ÍÑ…±±•…ÁÁ±¥…Ñ¥½¹ÏŠ˜œ€µ	ÕÍä(€€€ÑÉäì(€€€€€€€€‘¥¹ÍÑ…±±•‘I•ÍÕ±Ð€ô%¹Ù½­”µ½¹ÑÉ½±MÉ¥ÁÐ€‘¥¹ÍÑ…±±•‘5…¹…•È  œµÑ¥½¸œ°Õ‘¥Ðœ°œµ)Í½¸œ¤(€€€€€€€€‘µ…¹…•‘I•ÍÕ±Ð€ô%¹Ù½­”µ½¹ÑÉ½±MÉ¥ÁÐ€‘½ÁÑ¥½¹…±5…¹…•È  œµÑ¥½¸œ°Õ‘¥Ðœ°œµ)Í½¸œ¤(€€€€€€€¥˜€ ‘¥¹ÍÑ…±±•‘I•ÍÕ±Ð¹á¥Ñ½‘”€µ¹”€À¤ìM¡½ÜµÉÉ½È€½Õ±¹½ÐÉ•…¥¹ÍÑ…±±•…ÁÁÌœ€‘¥¹ÍÑ…±±•‘I•ÍÕ±ÐìÉ•ÑÕÉ¸ô(€€€€€€€¥˜€ ‘µ…¹…•‘I•ÍÕ±Ð¹á¥Ñ½‘”€µ¹”€À¤ìM¡½ÜµÉÉ½È€½Õ±¹½ÐÉ•…µ…¹…•ÍÑ…Ñ”œ€‘µ…¹…•‘I•ÍÕ±ÐìÉ•ÑÕÉ¸ô(€€€€€€€€‘¥¹ÍÑ…±±•€ô ¡½¹Ù•ÉÐµ)Í½¹ÉÉ…ä€‘¥¹ÍÑ…±±•‘I•ÍÕ±Ð¹=ÕÑÁÕÐ¤(€€€€€€€€‘µ…¹…•€ô ¡½¹Ù•ÉÐµ)Í½¹ÉÉ…ä€‘µ…¹…•‘I•ÍÕ±Ð¹=ÕÑÁÕÐ¤(€€€€€€€€‘ÍÉ¥ÁÐéµ…¹…•‘MÑ…Ñ”€ôíô(€€€€€€€™½É•… € ‘ÍÑ…Ñ”¥¸€‘µ…¹…•¤ì€‘ÍÉ¥ÁÐéµ…¹…•‘MÑ…Ñ•mmÍÑÉ¥¹t‘ÍÑ…Ñ”¹9…µ•t€ô€‘ÍÑ…Ñ”ô(€€€€€€€€‘ÍÉ¥ÁÐé…±±ÁÁÌ€ô  (€€€€€€€€€€€™½É•… € ‘…ÁÀ¥¸€‘¥¹ÍÑ…±±•¤ì(€€€€€€€€€€€€€€€€‘ÍÑ…ÑÕÌ€ô€%¹ÍÑ…±±•œ(€€€€€€€€€€€€€€€€‘‰…­É½Õ¹‘Ñ¥Ù”€ô€‘™…±Í”(€€€€€€€€€€€€€€€¥˜€ ‘…ÁÀ¹5…¹…•‘9…µ”€µ…¹€‘ÍÉ¥ÁÐéµ…¹…•‘MÑ…Ñ”¹½¹Ñ…¥¹Í-•ä¡mÍÑÉ¥¹t‘…ÁÀ¹5…¹…•‘9…µ”¤¤ì(€€€€€€€€€€€€€€€€€€€€‘ÍÑ…Ñ”€ô€‘ÍÉ¥ÁÐéµ…¹…•‘MÑ…Ñ•mmÍÑÉ¥¹t‘…ÁÀ¹5…¹…•‘9…µ•t(€€€€€€€€€€€€€€€€€€€€‘‰…­É½Õ¹‘Ñ¥Ù”€ôm‰½½±t‘ÍÑ…Ñ”¹	…­É½Õ¹‘Ñ¥Ù”(€€€€€€€€€€€€€€€€€€€¥˜€¡m¥¹Ñt‘ÍÑ…Ñ”¹IÕ¹¹¥¹œ€µÐ€À¤ì€‘ÍÑ…ÑÕÌ€ô€IÕ¹¹¥¹œœô(€€€€€€€€€€€€€€€€€€€•±Í•¥˜€¡m¥¹Ñt‘ÍÑ…Ñ”¹MÑ…ÉÑÕÁ¹ÑÉ¥•Ì€µÐ€À¤ì€‘ÍÑ…ÑÕÌ€ô€MÑ…ÉÑÌÝ¥Ñ ]¥¹‘½ÝÌœô(€€€€€€€€€€€€€€€€€€€•±Í•¥˜€ ‘‰…­É½Õ¹‘Ñ¥Ù”¤ì€‘ÍÑ…ÑÕÌ€ô€	…­É½Õ¹Í•ÉÙ¥”…Ñ¥Ù”œô(€€€€€€€€€€€€€€€€€€€•±Í”ì€‘ÍÑ…ÑÕÌ€ô€	…­É½Õ¹‘¥Í…‰±•œô(€€€€€€€€€€€€€€€ô(€€€€€€€€€€€€€€€mÁÍÕÍÑ½µ½‰©•Ñuì(€€€€€€€€€€€€€€€€€€€%€ômÍÑÉ¥¹t‘…ÁÀ¹%(€€€€€€€€€€€€€€€€€€€9…µ”€ômÍÑÉ¥¹t‘…ÁÀ¹9…µ”(€€€€€€€€€€€€€€€€€€€AÕ‰±¥Í¡•È€ô¥˜€¡mÍÑÉ¥¹t‘…ÁÀ¹AÕ‰±¥Í¡•È¤ìmÍÑÉ¥¹t‘…ÁÀ¹AÕ‰±¥Í¡•Èô•±Í”ì€U¹­¹½Ý¸ÁÕ‰±¥Í¡•Èœô(€€€€€€€€€€€€€€€€€€€Y•ÉÍ¥½¸€ômÍÑÉ¥¹t‘…ÁÀ¹Y•ÉÍ¥½¸(€€€€€€€€€€€€€€€€€€€M½Á”€ômÍÑÉ¥¹t‘…ÁÀ¹M½Á”(€€€€€€€€€€€€€€€€€€€M½ÕÉ”€ômÍÑÉ¥¹t‘…ÁÀ¹M½ÕÉ”(€€€€€€€€€€€€€€€€€€€…¹U¹¥¹ÍÑ…±°€ôm‰½½±t‘…ÁÀ¹…¹U¹¥¹ÍÑ…±°(€€€€€€€€€€€€€€€€€€€5…¹…•‘9…µ”€ômÍÑÉ¥¹t‘…ÁÀ¹5…¹…•‘9…µ”(€€€€€€€€€€€€€€€€€€€	…­É½Õ¹‘Ñ¥Ù”€ô€‘‰…­É½Õ¹‘Ñ¥Ù”(€€€€€€€€€€€€€€€€€€€MÑ…ÑÕÌ€ô€‘ÍÑ…ÑÕÌ(€€€€€€€€€€€€€€€ô(€€€€€€€€€€€ô(€€€€€€€€¤(€€€€€€€ÁÁ±äµÁÁ¥±Ñ•È(€€€€€€€€‘Õ¤¹ÁÁÍÉ¥¹M•±•Ñ•‘%Ñ•´€ô€‘¹Õ±°(€€€€€€€M•ÐµMÑ…ÑÕÌ€‰%¹ÍÑ…±±•…ÁÁÌÉ•™É•Í¡•…Ð€¡•Ðµ…Ñ”€µ½Éµ…Ð€! éµ´éÍÌœ¤¸ˆ(€€€ô(€€€…Ñ ì(€€€€€€€€‘ÍÉ¥ÁÐéÉ•™É•Í¡ÉÉ½ÉÍlÁÁÌt€ô€‘|¹á•ÁÑ¥½¸¹Q½MÑÉ¥¹œ ¤(€€€€€€€m]¥¹‘½ÝÌ¹5•ÍÍ…•	½átèéM¡½Ü ‘Ý¥¹‘½Ü°€‘|¹á•ÁÑ¥½¸¹5•ÍÍ…”°€½Õ±¹½ÐÉ•™É•Í ¥¹ÍÑ…±±•…ÁÁÌœ°€=,œ°€ÉÉ½Èœ¤ð=ÕÐµ9Õ±°(€€€€€€€M•ÐµMÑ…ÑÕÌ€%¹ÍÑ…±±•µ…ÁÀÉ•™É•Í ™…¥±•¸œ(€€€€€€€m]¥¹‘½ÝÌ¹ÕÑ½µ…Ñ¥½¸¹ÕÑ½µ…Ñ¥½¹AÉ½Á•ÉÑ¥•ÍtèéM•Ñ!•±ÁQ•áÐ ‘Õ¤¹MÑ…ÑÕÍQ•áÐ°€‘ÍÉ¥ÁÐéÉ•™É•Í¡ÉÉ½ÉÍlÁÁÌt¤(€€€ô)ô()™Õ¹Ñ¥½¸I•™É•Í µMÑ…ÉÑÕÀì(€€€mÙ½¥‘t‘ÍÉ¥ÁÐéÉ•™É•Í¡ÉÉ½ÉÌ¹I•µ½Ù” MÑ…ÉÑÕÀœ¤(€€€M•ÐµMÑ…ÑÕÌ€I•…‘¥¹œÍÑ…ÉÑÕÀ•¹ÑÉ¥•ÏŠ˜œ€µ	ÕÍä(€€€ÑÉäì(€€€€€€€€‘É•ÍÕ±Ð€ô%¹Ù½­”µ½¹ÑÉ½±MÉ¥ÁÐ€‘ÍÑ…ÉÑÕÁ5…¹…•È  œµÑ¥½¸œ°Õ‘¥Ðœ°œµ)Í½¸œ¤(€€€€€€€¥˜€ ‘É•ÍÕ±Ð¹á¥Ñ½‘”€µ¹”€À¤ìM¡½ÜµÉÉ½È€½Õ±¹½ÐÉ•…ÍÑ…ÉÑÕÀ•¹ÑÉ¥•Ìœ€‘É•ÍÕ±ÐìÉ•ÑÕÉ¸ô(€€€€€€€€‘ÍÉ¥ÁÐé…±±MÑ…ÉÑÕÀ€ô ¡½¹Ù•ÉÐµ)Í½¹ÉÉ…ä€‘É•ÍÕ±Ð¹=ÕÑÁÕÐ¤(€€€€€€€ÁÁ±äµMÑ…ÉÑÕÁ¥±Ñ•È(€€€€€€€€‘Õ¤¹MÑ…ÉÑÕÁÉ¥¹M•±•Ñ•‘%Ñ•´€ô€‘¹Õ±°(€€€€€€€M•ÐµMÑ…ÑÕÌ€‰MÑ…ÉÑÕÀ•¹ÑÉ¥•ÌÉ•™É•Í¡•…Ð€¡•Ðµ…Ñ”€µ½Éµ…Ð€! éµ´éÍÌœ¤¸ˆ(€€€ô(€€€…Ñ ì(€€€€€€€€‘ÍÉ¥ÁÐéÉ•™É•Í¡ÉÉ½ÉÍlMÑ…ÉÑÕÀt€ô€‘|¹á•ÁÑ¥½¸¹Q½MÑÉ¥¹œ ¤(€€€€€€€m]¥¹‘½ÝÌ¹5•ÍÍ…•	½átèéM¡½Ü ‘Ý¥¹‘½Ü°€‘|¹á•ÁÑ¥½¸¹5•ÍÍ…”°€½Õ±¹½ÐÉ•™É•Í ÍÑ…ÉÑÕÀ•¹ÑÉ¥•Ìœ°€=,œ°€ÉÉ½Èœ¤ð=ÕÐµ9Õ±°(€€€€€€€M•ÐµMÑ…ÑÕÌ€MÑ…ÉÑÕÀÉ•™É•Í ™…¥±•¸œ(€€€€€€€m]¥¹‘½ÝÌ¹ÕÑ½µ…Ñ¥½¸¹ÕÑ½µ…Ñ¥½¹AÉ½Á•ÉÑ¥•ÍtèéM•Ñ!•±ÁQ•áÐ ‘Õ¤¹MÑ…ÑÕÍQ•áÐ°€‘ÍÉ¥ÁÐéÉ•™É•Í¡ÉÉ½ÉÍlMÑ…ÉÑÕÀt¤(€€€ô)ô()™Õ¹Ñ¥½¸I•™É•Í µAÉ½•ÍÍ•Ìì(€€€mÙ½¥‘t‘ÍÉ¥ÁÐéÉ•™É•Í¡ÉÉ½ÉÌ¹I•µ½Ù” AÉ½•ÍÍ•Ìœ¤(€€€M•ÐµMÑ…ÑÕÌ€I•…‘¥¹œÕÉÉ•¹ÐµÍ•ÍÍ¥½¸ÁÉ½•ÍÍ•ÏŠ˜œ€µ	ÕÍä(€€€ÑÉäì(€€€€€€€€‘É¥Ñ¥…±9…µ•Ì€ô  …Õ‘¥½‘œœ°ÍÉÍÌœ°‘Ý´œ°•áÁ±½É•Èœ°™½¹Ñ‘ÉÙ¡½ÍÐœ°±Í…ÍÌœ°Í•ÉÙ¥•Ìœ°Í¥¡½ÍÐœ°ÍµÍÌœ°MÑ…ÉÑ5•¹ÕáÁ•É¥•¹•!½ÍÐœ°MåÍÑ•´œ°Ñ…Í­¡½ÍÑÜœ°Ý¥¹¥¹¥Ðœ°Ý¥¹±½½¸œ¤(€€€€€€€€‘Í•ÍÍ¥½¹%€ô€¡•ÐµAÉ½•ÍÌ€µ%€‘A%¤¹M•ÍÍ¥½¹%(€€€€€€€€‘¥µAÉ½•ÍÍ•Ì€ô ¡•Ðµ¥µ%¹ÍÑ…¹”]¥¸ÌÉ}AÉ½•ÍÌ€µ¥±Ñ•È€‰M•ÍÍ¥½¹%ô‘Í•ÍÍ¥½¹%ˆ€µÉÉ½ÉÑ¥½¸M¥±•¹Ñ±å½¹Ñ¥¹Õ”¤(€€€€€€€€‘ÍÉ¥ÁÐé…±±AÉ½•ÍÍ•Ì€ô  (€€€€€€€€€€€™½É•… € ‘¥´¥¸€‘¥µAÉ½•ÍÍ•Ì¤ì(€€€€€€€€€€€€€€€€‘ÁÉ½•ÍÌ€ô•ÐµAÉ½•ÍÌ€µ%€‘¥´¹AÉ½•ÍÍ%€µÉÉ½ÉÑ¥½¸M¥±•¹Ñ±å½¹Ñ¥¹Õ”(€€€€€€€€€€€€€€€¥˜€ µ¹½Ð€‘ÁÉ½•ÍÌ¤ì½¹Ñ¥¹Õ”ô(€€€€€€€€€€€€€€€€‘É…Ý9…µ”€ô€‘ÁÉ½•ÍÌ¹AÉ½•ÍÍ9…µ”(€€€€€€€€€€€€€€€€‘ÁÕ‰±¥Í¡•È€ô€œœ(€€€€€€€€€€€€€€€ÑÉäì€‘ÁÕ‰±¥Í¡•È€ômÍÑÉ¥¹t‘ÁÉ½•ÍÌ¹5…¥¹5½‘Õ±”¹¥±•Y•ÉÍ¥½¹%¹™¼¹½µÁ…¹å9…µ”ô…Ñ íô(€€€€€€€€€€€€€€€€‘…¹MÑ½À€ô€‘ÁÉ½•ÍÌ¹%€µ¹”€‘A%€µ…¹€‘É…Ý9…µ”€µ¹½Ñ¥¸€‘É¥Ñ¥…±9…µ•Ì(€€€€€€€€€€€€€€€mÁÍÕÍÑ½µ½‰©•Ñuì(€€€€€€€€€€€€€€€€€€€9…µ”€ô€‘É…Ý9…µ”(€€€€€€€€€€€€€€€€€€€%€ôm¥¹Ñt‘ÁÉ½•ÍÌ¹%(€€€€€€€€€€€€€€€€€€€5•µ½Éä€ô€ ìÀé8Áô5œ€µ˜€ ‘ÁÉ½•ÍÌ¹]½É­¥¹M•ÐØÐ€¼€Å5¤¤(€€€€€€€€€€€€€€€€€€€5•µ½Éå	åÑ•Ì€ôm±½¹t‘ÁÉ½•ÍÌ¹]½É­¥¹M•ÐØÐ(€€€€€€€€€€€€€€€€€€€AÕ‰±¥Í¡•È€ô¥˜€ ‘ÁÕ‰±¥Í¡•È¤ì€‘ÁÕ‰±¥Í¡•Èô•±Í”ì€U¹­¹½Ý¸ÁÕ‰±¥Í¡•Èœô(€€€€€€€€€€€€€€€€€€€½¹ÑÉ½°€ô¥˜€ ‘…¹MÑ½À¤ì€Ù…¥±…‰±”œô•±Í”ì€AÉ½Ñ•Ñ•œô(€€€€€€€€€€€€€€€€€€€…¹MÑ½À€ô€‘…¹MÑ½À(€€€€€€€€€€€€€€€ô(€€€€€€€€€€€ô(€€€€€€€€¤ðM½ÉÐµ=‰©•Ð5•µ½Éå	åÑ•Ì€µ•Í•¹‘¥¹œ(€€€€€€€ÁÁ±äµAÉ½•ÍÍ¥±Ñ•È(€€€€€€€€‘Õ¤¹AÉ½•ÍÍ•ÍÉ¥¹M•±•Ñ•‘%Ñ•´€ô€‘¹Õ±°(€€€€€€€M•ÐµMÑ…ÑÕÌ€‰AÉ½•ÍÍ•ÌÉ•™É•Í¡•…Ð€¡•Ðµ…Ñ”€µ½Éµ…Ð€! éµ´éÍÌœ¤¸ˆ(€€€ô(€€€…Ñ ì(€€€€€€€€‘ÍÉ¥ÁÐéÉ•™É•Í¡ÉÉ½ÉÍlAÉ½•ÍÍ•Ìt€ô€‘|¹á•ÁÑ¥½¸¹Q½MÑÉ¥¹œ ¤(€€€€€€€m]¥¹‘½ÝÌ¹5•ÍÍ…•	½átèéM¡½Ü ‘Ý¥¹‘½Ü°€‘|¹á•ÁÑ¥½¸¹5•ÍÍ…”°€½Õ±¹½ÐÉ•™É•Í ÁÉ½•ÍÍ•Ìœ°€=,œ°€ÉÉ½Èœ¤ð=ÕÐµ9Õ±°(€€€€€€€M•ÐµMÑ…ÑÕÌ€AÉ½•ÍÌÉ•™É•Í ™…¥±•¸œ(€€€€€€€m]¥¹‘½ÝÌ¹ÕÑ½µ…Ñ¥½¸¹ÕÑ½µ…Ñ¥½¹AÉ½Á•ÉÑ¥•ÍtèéM•Ñ!•±ÁQ•áÐ ‘Õ¤¹MÑ…ÑÕÍQ•áÐ°€‘ÍÉ¥ÁÐéÉ•™É•Í¡ÉÉ½ÉÍlAÉ½•ÍÍ•Ìt¤(€€€ô)ô((‘Õ¤¹ÁÁÍÉ¥¹‘‘}M•±•Ñ¥½¹¡…¹•¡ì(€€€€‘…ÁÀ€ô€‘Õ¤¹ÁÁÍÉ¥¹M•±•Ñ•‘%Ñ•´(€€€¥˜€ µ¹½Ð€‘…ÁÀ¤ì(€€€€€€€€‘Õ¤¹ÁÁ•Ñ…¥±Q¥Ñ±”¹Q•áÐ€ô€M•±•Ð…¸…ÁÀœ(€€€€€€€€‘Õ¤¹ÁÁ•Ñ…¥±Q•áÐ¹Q•áÐ€ô€ÁÀ‘•Ñ…¥±Ì…¹…Ù…¥±…‰±”…Ñ¥½¹ÌÝ¥±°…ÁÁ•…È¡•É”¸œ(€€€€€€€€‘Õ¤¹¥Í…‰±•ÁÀ¹½¹Ñ•¹Ð€ô€¥Í…‰±”‰…­É½Õ¹œ(€€€€€€€€‘Õ¤¹¥Í…‰±•ÁÀ¹%Í¹…‰±•€ô€‘™…±Í”(€€€€€€€€‘Õ¤¹U¹¥¹ÍÑ…±±ÁÀ¹%Í¹…‰±•€ô€‘™…±Í”(€€€€€€€É•ÑÕÉ¸(€€€ô(€€€€‘Õ¤¹ÁÁ•Ñ…¥±Q¥Ñ±”¹Q•áÐ€ô€‘…ÁÀ¹9…µ”(€€€€‘µ…¹…•‘Q•áÐ€ô¥˜€ ‘…ÁÀ¹5…¹…•‘9…µ”¤ì€ˆƒŠˆ€ ‘…ÁÀ¹MÑ…ÑÕÌ¹Q½1½Ý•É%¹Ù…É¥…¹Ð ¤¤ˆô•±Í”ì€œœô(€€€€‘Õ¤¹ÁÁ•Ñ…¥±Q•áÐ¹Q•áÐ€ô€ˆ ‘…ÁÀ¹AÕ‰±¥Í¡•È¤ƒŠˆ€ ‘…ÁÀ¹Y•ÉÍ¥½¸¤ƒŠˆ€ ‘…ÁÀ¹M½Á”¤‘µ…¹…•‘Q•áÐˆ(€€€€‘Õ¤¹¥Í…‰±•ÁÀ¹½¹Ñ•¹Ð€ô¥˜€ ‘…ÁÀ¹5…¹…•‘9…µ”€µ…¹€µ¹½Ð€‘…ÁÀ¹	…­É½Õ¹‘Ñ¥Ù”¤ì€	…­É½Õ¹‘¥Í…‰±•œô•±Í”ì€¥Í…‰±”‰…­É½Õ¹œô(€€€€‘Õ¤¹¥Í…‰±•ÁÀ¹%Í¹…‰±•€ôm‰½½±t‘…ÁÀ¹5…¹…•‘9…µ”€µ…¹m‰½½±t‘…ÁÀ¹	…­É½Õ¹‘Ñ¥Ù”(€€€€‘Õ¤¹U¹¥¹ÍÑ…±±ÁÀ¹%Í¹…‰±•€ôm‰½½±t‘…ÁÀ¹…¹U¹¥¹ÍÑ…±°)ô¤((‘Õ¤¹MÑ…ÉÑÕÁÉ¥¹‘‘}M•±•Ñ¥½¹¡…¹•¡ì(€€€€‘¥Ñ•´€ô€‘Õ¤¹MÑ…ÉÑÕÁÉ¥¹M•±•Ñ•‘%Ñ•´(€€€¥˜€ µ¹½Ð€‘¥Ñ•´¤ì(€€€€€€€€‘Õ¤¹MÑ…ÉÑÕÁ•Ñ…¥±Q¥Ñ±”¹Q•áÐ€ô€M•±•Ð„ÍÑ…ÉÑÕÀ¥Ñ•´œ(€€€€€€€€‘Õ¤¹MÑ…ÉÑÕÁ•Ñ…¥±Q•áÐ¹Q•áÐ€ô€9½Ñ¡¥¹œ¥Ì¡…¹•Õ¹Ñ¥°å½Ô½¹™¥É´…¸…Ñ¥½¸¸œ(€€€€€€€€‘Õ¤¹Q½±•MÑ…ÉÑÕÀ¹%Í¹…‰±•€ô€‘™…±Í”(€€€€€€€É•ÑÕÉ¸(€€€ô(€€€€‘Õ¤¹MÑ…ÉÑÕÁ•Ñ…¥±Q¥Ñ±”¹Q•áÐ€ô€‘¥Ñ•´¹9…µ”(€€€€‘Õ¤¹MÑ…ÉÑÕÁ•Ñ…¥±Q•áÐ¹Q•áÐ€ô€ˆ ‘¥Ñ•´¹M½ÕÉ”¤ƒŠˆ€ ‘¥Ñ•´¹½µµ…¹¤ˆ(€€€€‘Õ¤¹Q½±•MÑ…ÉÑÕÀ¹½¹Ñ•¹Ð€ô¥˜€ ‘¥Ñ•´¹MÑ…ÑÕÌ€µ•Ä€¹…‰±•œ¤ì€¥Í…‰±”œô•±Í”ì€I•ÍÑ½É”œô(€€€€‘Õ¤¹Q½±•MÑ…ÉÑÕÀ¹%Í¹…‰±•€ô€‘ÑÉÕ”)ô¤((‘Õ¤¹AÉ½•ÍÍ•ÍÉ¥¹‘‘}M•±•Ñ¥½¹¡…¹•¡ì(€€€€‘ÁÉ½•ÍÌ€ô€‘Õ¤¹AÉ½•ÍÍ•ÍÉ¥¹M•±•Ñ•‘%Ñ•´(€€€¥˜€ µ¹½Ð€‘ÁÉ½•ÍÌ¤ì(€€€€€€€€‘Õ¤¹AÉ½•ÍÍ•Ñ…¥±Q¥Ñ±”¹Q•áÐ€ô€M•±•Ð„ÁÉ½•ÍÌœ(€€€€€€€€‘Õ¤¹AÉ½•ÍÍ•Ñ…¥±Q•áÐ¹Q•áÐ€ô€¹‘¥¹œ„ÁÉ½•ÍÌ…¸‘¥Í…ÉÕ¹Í…Ù•Ý½É¬¸œ(€€€€€€€€‘Õ¤¹¹‘AÉ½•ÍÌ¹%Í¹…‰±•€ô€‘™…±Í”(€€€€€€€É•ÑÕÉ¸(€€€ô(€€€€‘Õ¤¹AÉ½•ÍÍ•Ñ…¥±Q¥Ñ±”¹Q•áÐ€ô€ˆ ‘ÁÉ½•ÍÌ¹9…µ”¤€€¡A%€ ‘ÁÉ½•ÍÌ¹%¤¤ˆ(€€€€‘Õ¤¹AÉ½•ÍÍ•Ñ…¥±Q•áÐ¹Q•áÐ€ô€ˆ ‘ÁÉ½•ÍÌ¹5•µ½Éä¤ƒŠˆ€ ‘ÁÉ½•ÍÌ¹AÕ‰±¥Í¡•È¤ƒŠˆ€ ‘ÁÉ½•ÍÌ¹½¹ÑÉ½°¤ˆ(€€€€‘Õ¤¹¹‘AÉ½•ÍÌ¹%Í¹…‰±•€ôm‰½½±t‘ÁÉ½•ÍÌ¹…¹MÑ½À)ô¤((‘Õ¤¹9…ÙÁÁÌ¹‘‘}±¥¬¡ìM¡½ÜµA…”ÁÁÌô¤(‘Õ¤¹9…ÙMÑ…ÉÑÕÀ¹‘‘}±¥¬¡ìM¡½ÜµA…”MÑ…ÉÑÕÀì¥˜€ ‘ÍÉ¥ÁÐé…±±MÑ…ÉÑÕÀ¹½Õ¹Ð€µ•Ä€À¤ìI•™É•Í µMÑ…ÉÑÕÀôô¤(‘Õ¤¹9…ÙAÉ½•ÍÍ•Ì¹‘‘}±¥¬¡ìM¡½ÜµA…”AÉ½•ÍÍ•Ìì¥˜€ ‘ÍÉ¥ÁÐé…±±AÉ½•ÍÍ•Ì¹½Õ¹Ð€µ•Ä€À¤ìI•™É•Í µAÉ½•ÍÍ•Ìôô¤(‘Õ¤¹ÁÁM•…É ¹‘‘}Q•áÑ¡…¹•¡ìÁÁ±äµÁÁ¥±Ñ•Èô¤(‘Õ¤¹MÑ…ÉÑÕÁM•…É ¹‘‘}Q•áÑ¡…¹•¡ìÁÁ±äµMÑ…ÉÑÕÁ¥±Ñ•Èô¤(‘Õ¤¹AÉ½•ÍÍM•…É ¹‘‘}Q•áÑ¡…¹•¡ìÁÁ±äµAÉ½•ÍÍ¥±Ñ•Èô¤(‘Õ¤¹I•™É•Í¡ÁÁÌ¹‘‘}±¥¬¡ìI•™É•Í µÁÁÌô¤(‘Õ¤¹I•™É•Í¡MÑ…ÉÑÕÀ¹‘‘}±¥¬¡ìI•™É•Í µMÑ…ÉÑÕÀô¤(‘Õ¤¹I•™É•Í¡AÉ½•ÍÍ•Ì¹‘‘}±¥¬¡ìI•™É•Í µAÉ½•ÍÍ•Ìô¤((‘Õ¤¹¥Í…‰±•ÁÀ¹‘‘}±¥¬¡ì(€€€€‘…ÁÀ€ô€‘Õ¤¹ÁÁÍÉ¥¹M•±•Ñ•‘%Ñ•´(€€€¥˜€ µ¹½Ð€‘…ÁÀ€µ½È€µ¹½Ð€‘…ÁÀ¹5…¹…•‘9…µ”€µ½È€µ¹½Ð€‘…ÁÀ¹	…­É½Õ¹‘Ñ¥Ù”¤ìÉ•ÑÕÉ¸ô(€€€€‘µ•ÍÍ…”€ô€‰¥Í…‰±”ÍÑ…ÉÑÕÀ…¹ÕÉÉ•¹Ð‰…­É½Õ¹…Ñ¥Ù¥Ñä™½È€ ‘…ÁÀ¹9…µ”¤ý¹¹Q¡”…ÁÁ±¥…Ñ¥½¸É•µ…¥¹Ì¥¹ÍÑ…±±•…¹…¸ÍÑ¥±°ÉÕ¸Ý¡•¸å½Ô½Á•¸¥Ð½ÈÝ¡•¸…¹½Ñ¡•È…ÁÀ•áÁ±¥¥Ñ±ä±…Õ¹¡•Ì¥Ð¸ÕÑ½µ…Ñ¥Œ…Ñ…±½•Í•ÉÙ¥•Ì…É”Í•ÐÑ¼µ…¹Õ…°…¹…¸É•ÅÕ•ÍÐ…‘µ¥¹¥ÍÑÉ…Ñ½È…ÁÁÉ½Ù…°¸ˆ(€€€¥˜€¡m]¥¹‘½ÝÌ¹5•ÍÍ…•	½átèéM¡½Ü ‘Ý¥¹‘½Ü°€‘µ•ÍÍ…”°€½¹™¥É´‰…­É½Õ¹¡…¹”œ°€e•Í9¼œ°€]…É¹¥¹œœ¤€µ¹”€e•Ìœ¤ìÉ•ÑÕÉ¸ô(€€€M•ÐµMÑ…ÑÕÌ€‰¥Í…‰±¥¹œ€ ‘…ÁÀ¹9…µ”§Š˜ˆ€µ	ÕÍä(€€€€‘É•ÍÕ±Ð€ô%¹Ù½­”µ½¹ÑÉ½±MÉ¥ÁÐ€‘½ÁÑ¥½¹…±5…¹…•È  œµÑ¥½¸œ°¥Í…‰±•MÑ…ÉÑÕÀœ°œµ9…µ”œ°‘…ÁÀ¹5…¹…•‘9…µ”°œµ½É”œ¤(€€€€‘™…¥±•€ô€‘É•ÍÕ±Ð¹á¥Ñ½‘”€µ¹”€À(€€€¥˜€ ‘™…¥±•¤ìM¡½ÜµÉÉ½È€	…­É½Õ¹…Ñ¥½¸‘¥¹½Ð½µÁ±•Ñ”œ€‘É•ÍÕ±Ðô(€€€I•™É•Í µÁÁÌ(€€€I•™É•Í µMÑ…ÉÑÕÀ(€€€¥˜€ ‘™…¥±•¤ìM•ÐµMÑ…ÑÕÌ€‰½Õ±¹½Ð™Õ±±ä‘¥Í…‰±”‰…­É½Õ¹…Ñ¥Ù¥Ñä™½È€ ‘…ÁÀ¹9…µ”¤¸ˆô(€€€•±Í”ìM•ÐµMÑ…ÑÕÌ€‰	…­É½Õ¹…¹ÍÑ…ÉÑÕÀ…Ñ¥Ù¥Ñä‘¥Í…‰±•™½È€ ‘…ÁÀ¹9…µ”¤¸ˆô)ô¤((‘Õ¤¹U¹¥¹ÍÑ…±±ÁÀ¹‘‘}±¥¬¡ì(€€€€‘…ÁÀ€ô€‘Õ¤¹ÁÁÍÉ¥¹M•±•Ñ•‘%Ñ•´(€€€¥˜€ µ¹½Ð€‘…ÁÀ€µ½È€µ¹½Ð€‘…ÁÀ¹…¹U¹¥¹ÍÑ…±°¤ìÉ•ÑÕÉ¸ô(€€€€‘Ý…É¹¥¹œ€ô¥˜€ ‘…ÁÀ¹5…¹…•‘9…µ”€µ…¹€‘…Ñ…±½	å9…µ”¹½¹Ñ…¥¹Í-•ä¡mÍÑÉ¥¹t‘…ÁÀ¹5…¹…•‘9…µ”¤¤ì€‰¹¸ ‘…Ñ…±½	å9…µ•mmÍÑÉ¥¹t‘…ÁÀ¹5…¹…•‘9…µ•t¹Ý…É¹¥¹œ¤ˆô•±Í”ì€œœô(€€€€‘µ•ÍÍ…”€ô€‰U¹¥¹ÍÑ…±°€ ‘…ÁÀ¹9…µ”¤ý¹¹AÕ‰±¥Í¡•Èè€ ‘…ÁÀ¹AÕ‰±¥Í¡•È¥¹QåÁ”è€ ‘…ÁÀ¹M½ÕÉ”¤‘Ý…É¹¥¹¹¹]¥¹‘½ÝÌµ…äÉ•ÅÕ•ÍÐ…‘µ¥¹¥ÍÑÉ…Ñ½È…ÁÁÉ½Ù…°¸ˆ(€€€¥˜€¡m]¥¹‘½ÝÌ¹5•ÍÍ…•	½átèéM¡½Ü ‘Ý¥¹‘½Ü°€‘µ•ÍÍ…”°€½¹™¥É´Õ¹¥¹ÍÑ…±°œ°€e•Í9¼œ°€]…É¹¥¹œœ¤€µ¹”€e•Ìœ¤ìÉ•ÑÕÉ¸ô(€€€M•ÐµMÑ…ÑÕÌ€‰U¹¥¹ÍÑ…±±¥¹œ€ ‘…ÁÀ¹9…µ”§Š˜ˆ€µ	ÕÍä(€€€€‘É•ÍÕ±Ð€ô¥˜€ ‘…ÁÀ¹5…¹…•‘9…µ”¤ì(€€€€€€€%¹Ù½­”µ½¹ÑÉ½±MÉ¥ÁÐ€‘½ÁÑ¥½¹…±5…¹…•È  œµÑ¥½¸œ°U¹¥¹ÍÑ…±°œ°œµ9…µ”œ°‘…ÁÀ¹5…¹…•‘9…µ”°œµ½É”œ¤(€€€ô•±Í”ì(€€€€€€€%¹Ù½­”µ½¹ÑÉ½±MÉ¥ÁÐ€‘¥¹ÍÑ…±±•‘5…¹…•È  œµÑ¥½¸œ°U¹¥¹ÍÑ…±°œ°œµ%œ°‘…ÁÀ¹%°œµ½É”œ¤(€€€ô(€€€¥˜€ ‘É•ÍÕ±Ð¹á¥Ñ½‘”€µ¹”€À¤ìM¡½ÜµÉÉ½È€U¹¥¹ÍÑ…±°‘¥¹½Ð½µÁ±•Ñ”œ€‘É•ÍÕ±Ðô(€€€I•™É•Í µÁÁÌ(€€€I•™É•Í µMÑ…ÉÑÕÀ(€€€I•™É•Í µAÉ½•ÍÍ•Ì)ô¤((‘Õ¤¹Q½±•MÑ…ÉÑÕÀ¹‘‘}±¥¬¡ì(€€€€‘¥Ñ•´€ô€‘Õ¤¹MÑ…ÉÑÕÁÉ¥¹M•±•Ñ•‘%Ñ•´(€€€¥˜€ µ¹½Ð€‘¥Ñ•´¤ìÉ•ÑÕÉ¸ô(€€€€‘…Ñ¥½¸€ô¥˜€ ‘¥Ñ•´¹MÑ…ÑÕÌ€µ•Ä€¹…‰±•œ¤ì€¥Í…‰±”œô•±Í”ì€¹…‰±”œô(€€€€‘Ù•Éˆ€ô¥˜€ ‘…Ñ¥½¸€µ•Ä€¥Í…‰±”œ¤ì€‘¥Í…‰±”œô•±Í”ì€É•ÍÑ½É”œô(€€€¥˜€¡m]¥¹‘½ÝÌ¹5•ÍÍ…•	½átèéM¡½Ü ‘Ý¥¹‘½Ü°€‰M…™•±ä€‘Ù•Éˆ€ ‘¥Ñ•´¹9…µ”¤üˆ°€‰½¹™¥É´€‘Ù•Éˆˆ°€e•Í9¼œ°€EÕ•ÍÑ¥½¸œ¤€µ¹”€e•Ìœ¤ìÉ•ÑÕÉ¸ô(€€€M•ÐµMÑ…ÑÕÌ€ˆ ‘Ù•Éˆ¹MÕ‰ÍÑÉ¥¹œ À°Ä¤¹Q½UÁÁ•É%¹Ù…É¥…¹Ð ¤¤ ‘Ù•Éˆ¹MÕ‰ÍÑÉ¥¹œ Ä¤¥¥¹œ€ ‘¥Ñ•´¹9…µ”§Š˜ˆ€µ	ÕÍä(€€€€‘É•ÍÕ±Ð€ô%¹Ù½­”µ½¹ÑÉ½±MÉ¥ÁÐ€‘ÍÑ…ÉÑÕÁ5…¹…•È  œµÑ¥½¸œ°‘…Ñ¥½¸°œµ%œ°‘¥Ñ•´¹%°œµ½É”œ¤(€€€¥˜€ ‘É•ÍÕ±Ð¹á¥Ñ½‘”€µ¹”€À¤ìM¡½ÜµÉÉ½È€MÑ…ÉÑÕÀ…Ñ¥½¸‘¥¹½Ð½µÁ±•Ñ”œ€‘É•ÍÕ±Ðô(€€€I•™É•Í µMÑ…ÉÑÕÀ)ô¤((‘Õ¤¹¹‘AÉ½•ÍÌ¹‘‘}±¥¬¡ì(€€€€‘Í•±•Ñ•€ô€‘Õ¤¹AÉ½•ÍÍ•ÍÉ¥¹M•±•Ñ•‘%Ñ•´(€€€¥˜€ µ¹½Ð€‘Í•±•Ñ•€µ½È€µ¹½Ð€‘Í•±•Ñ•¹…¹MÑ½À¤ìÉ•ÑÕÉ¸ô(€€€¥˜€¡m]¥¹‘½ÝÌ¹5•ÍÍ…•	½átèéM¡½Ü ‘Ý¥¹‘½Ü°€‰¹€ ‘Í•±•Ñ•¹9…µ”¤€¡A%€ ‘Í•±•Ñ•¹%¤¤ý¹¹U¹Í…Ù•Ý½É¬¥¸Ñ¡¥ÌÁÉ½•ÍÌÝ¥±°‰”±½ÍÐ¸ˆ°€½¹™¥É´•¹ÁÉ½•ÍÌœ°€e•Í9¼œ°€]…É¹¥¹œœ¤€µ¹”€e•Ìœ¤ìÉ•ÑÕÉ¸ô(€€€ÑÉäì(€€€€€€€€‘ÕÉÉ•¹Ð€ô•ÐµAÉ½•ÍÌ€µ%€‘Í•±•Ñ•¹%€µÉÉ½ÉÑ¥½¸MÑ½À(€€€€€€€¥˜€ ‘ÕÉÉ•¹Ð¹AÉ½•ÍÍ9…µ”€µ¹”€‘Í•±•Ñ•¹9…µ”¤ìÑ¡É½Ü€Q¡”Í•±•Ñ•A%¹½Ü‰•±½¹ÌÑ¼„‘¥™™•É•¹ÐÁÉ½•ÍÌ¸I•™É•Í …¹ÑÉä……¥¸¸œô(€€€€€€€MÑ½ÀµAÉ½•ÍÌ€µ%€‘Í•±•Ñ•¹%€µ½É”€µÉÉ½ÉÑ¥½¸MÑ½À(€€€€€€€M•ÐµMÑ…ÑÕÌ€‰¹‘•€ ‘Í•±•Ñ•¹9…µ”¤¸ˆ(€€€ô(€€€…Ñ ìm]¥¹‘½ÝÌ¹5•ÍÍ…•	½átèéM¡½Ü ‘Ý¥¹‘½Ü°€‘|¹á•ÁÑ¥½¸¹5•ÍÍ…”°€½Õ±¹½Ð•¹ÁÉ½•ÍÌœ°€=,œ°€ÉÉ½Èœ¤ð=ÕÐµ9Õ±°ô(€€€I•™É•Í µAÉ½•ÍÍ•Ì)ô¤()M¡½ÜµA…”ÁÁÌ)¥˜€ ‘Mµ½­•Q•ÍÐ¤ì(€€€I•™É•Í µÁÁÌ(€€€I•™É•Í µMÑ…ÉÑÕÀ(€€€I•™É•Í µAÉ½•ÍÍ•Ì(€€€¥˜€ ‘ÍÉ¥ÁÐéÉ•™É•Í¡ÉÉ½ÉÌ¹½Õ¹Ð€µÐ€À¤ì(€€€€€€€Ñ¡É½Ü€‰ÁÀ½¹ÑÉ½°Íµ½­”Ñ•ÍÐÉ•™É•Í ™…¥±•è€ ‘ÍÉ¥ÁÐéÉ•™É•Í¡ÉÉ½ÉÌ¹Y…±Õ•Ì€µ©½¥¸€œð€œ¤ˆ(€€€ô(€€€m½É‘•É•‘uì(€€€€€€€MÑ…ÑÕÌ€ô€Á…ÍÌœ(€€€€€€€%¹ÍÑ…±±•‘I½ÝÌ€ô€‘Õ¤¹ÁÁÍÉ¥¹%Ñ•µÌ¹½Õ¹Ð(€€€€€€€MÑ…ÉÑÕÁI½ÝÌ€ô€‘Õ¤¹MÑ…ÉÑÕÁÉ¥¹%Ñ•µÌ¹½Õ¹Ð(€€€€€€€AÉ½•ÍÍI½ÝÌ€ô€‘Õ¤¹AÉ½•ÍÍ•ÍÉ¥¹%Ñ•µÌ¹½Õ¹Ð(€€€€€€€áÑ•É¹…±M•ÑÑ¥¹Í1¥¹­Ì€ô€À(€€€ôð½¹Ù•ÉÑQ¼µ)Í½¸(€€€€‘Ý¥¹‘½Ü¹±½Í” ¤(€€€É•ÑÕÉ¸)ô((‘Ý¥¹‘½Ü¹‘‘}½¹Ñ•¹ÑI•¹‘•É•¡ìI•™É•Í µÁÁÌô¤)mÙ½¥‘t‘Ý¥¹‘½Ü¹M¡½Ý¥…±½œ ¤(