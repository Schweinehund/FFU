#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Enables SMB and ICMP (ping) firewall rules for FFU capture connectivity.

.DESCRIPTION
    Enables inbound SMB (TCP 445) and ICMPv4 Echo Request (ping) rules across
    Domain, Private, and Public firewall profiles. This ensures the capture VM
    can connect to the FFUCaptureShare and that basic network diagnostics work.

.EXAMPLE
    .\Enable-FFUFirewallRules.ps1
#>

[CmdletBinding()]
param()

Write-Host "Enabling SMB and Ping firewall rules for all profiles..." -ForegroundColor Cyan

# Enable SMB inbound (TCP 445) - use built-in File and Printer Sharing rules
$smbRules = Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue |
    Where-Object { $_.Direction -eq 'Inbound' -and $_.DisplayName -match 'SMB-In' }

if ($smbRules) {
    foreach ($rule in $smbRules) {
        Set-NetFirewallRule -Name $rule.Name -Profile Domain, Private, Public -Enabled True
        Write-Host "  Enabled: $($rule.DisplayName)" -ForegroundColor Green
    }
}
else {
    # Create rule if built-in rules not found
    New-NetFirewallRule -DisplayName "FFU Builder - SMB Inbound" `
        -Direction Inbound -Protocol TCP -LocalPort 445 `
        -Profile Domain, Private, Public -Action Allow -Enabled True | Out-Null
    Write-Host "  Created: FFU Builder - SMB Inbound (TCP 445)" -ForegroundColor Green
}

# Enable ICMPv4 Echo Request (ping) - use built-in Core Networking rules
$pingRules = Get-NetFirewallRule -DisplayGroup "Core Networking Diagnostics" -ErrorAction SilentlyContinue |
    Where-Object { $_.Direction -eq 'Inbound' -and $_.DisplayName -match 'ICMP.*Echo Request' }

if ($pingRules) {
    foreach ($rule in $pingRules) {
        Set-NetFirewallRule -Name $rule.Name -Profile Domain, Private, Public -Enabled True
        Write-Host "  Enabled: $($rule.DisplayName)" -ForegroundColor Green
    }
}
else {
    # Create rule if built-in rules not found
    New-NetFirewallRule -DisplayName "FFU Builder - ICMPv4 Echo Request" `
        -Direction Inbound -Protocol ICMPv4 -IcmpType 8 `
        -Profile Domain, Private, Public -Action Allow -Enabled True | Out-Null
    Write-Host "  Created: FFU Builder - ICMPv4 Echo Request (Ping)" -ForegroundColor Green
}

Write-Host "`nFirewall rules enabled for Domain, Private, and Public profiles." -ForegroundColor Cyan
Write-Host "SMB (TCP 445) and Ping (ICMPv4) are now allowed inbound." -ForegroundColor Cyan
