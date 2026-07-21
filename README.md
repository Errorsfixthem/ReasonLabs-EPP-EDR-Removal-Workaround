# ReasonLabs EPP/EDR/VPN Removal Workaround (2026)

This repository contains a PowerShell-based workaround for removing ReasonLabs EPP/EDR services when the normal uninstall process is unavailable, incomplete, or unsuccessful.

I created this guide because I searched online and could not find a complete, step-by-step solution that worked in my environment.

In my case, I decided to remove the software after observing active connections to an endpoint that had been flagged as having a poor reputation, together with other unexplained network activity.

This observation alone does **not** prove that ReasonLabs is malicious. Always validate network indicators with your own security tools and investigation process.

## Important Notice

Use this script only on systems that you own or are explicitly authorized to administer.

The script makes system-level changes, including:

- Disabling Windows services.
- Modifying service registry values.
- Creating a startup scheduled task.
- Deleting Windows services.
- Removing uninstall registry entries.
- Deleting the ReasonLabs installation directory.
- Optionally restarting the computer.

These actions may be irreversible without reinstalling the software.

Test the script in a controlled environment before using it on a production system.

This project is provided without warranty. Results may vary depending on the ReasonLabs version, Windows configuration, permissions, endpoint security controls, and enterprise policies.

## Repository Contents

```text
ReasonLabs-EPP-EDR-Removal-Workaround/
├── README.md
└── ReasonLabs-Cleanup.ps1
```

## Prerequisites

- Windows 10, Windows 11, or a supported Windows Server version.
- Windows PowerShell 5.1 or later.
- Local administrator privileges.
- Authorization to modify services, registry keys, scheduled tasks, and program files.
- A planned restart window if the script will be used in an enterprise environment.

## Recommended First Step

Before using this workaround, try the normal uninstall methods available on the system:

1. Windows **Settings > Apps > Installed apps**.
2. **Control Panel > Programs and Features**.
3. The official ReasonLabs uninstaller, if present.
4. Your organization's software deployment or endpoint management platform.

Use this workaround only when the standard removal process is unavailable or unsuccessful.

## Download

Download the `ReasonLabs-Cleanup.ps1` file from this repository.

You can also clone the repository:

```powershell
git clone https://github.com/YOUR-USERNAME/ReasonLabs-EPP-EDR-Removal-Workaround.git
cd ReasonLabs-EPP-EDR-Removal-Workaround
```

Replace `YOUR-USERNAME` with your GitHub username.

## Usage

### 1. Open PowerShell as Administrator

Search for **PowerShell**, right-click it, and select:

```text
Run as administrator
```

### 2. Change to the Script Directory

Example:

```powershell
cd "$env:USERPROFILE\Downloads"
```

Or, if you cloned the repository:

```powershell
cd "C:\Path\To\ReasonLabs-EPP-EDR-Removal-Workaround"
```

### 3. Allow Script Execution for the Current Session

This changes the execution policy only for the current PowerShell process:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### 4. Run the Script Without an Immediate Restart

```powershell
.\ReasonLabs-Cleanup.ps1
```

This option:

- Detects ReasonLabs-related services.
- Disables their startup through the registry.
- Creates the cleanup script.
- Registers a one-time startup task.
- Does not restart the computer automatically.

Restart the computer manually when operationally appropriate.

### 5. Run the Script and Schedule a Restart

To schedule a restart after 60 seconds:

```powershell
.\ReasonLabs-Cleanup.ps1 -Restart
```

To use a different restart delay:

```powershell
.\ReasonLabs-Cleanup.ps1 -Restart -RestartDelay 120
```

The allowed restart delay is between 10 and 3600 seconds.

To cancel a pending restart before the timer expires:

```cmd
shutdown /a
```

## What the Script Does

The PowerShell script performs the following steps:

1. Verifies that it is running with administrator privileges.
2. Searches for services whose path or display name is associated with ReasonLabs or RAV.
3. Adds the following known services to the cleanup list:

```text
rsEngineSvc
rsWSC
rsClientSvc
rsEDRSvc
rsSyncSvc
```

4. Sets each detected service registry value to:

```text
Start = 4
```

This configures the service startup type as `Disabled`.

5. Creates the working directory:

```text
C:\Windows\Temp\ReasonCleanup
```

6. Creates the startup cleanup script:

```text
C:\Windows\Temp\ReasonCleanup\cleanup.cmd
```

7. Creates a scheduled task named:

```text
ReasonLabs Cleanup
```

8. Configures the task to run:

- At system startup.
- Under the `SYSTEM` account.
- With the highest available privileges.

9. During the next startup, the cleanup task attempts to:

- Stop the ReasonLabs services.
- Delete the ReasonLabs services.
- Remove ReasonLabs uninstall registry entries.
- Wait 30 seconds.
- Delete the ReasonLabs program directory.
- Delete the scheduled task after execution.
- Record all results in a log file.

## Files and Logs

The script creates the following files:

```text
C:\Windows\Temp\ReasonCleanup\setup.log
C:\Windows\Temp\ReasonCleanup\cleanup.cmd
C:\Windows\Temp\ReasonCleanup\cleanup.log
```

### Setup Log

The setup log records:

- Computer name.
- User account.
- Detected services.
- Service registry changes.
- Scheduled task creation.
- Errors encountered before restart.

Review it with:

```powershell
Get-Content "C:\Windows\Temp\ReasonCleanup\setup.log"
```

### Cleanup Log

The cleanup log records the commands executed during system startup.

Review it after the restart:

```powershell
Get-Content "C:\Windows\Temp\ReasonCleanup\cleanup.log"
```

## Verification

After the computer restarts, perform the following checks from an elevated PowerShell or Command Prompt session.

### Check the Known Services

```cmd
sc query rsEngineSvc
sc query rsWSC
sc query rsClientSvc
sc query rsEDRSvc
sc query rsSyncSvc
```

A successfully deleted service should return:

```text
[SC] OpenService FAILED 1060:

The specified service does not exist as an installed service.
```

### Check for Remaining ReasonLabs Services

```powershell
Get-CimInstance Win32_Service |
    Where-Object {
        $_.PathName -match 'ReasonLabs' -or
        $_.DisplayName -match 'ReasonLabs|Reason Security|RAV'
    } |
    Select-Object Name, DisplayName, State, StartMode, PathName
```

No ReasonLabs-related services should be returned.

### Check the Installation Directory

```powershell
Test-Path "C:\Program Files\ReasonLabs"
```

Expected result:

```text
False
```

You can also check it with Command Prompt:

```cmd
dir "C:\Program Files\ReasonLabs"
```

### Check the Scheduled Task

```powershell
Get-ScheduledTask -TaskName "ReasonLabs Cleanup" -ErrorAction SilentlyContinue
```

No task should be returned after the cleanup task deletes itself.

You can also use:

```cmd
schtasks /query /tn "ReasonLabs Cleanup"
```

Expected result:

```text
ERROR: The system cannot find the file specified.
```

## Successful Remediation Criteria

The workaround can be considered successful when:

- The known ReasonLabs services return Windows error `1060`.
- No ReasonLabs-related services are returned by the CIM service query.
- `C:\Program Files\ReasonLabs` no longer exists.
- The `ReasonLabs Cleanup` scheduled task no longer exists.
- The cleanup log confirms that the removal commands were executed.

## Troubleshooting

### The Script Says It Must Be Run as Administrator

Close PowerShell, reopen it using **Run as administrator**, and run the script again.

### PowerShell Blocks the Script

Use a process-scoped execution policy:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Then run:

```powershell
.\ReasonLabs-Cleanup.ps1
```

### The Service Still Appears as Running

Setting `Start=4` disables future startup but does not always terminate an already-running protected service.

The scheduled task performs the deletion during the next startup, when the service may no longer be active.

### The Program Directory Still Exists

Review:

```powershell
Get-Content "C:\Windows\Temp\ReasonCleanup\cleanup.log"
```

Possible causes include:

- A file is still locked.
- The scheduled task did not run.
- Endpoint security software blocked the deletion.
- The ReasonLabs version uses a different installation path.
- The service recreated files during startup.
- Additional tamper-protection controls are enabled.

### The Scheduled Task Did Not Run

Verify the task before restarting:

```powershell
Get-ScheduledTask -TaskName "ReasonLabs Cleanup"
```

You can also inspect it with:

```cmd
schtasks /query /tn "ReasonLabs Cleanup" /fo LIST /v
```

Confirm that it is configured to run:

```text
At system startup
As SYSTEM
With highest privileges
```

### Some Registry Entries Were Not Found

This may be normal if:

- The entries were already removed.
- The installed version uses different registry paths.
- The product was partially uninstalled previously.

Review the cleanup log to distinguish between expected missing entries and actual failures.

## Security Considerations

Do not treat a poor-reputation result by itself as definitive proof of compromise or malicious behavior.

Before removal, consider collecting:

- Destination IP address or domain.
- DNS resolution history.
- Connection timestamps.
- Process ID and executable path.
- File hashes.
- Digital signature information.
- Proxy, firewall, EDR, or DNS logs.
- Reputation results from multiple independent sources.
- Packet captures, when authorized and operationally appropriate.

Preserve relevant evidence before deleting services or files if the activity may require incident-response, forensic, legal, or compliance review.

## Disclaimer

This script is an unofficial community workaround and is not affiliated with, endorsed by, or supported by ReasonLabs.

Use it at your own risk.

<p align="center">
  <img src="peluk-banner.png" alt="Peluk banner" width="100%">
</p>



The author is not responsible for data loss, system instability, service disruption, security-control conflicts, or any other consequence resulting from the use of this script.
