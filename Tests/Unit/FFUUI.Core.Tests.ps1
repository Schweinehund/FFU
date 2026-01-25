#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Unit tests for FFUUI.Core module functions

.DESCRIPTION
    Pester 5.x tests for the FFUUI.Core.psm1 module functions.
    Tests cover network adapter enumeration for VM Host IP dropdown.

.NOTES
    Phase 28-01: Network Adapter Enumeration
    Tests validate Get-HostNetworkAdapters function behavior including:
    - Return type validation
    - Property presence
    - APIPA/loopback filtering
    - Primary adapter identification
    - Error handling
#>

BeforeAll {
    # Import the module for testing
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\FFUDevelopment\FFUUI.Core\FFUUI.Core.psd1'
    Import-Module $ModulePath -Force -ErrorAction Stop -WarningAction SilentlyContinue
}

Describe 'Get-HostNetworkAdapters' -Tag 'Unit', 'FFUUI.Core', 'NetworkAdapters' {

    Context 'Return type validation' -Tag 'ReturnType' {

        It 'Returns an array or collection type' {
            InModuleScope FFUUI.Core {
                # Mock the underlying cmdlets to return controlled data
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    [PSCustomObject]@{
                        IPAddress      = '192.168.1.100'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                # When there's one result, PowerShell may return a scalar PSCustomObject
                # We wrap in @() to ensure array behavior when iterating
                @($result).Count | Should -BeGreaterOrEqual 1
            }
        }

        It 'Returns array of PSCustomObject when adapters found' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    [PSCustomObject]@{
                        IPAddress      = '192.168.1.100'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result.Count | Should -BeGreaterThan 0
                $result[0] | Should -BeOfType [PSCustomObject]
            }
        }
    }

    Context 'Required properties' -Tag 'Properties' {

        It 'Each result has IPAddress property' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    [PSCustomObject]@{
                        IPAddress      = '192.168.1.100'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result[0].PSObject.Properties.Name | Should -Contain 'IPAddress'
                $result[0].IPAddress | Should -Be '192.168.1.100'
            }
        }

        It 'Each result has AdapterName property' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    [PSCustomObject]@{
                        IPAddress      = '192.168.1.100'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result[0].PSObject.Properties.Name | Should -Contain 'AdapterName'
                $result[0].AdapterName | Should -Be 'Ethernet'
            }
        }

        It 'Each result has Description property' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    [PSCustomObject]@{
                        IPAddress      = '192.168.1.100'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result[0].PSObject.Properties.Name | Should -Contain 'Description'
                $result[0].Description | Should -Be 'Test Adapter'
            }
        }

        It 'Each result has DisplayText property' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    [PSCustomObject]@{
                        IPAddress      = '192.168.1.100'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result[0].PSObject.Properties.Name | Should -Contain 'DisplayText'
            }
        }

        It 'Each result has InterfaceIndex property' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    [PSCustomObject]@{
                        IPAddress      = '192.168.1.100'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result[0].PSObject.Properties.Name | Should -Contain 'InterfaceIndex'
                $result[0].InterfaceIndex | Should -Be 10
            }
        }

        It 'Each result has IsPrimary property' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    [PSCustomObject]@{
                        IPAddress      = '192.168.1.100'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result[0].PSObject.Properties.Name | Should -Contain 'IsPrimary'
                $result[0].IsPrimary | Should -BeOfType [bool]
            }
        }
    }

    Context 'DisplayText format validation' -Tag 'DisplayText' {

        It 'DisplayText follows format: IP (AdapterName - Description)' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Intel(R) I211 Gigabit'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    [PSCustomObject]@{
                        IPAddress      = '192.168.1.100'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result[0].DisplayText | Should -Be '192.168.1.100 (Ethernet - Intel(R) I211 Gigabit)'
            }
        }
    }

    Context 'APIPA address filtering' -Tag 'Filtering', 'APIPA' {

        It 'Filters out APIPA addresses (169.254.x.x)' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    # Return only an APIPA address
                    [PSCustomObject]@{
                        IPAddress      = '169.254.100.50'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result.Count | Should -Be 0
            }
        }

        It 'Does not include APIPA addresses in results' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    # Return both valid and APIPA addresses
                    @(
                        [PSCustomObject]@{
                            IPAddress      = '192.168.1.100'
                            InterfaceIndex = 10
                            AddressFamily  = 'IPv4'
                        },
                        [PSCustomObject]@{
                            IPAddress      = '169.254.50.100'
                            InterfaceIndex = 10
                            AddressFamily  = 'IPv4'
                        }
                    )
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result.Count | Should -Be 1
                $result[0].IPAddress | Should -Be '192.168.1.100'
            }
        }
    }

    Context 'Loopback address filtering' -Tag 'Filtering', 'Loopback' {

        It 'Filters out loopback addresses (127.x.x.x)' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    # Return only a loopback address
                    [PSCustomObject]@{
                        IPAddress      = '127.0.0.1'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result.Count | Should -Be 0
            }
        }

        It 'Filters out any 127.x.x.x address' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    @(
                        [PSCustomObject]@{
                            IPAddress      = '192.168.1.100'
                            InterfaceIndex = 10
                            AddressFamily  = 'IPv4'
                        },
                        [PSCustomObject]@{
                            IPAddress      = '127.100.50.25'
                            InterfaceIndex = 10
                            AddressFamily  = 'IPv4'
                        }
                    )
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result.Count | Should -Be 1
                $result[0].IPAddress | Should -Be '192.168.1.100'
            }
        }
    }

    Context 'Primary adapter identification' -Tag 'Primary' {

        It 'Marks adapter with default gateway as IsPrimary = true' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10  # Primary interface
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10  # Matches default route
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    [PSCustomObject]@{
                        IPAddress      = '192.168.1.100'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result[0].IsPrimary | Should -Be $true
            }
        }

        It 'Marks adapter without default gateway as IsPrimary = false' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 20  # Different interface
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10  # Does not match default route
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    [PSCustomObject]@{
                        IPAddress      = '192.168.1.100'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result[0].IsPrimary | Should -Be $false
            }
        }

        It 'Correctly identifies primary among multiple adapters' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10  # Primary is interface 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    @(
                        [PSCustomObject]@{
                            Name                 = 'Ethernet'
                            InterfaceDescription = 'Primary Adapter'
                            ifIndex              = 10  # Primary
                            Status               = 'Up'
                        },
                        [PSCustomObject]@{
                            Name                 = 'Wi-Fi'
                            InterfaceDescription = 'Secondary Adapter'
                            ifIndex              = 20  # Not primary
                            Status               = 'Up'
                        }
                    )
                }
                Mock Get-NetIPAddress {
                    param($InterfaceIndex)
                    if ($InterfaceIndex -eq 10) {
                        [PSCustomObject]@{
                            IPAddress      = '192.168.1.100'
                            InterfaceIndex = 10
                            AddressFamily  = 'IPv4'
                        }
                    }
                    elseif ($InterfaceIndex -eq 20) {
                        [PSCustomObject]@{
                            IPAddress      = '10.0.0.50'
                            InterfaceIndex = 20
                            AddressFamily  = 'IPv4'
                        }
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $primary = $result | Where-Object { $_.IsPrimary -eq $true }
                $secondary = $result | Where-Object { $_.IsPrimary -eq $false }

                $primary.Count | Should -Be 1
                $primary.IPAddress | Should -Be '192.168.1.100'
                $secondary.Count | Should -Be 1
                $secondary.IPAddress | Should -Be '10.0.0.50'
            }
        }
    }

    Context 'Error handling' -Tag 'ErrorHandling' {

        It 'Returns empty array when Get-NetAdapter throws' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    throw 'Network adapter error'
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                # When exception occurs, function returns @() which may be $null or empty
                @($result).Count | Should -Be 0
            }
        }

        It 'Returns empty array when no physical adapters are up' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    [PSCustomObject]@{
                        DestinationPrefix = '0.0.0.0/0'
                        InterfaceIndex    = 10
                        RouteMetric       = 25
                    }
                }
                Mock Get-NetAdapter {
                    # Return adapter with 'Disconnected' status
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Disconnected'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                $result.Count | Should -Be 0
            }
        }

        It 'Handles missing default route gracefully' {
            InModuleScope FFUUI.Core {
                Mock Get-NetRoute {
                    # Return nothing - no default route
                    $null
                }
                Mock Get-NetAdapter {
                    [PSCustomObject]@{
                        Name                 = 'Ethernet'
                        InterfaceDescription = 'Test Adapter'
                        ifIndex              = 10
                        Status               = 'Up'
                    }
                }
                Mock Get-NetIPAddress {
                    [PSCustomObject]@{
                        IPAddress      = '192.168.1.100'
                        InterfaceIndex = 10
                        AddressFamily  = 'IPv4'
                    }
                }
                Mock WriteLog {}

                $result = Get-HostNetworkAdapters
                # Should still return adapter, just with IsPrimary = false
                $result.Count | Should -Be 1
                $result[0].IsPrimary | Should -Be $false
            }
        }
    }

    Context 'Function export' -Tag 'Export' {

        It 'Get-HostNetworkAdapters is exported from FFUUI.Core module' {
            $exportedFunctions = (Get-Module FFUUI.Core).ExportedFunctions.Keys
            $exportedFunctions | Should -Contain 'Get-HostNetworkAdapters'
        }
    }
}
