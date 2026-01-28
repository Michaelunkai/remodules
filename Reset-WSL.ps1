#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Resets WSL by disabling all features, rebooting, re-enabling, and rebooting again.
.DESCRIPTION
    Phase 1: Disables WSL features and schedules Phase 2, then reboots.
    Phase 2: Re-enables WSL features, removes scheduled task, then reboots.
#>

$TaskName = "WSL-Reset-Phase2"
$ScriptPath = $MyInvocation.MyCommand.Path
$Phase2Flag = "$env:TEMP\wsl-reset-phase2.flag"

$Features = @(
    "Microsoft-Windows-Subsystem-Linux",
    "VirtualMachinePlatform",
    "HypervisorPlatform",
    "Microsoft-Hyper-V-All",
    "Microsoft-Hyper-V",
    "Microsoft-Hyper-V-Tools-All",
    "Microsoft-Hyper-V-Management-PowerShell",
    "Microsoft-Hyper-V-Hypervisor",
    "Microsoft-Hyper-V-Services",
    "Microsoft-Hyper-V-Management-Clients"
)

function Disable-WSLFeatures {
    Write-Host "=== WSL RESET - PHASE 1 ===" -ForegroundColor Cyan
    Write-Host "Disabling WSL-related features..." -ForegroundColor Yellow

    foreach ($feature in $Features) {
        $state = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
        if ($state -and $state.State -eq "Enabled") {
            Write-Host "  Disabling: $feature" -ForegroundColor Gray
            Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction SilentlyContinue
        } else {
            Write-Host "  Skipping (not enabled): $feature" -ForegroundColor DarkGray
        }
    }

    # Create phase 2 flag
    New-Item -Path $Phase2Flag -ItemType File -Force | Out-Null

    # Schedule Phase 2 to run at next logon
    Write-Host "Scheduling Phase 2 for next boot..." -ForegroundColor Yellow
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings | Out-Null

    Write-Host "`nPhase 1 complete. Rebooting in 10 seconds..." -ForegroundColor Green
    Write-Host "Press Ctrl+C to cancel." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}

function Enable-WSLFeatures {
    Write-Host "=== WSL RESET - PHASE 2 ===" -ForegroundColor Cyan
    Write-Host "Re-enabling WSL-related features..." -ForegroundColor Yellow

    foreach ($feature in $Features) {
        $state = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
        if ($state) {
            Write-Host "  Enabling: $feature" -ForegroundColor Gray
            Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -All -ErrorAction SilentlyContinue
        }
    }

    # Cleanup
    Remove-Item -Path $Phase2Flag -Force -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    Write-Host "`nPhase 2 complete. Final reboot in 10 seconds..." -ForegroundColor Green
    Write-Host "Press Ctrl+C to cancel." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}

# Main logic - determine which phase to run
if (Test-Path $Phase2Flag) {
    Enable-WSLFeatures
} else {
    Disable-WSLFeatures
}
