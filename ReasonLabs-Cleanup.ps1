#requires -version 5.1
<#
.SYNOPSIS
    Disables ReasonLabs services and prepares a one-time startup cleanup task.

.DESCRIPTION
    This script was created as a community workaround for systems where the
    standard ReasonLabs uninstall process is unavailable or unsuccessful.

    It performs the following actions:
      1. Checks for administrative privileges.
      2. Finds ReasonLabs-related Windows services.
      3. Sets their startup type to Disabled through the service registry keys.
      4. Creates a cleanup CMD file under C:\Windows\Temp\ReasonCleanup.
      5. Registers a one-time startup task that runs as SYSTEM.
      6. Optionally schedules a controlled restart.

    During the next startup, the cleanup task attempts to:
      - Stop and delete known ReasonLabs services.
      - Remove ReasonLabs uninstall registry entries.
      - Delete C:\Program Files\ReasonLabs.
      - Delete the scheduled task after execution.
      - Record the results in cleanup.log.

.NOTES
    Run this script only on systems you own or are authorized to administer.
    Test it in a controlled environment before using it in production.

    This script is provided without warranty. Results may vary depending on
    the ReasonLabs version, permissions, system configuration, and security
    controls.

.EXAMPLE
    .\ReasonLabs-Cleanup.ps1

    Prepares the cleanup task but does not restart the computer.

.EXAMPLE
    .\ReasonLabs-Cleanup.ps1 -Restart

    Prepares the cleanup task and schedules a restart after 60 seconds.

.EXAMPLE
    .\ReasonLabs-Cleanup.ps1 -Restart -RestartDelay 120

    Prepares the cleanup task and schedules a restart after 120 seconds.
#>

[CmdletBinding()]
param(
    [switch]$Restart,

    [ValidateRange(10, 3600)]
    [int]$RestartDelay = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName     = 'ReasonLabs Cleanup'
$WorkDir      = Join-Path $env:windir 'Temp\ReasonCleanup'
$CleanupFile  = Join-Path $WorkDir 'cleanup.cmd'
$SetupLog     = Join-Path $WorkDir 'setup.log'
$CleanupLog   = Join-Path $WorkDir 'cleanup.log'

$KnownServices = @(
    'rsEngineSvc',
    'rsWSC',
    'rsClientSvc',
    'rsEDRSvc',
    'rsSyncSvc'
)

function Write-SetupLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line

    if (Test-Path $WorkDir) {
        Add-Content -LiteralPath $SetupLog -Value $line -Encoding UTF8
    }
}

function Assert-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This script must be run from an elevated PowerShell session.'
    }
}

try {
    Assert-Administrator

    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    Set-Content -LiteralPath $SetupLog -Value '' -Encoding UTF8

    Write-SetupLog 'Starting ReasonLabs cleanup preparation.'
    Write-SetupLog ("Computer: {0}" -f $env:COMPUTERNAME)
    Write-SetupLog ("User: {0}" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name)

    $detectedServices = @(
        Get-CimInstance Win32_Service |
            Where-Object {
                ($_.PathName -match 'ReasonLabs') -or
                ($_.DisplayName -match 'ReasonLabs|Reason Security|RAV')
            }
    )

    if ($detectedServices.Count -eq 0) {
        Write-SetupLog 'No ReasonLabs services were detected through WMI/CIM. The known service names will still be included in the startup cleanup task.' 'WARN'
    }
    else {
        Write-SetupLog ("Detected {0} ReasonLabs-related service(s)." -f $detectedServices.Count)

        foreach ($service in $detectedServices) {
            Write-SetupLog ("Detected service: {0} | State: {1} | StartMode: {2} | Path: {3}" -f `
                $service.Name, $service.State, $service.StartMode, $service.PathName)
        }
    }

    $serviceNames = @(
        $KnownServices
        $detectedServices.Name
    ) | Where-Object { $_ } | Sort-Object -Unique

    foreach ($serviceName in $serviceNames) {
        $serviceRegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"

        if (Test-Path -LiteralPath $serviceRegistryPath) {
            Set-ItemProperty -LiteralPath $serviceRegistryPath -Name Start -Type DWord -Value 4
            Write-SetupLog ("Disabled service startup through registry: {0}" -f $serviceName)
        }
        else {
            Write-SetupLog ("Service registry key not found: {0}" -f $serviceName) 'WARN'
        }
    }

    $cleanupLines = @(
        '@echo off'
        'setlocal'
        ('set "LOG={0}"' -f $CleanupLog)
        'echo ================================================== >> "%LOG%"'
        'echo [%DATE% %TIME%] Starting ReasonLabs cleanup >> "%LOG%"'
        'echo Computer: %COMPUTERNAME% >> "%LOG%"'
        'echo User: %USERNAME% >> "%LOG%"'
        'echo. >> "%LOG%"'
    )

    foreach ($serviceName in $serviceNames) {
        $cleanupLines += ('echo Stopping service {0} >> "%LOG%"' -f $serviceName)
        $cleanupLines += ('sc.exe stop {0} >> "%LOG%" 2>&1' -f $serviceName)
        $cleanupLines += ('echo Deleting service {0} >> "%LOG%"' -f $serviceName)
        $cleanupLines += ('sc.exe delete {0} >> "%LOG%" 2>&1' -f $serviceName)
    }

    $cleanupLines += @(
        'echo Removing uninstall registry entries >> "%LOG%"'
        'reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ReasonLabs-EPP" /f >> "%LOG%" 2>&1'
        'reg.exe delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\ReasonLabs-EPP" /f >> "%LOG%" 2>&1'
        'echo Waiting before deleting program files >> "%LOG%"'
        'timeout.exe /t 30 /nobreak >> "%LOG%" 2>&1'
        'echo Removing ReasonLabs program directory >> "%LOG%"'
        'rmdir /s /q "C:\Program Files\ReasonLabs" >> "%LOG%" 2>&1'
        'echo Deleting scheduled task >> "%LOG%"'
        ('schtasks.exe /delete /tn "{0}" /f >> "%LOG%" 2>&1' -f $TaskName)
        'echo [%DATE% %TIME%] ReasonLabs cleanup completed >> "%LOG%"'
        'echo ================================================== >> "%LOG%"'
        'endlocal'
    )

    Set-Content -LiteralPath $CleanupFile -Value $cleanupLines -Encoding ASCII
    Write-SetupLog ("Created startup cleanup script: {0}" -f $CleanupFile)

    $action = New-ScheduledTaskAction `
        -Execute 'cmd.exe' `
        -Argument ('/c "{0}"' -f $CleanupFile)

    $trigger = New-ScheduledTaskTrigger -AtStartup

    $principal = New-ScheduledTaskPrincipal `
        -UserId 'SYSTEM' `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description 'One-time ReasonLabs service and file cleanup task.' `
        -Force | Out-Null

    $task = Get-ScheduledTask -TaskName $TaskName
    Write-SetupLog ("Scheduled task created successfully: {0}" -f $task.TaskName)
    Write-SetupLog 'The cleanup task will run as SYSTEM during the next startup.'

    Write-Host ''
    Write-Host 'Preparation completed successfully.'
    Write-Host ''
    Write-Host ("Setup log:   {0}" -f $SetupLog)
    Write-Host ("Cleanup log: {0}" -f $CleanupLog)
    Write-Host ("Task name:   {0}" -f $TaskName)
    Write-Host ''

    if ($Restart) {
        Write-SetupLog ("Scheduling controlled restart in {0} seconds." -f $RestartDelay)
        & shutdown.exe /r /t $RestartDelay /c 'Controlled restart for ReasonLabs cleanup'
        Write-Host ("Restart scheduled. Run 'shutdown /a' to cancel it before the timer expires.")
    }
    else {
        Write-Host 'Restart the computer when operationally appropriate to execute the cleanup task.'
        Write-Host 'To restart automatically, rerun this script with the -Restart parameter.'
    }
}
catch {
    try {
        if (-not (Test-Path $WorkDir)) {
            New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
        }

        $errorLine = '[{0}] [ERROR] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message
        Add-Content -LiteralPath $SetupLog -Value $errorLine -Encoding UTF8
    }
    catch {
        # Ignore secondary logging failures.
    }

    Write-Error $_.Exception.Message
    exit 1
}
