---
phase: 28-vm-host-ip-dropdown
plan: 01
title: "Network Adapter Enumeration"
subsystem: ui-networking
tags: [powershell, wpf, network, adapter, enumeration]

dependency_graph:
  requires: []
  provides: ["Get-HostNetworkAdapters function", "Network adapter enumeration API"]
  affects: ["28-02 (UI dropdown integration)", "28-03 (Pre-flight validation)"]

tech_stack:
  added: []
  patterns:
    - "Physical adapter enumeration via Get-NetAdapter -Physical"
    - "Primary adapter detection via Get-NetRoute 0.0.0.0/0"
    - "APIPA/loopback filtering with -like wildcards"

file_tracking:
  created:
    - "Tests/Unit/FFUUI.Core.Tests.ps1"
  modified:
    - "FFUDevelopment/FFUUI.Core/FFUUI.Core.psm1"

decisions:
  - key: "adapter-enumeration-api"
    choice: "PSCustomObject array with 6 properties"
    rationale: "Provides all metadata needed for dropdown display and backend operations"
  - key: "primary-detection"
    choice: "Default gateway route (0.0.0.0/0) with lowest metric"
    rationale: "Standard method to identify the adapter with internet connectivity"
  - key: "filtering-approach"
    choice: "String -like wildcards for IP filtering"
    rationale: "Simple, readable pattern matching for 169.254.* and 127.*"

metrics:
  tasks_completed: 2
  tasks_total: 2
  tests_added: 20
  tests_passed: 20
  duration: "4m"
  completed: "2026-01-25"
---

# Phase 28 Plan 01: Network Adapter Enumeration Summary

**One-liner:** Get-HostNetworkAdapters function enumerates physical adapters with IPv4 addresses, filters APIPA/loopback, identifies primary via default gateway route.

## What Was Built

### Task 1: Get-HostNetworkAdapters Function
Created the `Get-HostNetworkAdapters` function in FFUUI.Core.psm1 that:

1. **Enumerates physical adapters** using `Get-NetAdapter -Physical` filtered to `Status -eq 'Up'`
2. **Gets IPv4 addresses** for each adapter via `Get-NetIPAddress -AddressFamily IPv4`
3. **Filters out APIPA** (169.254.x.x) addresses that indicate no DHCP
4. **Filters out loopback** (127.x.x.x) addresses that aren't valid for VM connectivity
5. **Identifies primary adapter** by finding the interface with the default gateway route (0.0.0.0/0)
6. **Returns PSCustomObject array** with properties:
   - `IPAddress` - The IPv4 address string
   - `AdapterName` - Adapter name (e.g., "Ethernet", "Wi-Fi")
   - `Description` - Full adapter description (e.g., "Intel(R) I211 Gigabit Network Connection")
   - `DisplayText` - Formatted string for dropdown: `"192.168.1.100 (Ethernet - Intel(R) I211 Gigabit)"`
   - `InterfaceIndex` - Integer for network operations
   - `IsPrimary` - Boolean indicating default gateway presence

### Task 2: Pester Tests
Created comprehensive test suite with 20 tests covering:

- Return type validation
- Required property presence (all 6 properties)
- DisplayText format validation (`$IP ($Name - $Description)`)
- APIPA address filtering
- Loopback address filtering
- Primary adapter identification (matching/non-matching/multiple adapters)
- Error handling (exception, no adapters, missing route)
- Module export verification

## Commits

| Commit | Type | Description |
|--------|------|-------------|
| cf427fd | feat | Add Get-HostNetworkAdapters function with WriteLog diagnostics |
| 75f45e7 | test | Add 20 Pester tests covering all function behaviors |

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

```
=== Function Export Test ===
[PASS] Get-HostNetworkAdapters is exported

=== Function Output Test ===
Found 1 adapter(s)
IPAddress     AdapterName  Description                              DisplayText
---------     -----------  -----------                              -----------
192.168.4.88  Wi-Fi 3      ASUS USB-BE92 Nano Wireless USB Adapter  192.168.4.88 (Wi-Fi 3 - ASUS USB-BE92...)

=== Property Validation ===
[PASS] Property: IPAddress
[PASS] Property: AdapterName
[PASS] Property: Description
[PASS] Property: DisplayText
[PASS] Property: InterfaceIndex
[PASS] Property: IsPrimary

=== Filtering Validation ===
[PASS] No APIPA addresses in results
[PASS] No loopback addresses in results

=== Primary Adapter Test ===
Primary adapter(s): 1
Primary: 192.168.4.88 (Wi-Fi 3 - ASUS USB-BE92 Nano Wireless USB Adapter)

=== Pester Tests ===
Tests Passed: 20, Failed: 0
```

## Next Phase Readiness

### Plan 02: UI Dropdown Integration

The `Get-HostNetworkAdapters` function is ready to be consumed by the UI:

- **Dropdown population:** Call at UI load, populate ComboBox with `DisplayText` as display member
- **Primary selection:** Auto-select item where `IsPrimary -eq $true` as default
- **Manual entry:** Support "Other" option with custom TextBox fallback (existing pattern)
- **Value extraction:** Use `IPAddress` property as the actual value for config

### Integration Points

```powershell
# UI load handler pattern
$adapters = Get-HostNetworkAdapters
$cmbVMHostIP.ItemsSource = $adapters
$cmbVMHostIP.DisplayMemberPath = 'DisplayText'
$cmbVMHostIP.SelectedValuePath = 'IPAddress'

# Auto-select primary
$primary = $adapters | Where-Object { $_.IsPrimary } | Select-Object -First 1
if ($primary) { $cmbVMHostIP.SelectedItem = $primary }
```
