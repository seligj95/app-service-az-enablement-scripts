#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Checks zone redundancy status for specific App Service Environments by resource ID
    
.DESCRIPTION
    This script reads App Service Environment resource IDs from a file and checks their zone redundancy status.
    It validates region support for zone redundancy and shows the current configuration.
    
    For more information about App Service Environment reliability and zone redundancy:
    - ASE Reliability Guide: https://learn.microsoft.com/en-us/azure/reliability/reliability-app-service-environment
    - Configure Zone Redundancy: https://learn.microsoft.com/en-us/azure/app-service/environment/configure-zone-redundancy-environment?tabs=portal
    
.PARAMETER FilePath
    Path to the file containing App Service Environment resource IDs (one per line)
    
.EXAMPLE
    .\Check-AppServiceEnvironmentZoneRedundancy.ps1 -FilePath "ase_resource_ids.txt"
    
.NOTES
    Requires Azure CLI to be installed and authenticated.
    All resource IDs must be from the currently authenticated subscription.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath
)

# Define regions that support zone redundancy for App Service Environments
# Based on Microsoft documentation - Azure regions list (learn.microsoft.com/azure/reliability/regions-list)
$ZoneRedundantRegions = @(
    "australiaeast",
    "brazilsouth",
    "canadacentral",
    "centralindia",
    "centralus",
    "eastasia",
    "eastus",
    "eastus2",
    "francecentral",
    "germanywestcentral",
    "japaneast",
    "koreacentral",
    "northcentralus",
    "northeurope",
    "norwayeast",
    "southafricanorth",
    "southcentralus",
    "southeastasia",
    "swedencentral",
    "switzerlandnorth",
    "uaenorth",
    "uksouth",
    "westcentralus",
    "westeurope",
    "westus2",
    "westus3"
)

function Test-RegionSupportsZones {
    param([string]$Region)
    return $ZoneRedundantRegions -contains $Region.ToLower().Replace(' ', '')
}

function Parse-AseResourceId {
    param([string]$ResourceId)
    
    # Parse resource ID format: /subscriptions/{subscription-id}/resourceGroups/{rg-name}/providers/Microsoft.Web/hostingEnvironments/{ase-name}
    if ($ResourceId -match '^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.Web/hostingEnvironments/([^/]+)$') {
        return @{
            SubscriptionId = $Matches[1]
            ResourceGroup = $Matches[2]
            AseName = $Matches[3]
            IsValid = $true
        }
    }
    
    return @{ IsValid = $false }
}

# Main script execution
Write-Host "=== App Service Environment Zone Redundancy Check ===" -ForegroundColor Blue
Write-Host ""

# Check if Azure CLI is installed
try {
    $null = Get-Command az -ErrorAction Stop
} catch {
    Write-Host "Error: Azure CLI is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
}

# Check if user is logged in
try {
    $currentAccount = az account show --query "{subscriptionId:id, subscriptionName:name}" -o json 2>$null | ConvertFrom-Json
} catch {
    Write-Host "Error: Not logged in to Azure CLI" -ForegroundColor Red
    Write-Host "Please run 'az login' to authenticate"
    exit 1
}

Write-Host "Current Subscription: $($currentAccount.subscriptionName) ($($currentAccount.subscriptionId))" -ForegroundColor Blue
Write-Host ""

# Check if file exists
if (-not (Test-Path $FilePath)) {
    Write-Host "Error: File '$FilePath' not found" -ForegroundColor Red
    exit 1
}

# Read resource IDs from file
Write-Host "Reading ASE resource IDs from file: $FilePath" -ForegroundColor Yellow
$resourceIds = Get-Content $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }

if ($resourceIds.Count -eq 0) {
    Write-Host "No ASE resource IDs found in file. Exiting." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($resourceIds.Count) App Service Environment(s) to check" -ForegroundColor Blue
Write-Host ""

# Create results table header
$headerFormat = "{0,-30} {1,-20} {2,-12} {3,-8} {4,-20} {5,-12}"
Write-Host ($headerFormat -f "App Service Environment", "Resource Group", "Location", "Max AZs", "Zone Redundancy", "Eligible") -ForegroundColor White
Write-Host ($headerFormat -f "==============================", "====================", "============", "========", "====================", "============") -ForegroundColor White

# Initialize counters
$totalAses = 0
$zoneRedundantAses = 0
$nonZoneRedundantAses = 0
$regionNotSupported = 0
$maxZonesOne = 0
$maxZonesZero = 0
$maxZonesUnknown = 0
$eligibleForConversion = 0

# Process each resource ID
foreach ($resourceId in $resourceIds) {
    $totalAses++
    
    # Parse resource ID
    $parsed = Parse-AseResourceId -ResourceId $resourceId
    
    if (-not $parsed.IsValid) {
        $displayName = ($resourceId -split '/')[-1].Substring(0, [Math]::Min(29, ($resourceId -split '/')[-1].Length))
        Write-Host ($headerFormat -f $displayName, "-", "-", "-", "Invalid Resource ID Format", "No") -ForegroundColor Red
        continue
    }
    
    # Validate subscription matches current
    if ($parsed.SubscriptionId -ne $currentAccount.subscriptionId) {
        $displayName = $parsed.AseName.Substring(0, [Math]::Min(29, $parsed.AseName.Length))
        $displayRg = $parsed.ResourceGroup.Substring(0, [Math]::Min(19, $parsed.ResourceGroup.Length))
        Write-Host ($headerFormat -f $displayName, $displayRg, "-", "-", "Different Subscription", "No") -ForegroundColor Red
        continue
    }
    
    # Get App Service Environment details
    try {
        $aseDetailsJson = az resource show --ids $resourceId --query "{location:location, zoneRedundant:properties.zoneRedundant, maximumNumberOfZones:properties.maximumNumberOfZones}" -o json 2>$null
        $aseDetails = $aseDetailsJson | ConvertFrom-Json
        
        $location = $aseDetails.location
        $zoneRedundant = $aseDetails.zoneRedundant
        $maximumNumberOfZones = $aseDetails.maximumNumberOfZones
        
        # Normalize location for comparison
        $locationNormalized = $location.ToLower().Replace(' ', '')
        
        # Check support
        $regionSupportsZones = Test-RegionSupportsZones -Region $locationNormalized
        
        # Determine status
        if (-not $regionSupportsZones) {
            $zoneStatus = "Region Not Supported"
            $color = "Yellow"
            $regionNotSupported++
        }
        elseif ($maximumNumberOfZones -eq $null) {
            $zoneStatus = "Max Zones Unknown"
            $color = "Yellow"
            $maxZonesUnknown++
        }
        elseif ($maximumNumberOfZones -eq 0) {
            $zoneStatus = "Max Zones Zero"
            $color = "Yellow"
            $maxZonesZero++
        }
        elseif ($maximumNumberOfZones -eq 1) {
            $zoneStatus = "Requires New ASE"
            $color = "Magenta"
            $maxZonesOne++
        }
        elseif ($zoneRedundant -eq $true) {
            $zoneStatus = "Enabled"
            $color = "Green"
            $zoneRedundantAses++
        }
        elseif ($zoneRedundant -eq $false) {
            $zoneStatus = "Disabled"
            $color = "Red"
            $nonZoneRedundantAses++
        }
        else {
            $zoneStatus = "Status Unknown"
            $color = "Yellow"
        }
        
        # Determine eligibility for zone redundancy
        $eligibleText = "No"
        
        if ($zoneRedundant -eq $true) {
            $eligibleText = "Already ZR"
        }
        elseif ($maximumNumberOfZones -eq $null) {
            $eligibleText = "Unknown"
        }
        elseif ($maximumNumberOfZones -eq 0) {
            $eligibleText = "No"
        }
        elseif ($regionSupportsZones -and $maximumNumberOfZones -gt 1 -and $zoneRedundant -eq $false) {
            $eligibleText = "Yes"
            $eligibleForConversion++
        }
        
        # Display result
        $displayName = $parsed.AseName.Substring(0, [Math]::Min(29, $parsed.AseName.Length))
        $displayRg = $parsed.ResourceGroup.Substring(0, [Math]::Min(19, $parsed.ResourceGroup.Length))
        $displayMaxZones = if ($maximumNumberOfZones -eq $null) { "null" } else { $maximumNumberOfZones.ToString() }
        
        Write-Host ($headerFormat -f $displayName, $displayRg, $location, $displayMaxZones, $zoneStatus, $eligibleText) -ForegroundColor $color
        
    }
    catch {
        $displayName = $parsed.AseName.Substring(0, [Math]::Min(29, $parsed.AseName.Length))
        $displayRg = $parsed.ResourceGroup.Substring(0, [Math]::Min(19, $parsed.ResourceGroup.Length))
        Write-Host ($headerFormat -f $displayName, $displayRg, "Unknown", "-", "Error fetching details", "No") -ForegroundColor Red
    }
}

# Display summary
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Blue
Write-Host "Total App Service Environments: $totalAses"
Write-Host "Zone Redundancy Enabled: $zoneRedundantAses" -ForegroundColor Green
Write-Host "Zone Redundancy Disabled: $nonZoneRedundantAses" -ForegroundColor Red
Write-Host "Requires New ASE: $maxZonesOne" -ForegroundColor Magenta
Write-Host "Max Zones Zero: $maxZonesZero" -ForegroundColor Yellow
Write-Host "Max Zones Unknown: $maxZonesUnknown" -ForegroundColor Yellow
Write-Host "Region Not Supported: $regionNotSupported" -ForegroundColor Yellow

Write-Host ""
Write-Host "Status Explanations:" -ForegroundColor Blue
Write-Host "• Enabled: Zone redundancy is configured and active" -ForegroundColor Green
Write-Host "• Disabled: Zone redundancy is supported but not enabled" -ForegroundColor Red
Write-Host "• Requires New ASE: ASE supports only 1 zone - redeploy ASE in new resource group" -ForegroundColor Magenta
Write-Host "• Max Zones Zero: ASE does not support zones - check ASE tier/configuration" -ForegroundColor Yellow
Write-Host "• Max Zones Unknown: Unable to determine zone support - check ASE configuration" -ForegroundColor Yellow
Write-Host "• Region Not Supported: The Azure region doesn't support zone redundancy" -ForegroundColor Yellow
Write-Host ""
Write-Host "Eligibility Explanations:" -ForegroundColor Blue
Write-Host "• Already ZR: ASE is already zone redundant" -ForegroundColor Green
Write-Host "• Yes: ASE can be converted to zone redundant" -ForegroundColor Yellow
Write-Host "• No: ASE cannot be converted (check Zone Redundancy column for reason)" -ForegroundColor Red
Write-Host "• Unknown: Cannot determine eligibility due to missing zone information" -ForegroundColor Yellow
Write-Host ""
Write-Host "Note: ASE zone redundancy conversion can take 12-24 hours to complete." -ForegroundColor Blue

# Ask user if they want to proceed with conversion
Write-Host ""
Write-Host "=== Zone Redundancy Conversion ===" -ForegroundColor Blue
if ($eligibleForConversion -gt 0) {
    Write-Host "Found $eligibleForConversion App Service Environment(s) that can be converted to zone redundant." -ForegroundColor Yellow
    Write-Host "This will:"
    Write-Host "• Enable zone redundancy on eligible ASEs"
    Write-Host "• Process can take 12-24 hours to complete"
    Write-Host "• No downtime or performance impact during conversion"
    Write-Host ""
    $proceed = Read-Host "Do you want to proceed with the conversion? (y/N)"
    
    if ($proceed -eq 'y' -or $proceed -eq 'Y' -or $proceed -eq 'yes' -or $proceed -eq 'YES') {
        Write-Host ""
        Write-Host "=== Converting ASEs to Zone Redundant ===" -ForegroundColor Blue
        
        # Re-process resource IDs for conversion
        foreach ($resourceId in $resourceIds) {
            $parsed = Parse-AseResourceId -ResourceId $resourceId
            
            if (-not $parsed.IsValid -or $parsed.SubscriptionId -ne $currentAccount.subscriptionId) {
                continue
            }
            
            # Get ASE details again
            try {
                $aseDetailsJson = az resource show --ids $resourceId --query "{location:location, zoneRedundant:properties.zoneRedundant, maximumNumberOfZones:properties.maximumNumberOfZones}" -o json 2>$null
                $aseDetails = $aseDetailsJson | ConvertFrom-Json
                
                $location = $aseDetails.location
                $zoneRedundant = $aseDetails.zoneRedundant
                $maximumNumberOfZones = $aseDetails.maximumNumberOfZones
                
                # Check if this ASE is eligible for conversion
                $locationNormalized = $location.ToLower().Replace(' ', '')
                $regionSupportsZones = Test-RegionSupportsZones -Region $locationNormalized
                
                # Check if eligible for conversion
                if ($maximumNumberOfZones -eq $null) {
                    Write-Host "⚠ Cannot convert $($parsed.AseName) - Max zones information unavailable" -ForegroundColor Yellow
                    continue
                }
                elseif ($maximumNumberOfZones -eq 0) {
                    Write-Host "⚠ Cannot convert $($parsed.AseName) - ASE does not support zones" -ForegroundColor Yellow
                    continue
                }
                elseif ($regionSupportsZones -and $maximumNumberOfZones -gt 1 -and $zoneRedundant -eq $false) {
                    
                    Write-Host "Initiating conversion: $($parsed.AseName)" -ForegroundColor Yellow
                    
                    try {
                        # Execute the conversion command
                        $result = az resource update --ids $resourceId --set properties.zoneRedundant=true 2>&1
                        
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "✓ Successfully initiated zone redundancy conversion for $($parsed.AseName)" -ForegroundColor Green
                        } else {
                            Write-Host "✗ Failed to initiate conversion for $($parsed.AseName): $result" -ForegroundColor Red
                        }
                    }
                    catch {
                        Write-Host "✗ Error initiating conversion for $($parsed.AseName): $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
            catch {
                Write-Host "✗ Error processing $($parsed.AseName): Unable to retrieve ASE details" -ForegroundColor Red
            }
        }
        
        Write-Host ""
        Write-Host "=== Conversion Commands Initiated ===" -ForegroundColor Blue
        Write-Host "Zone redundancy conversion has been initiated for eligible ASEs." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Important Notes:" -ForegroundColor Blue
        Write-Host "• Conversions take 12-24 hours to complete" -ForegroundColor Yellow
        Write-Host "• No downtime or performance impact during conversion" -ForegroundColor Yellow
        Write-Host "• Check conversion status in one of these ways:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Option 1 - Azure Portal:" -ForegroundColor Cyan
        Write-Host "  Go to your ASE → Overview blade → Check status" -ForegroundColor White
        Write-Host ""
        Write-Host "Option 2 - Azure CLI:" -ForegroundColor Cyan
        Write-Host "  az resource show --ids [ASE_RESOURCE_ID] --query 'properties.status'" -ForegroundColor White
        Write-Host "  Example:" -ForegroundColor White
        foreach ($resourceId in $resourceIds) {
            $parsed = Parse-AseResourceId -ResourceId $resourceId
            if ($parsed.IsValid) {
                Write-Host "  az resource show --ids '$resourceId' --query 'properties.status'" -ForegroundColor Gray
                break # Just show one example
            }
        }
        Write-Host ""
        Write-Host "Re-run this script later to see the updated zone redundancy status." -ForegroundColor Yellow
    }
    else {
        Write-Host "Conversion cancelled by user." -ForegroundColor Yellow
    }
} else {
    Write-Host "No ASEs are eligible for automatic conversion to zone redundant." -ForegroundColor Yellow
}
