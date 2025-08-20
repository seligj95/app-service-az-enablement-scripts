#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Checks zone redundancy status for specific App Service Plans by resource ID
    
.DESCRIPTION
    This script reads App Service Plan resource IDs from a file and checks their zone redundancy status.
    It validates region and SKU support for zone redundancy and shows the current configuration.
    
    For more information about App Service reliability and zone redundancy:
    - App Service Reliability Guide: https://learn.microsoft.com/en-us/azure/reliability/reliability-app-service
    - Configure Zone Redundancy: https://learn.microsoft.com/en-us/azure/app-service/configure-zone-redundancy?tabs=portal
    
    Note: If using Isolated v2 plans, also review the App Service Environment documentation:
    - ASE Reliability Guide: https://learn.microsoft.com/en-us/azure/reliability/reliability-app-service-environment
    - Configure ASE Zone Redundancy: https://learn.microsoft.com/en-us/azure/app-service/environment/configure-zone-redundancy-environment?tabs=portal
    
.PARAMETER FilePath
    Path to the file containing App Service Plan resource IDs (one per line)
    
.EXAMPLE
    .\Check-AppServicePlanZoneRedundancy.ps1 -FilePath "resource_ids.txt"
    
.NOTES
    Requires Azure CLI to be installed and authenticated.
    All resource IDs must be from the currently authenticated subscription.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath
)

# Define regions that support zone redundancy for App Service Plans
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

# Define SKUs that support zone redundancy
$ZoneRedundantSkus = @(
    "P1v2", "P2v2", "P3v2",
    "P0v3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3",
    "P0v4", "P1v4", "P2v4", "P3v4", "P1mv4", "P2mv4", "P3mv4", "P4mv4", "P5mv4",
    "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2", "I1mv2", "I2mv2", "I3mv2", "I4mv2", "I5mv2"
)

function Test-RegionSupportsZones {
    param([string]$Region)
    return $ZoneRedundantRegions -contains $Region.ToLower().Replace(' ', '')
}

function Test-SkuSupportsZones {
    param([string]$Sku)
    return $ZoneRedundantSkus -contains $Sku
}

function Test-IsIsolatedV2Sku {
    param([string]$Sku)
    return $Sku -match '^I\d+v2$|^I\d+mv2$'
}

function Get-AppServiceEnvironmentDetails {
    param([string]$HostingEnvironmentId)
    
    if (-not $HostingEnvironmentId) {
        return $null
    }
    
    try {
        # Use the full resource ID to query the ASE directly
        $aseDetailsJson = az resource show --ids $HostingEnvironmentId --query "properties.zoneRedundant" -o json 2>$null
        
        if ([string]::IsNullOrWhiteSpace($aseDetailsJson)) {
            return $null
        }
        
        $zoneRedundantValue = $aseDetailsJson | ConvertFrom-Json
        
        # Handle different possible values
        if ($zoneRedundantValue -eq $null) {
            $zoneRedundantValue = $false
        }
        
        return @{ zoneRedundant = $zoneRedundantValue }
        
    }
    catch {
        return $null
    }
}

function Parse-ResourceId {
    param([string]$ResourceId)
    
    # Parse resource ID format: /subscriptions/{subscription-id}/resourceGroups/{rg-name}/providers/Microsoft.Web/server[Ff]arms/{plan-name}
    if ($ResourceId -match '^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.Web/server[Ff]arms/([^/]+)$') {
        return @{
            SubscriptionId = $Matches[1]
            ResourceGroup = $Matches[2]
            PlanName = $Matches[3]
            IsValid = $true
        }
    }
    
    return @{ IsValid = $false }
}

# Main script execution
Write-Host "=== App Service Plan Zone Redundancy Check ===" -ForegroundColor Blue
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
Write-Host "Reading resource IDs from file: $FilePath" -ForegroundColor Yellow
$resourceIds = Get-Content $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }

if ($resourceIds.Count -eq 0) {
    Write-Host "No resource IDs found in file. Exiting." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($resourceIds.Count) App Service Plan(s) to check" -ForegroundColor Blue
Write-Host ""

# Create results table header
$headerFormat = "{0,-30} {1,-20} {2,-12} {3,-8} {4,-9} {5,-8} {6,-12} {7,-20} {8,-12}"
Write-Host ($headerFormat -f "App Service Plan", "Resource Group", "Location", "SKU", "Instances", "Max AZs", "Current AZs", "Zone Redundancy", "Eligible") -ForegroundColor White
Write-Host ($headerFormat -f "==============================", "====================", "============", "========", "=========", "========", "============", "====================", "============") -ForegroundColor White

# Initialize counters
$totalPlans = 0
$zoneRedundantPlans = 0
$nonZoneRedundantPlans = 0
$regionNotSupported = 0
$skuNotSupported = 0
$requiresNewPlan = 0
$aseNotZoneRedundant = 0

# Process each resource ID
foreach ($resourceId in $resourceIds) {
    $totalPlans++
    
    # Parse resource ID
    $parsed = Parse-ResourceId -ResourceId $resourceId
    
    if (-not $parsed.IsValid) {
        $displayName = ($resourceId -split '/')[-1].Substring(0, [Math]::Min(29, ($resourceId -split '/')[-1].Length))
        Write-Host ($headerFormat -f $displayName, "-", "-", "-", "-", "-", "-", "Invalid Resource ID Format", "No") -ForegroundColor Red
        continue
    }
    
    # Validate subscription matches current
    if ($parsed.SubscriptionId -ne $currentAccount.subscriptionId) {
        $displayName = $parsed.PlanName.Substring(0, [Math]::Min(29, $parsed.PlanName.Length))
        $displayRg = $parsed.ResourceGroup.Substring(0, [Math]::Min(19, $parsed.ResourceGroup.Length))
        Write-Host ($headerFormat -f $displayName, $displayRg, "-", "-", "-", "-", "-", "Different Subscription", "No") -ForegroundColor Red
        continue
    }
    
    # Get App Service Plan details
    try {
        $planDetailsJson = az appservice plan show --ids $resourceId --query "{location:location, sku:sku.name, skuCapacity:sku.capacity, zoneRedundant:properties.zoneRedundant, maximumNumberOfZones:properties.maximumNumberOfZones, currentNumberOfZonesUtilized:properties.currentNumberOfZonesUtilized, hostingEnvironmentId:properties.hostingEnvironmentId, hostingEnvironmentProfile:properties.hostingEnvironmentProfile.name}" -o json 2>$null
        $planDetails = $planDetailsJson | ConvertFrom-Json
        
        $location = $planDetails.location
        $sku = $planDetails.sku
        $skuCapacity = $planDetails.skuCapacity
        $zoneRedundant = $planDetails.zoneRedundant
        $maximumNumberOfZones = $planDetails.maximumNumberOfZones
        $currentNumberOfZonesUtilized = $planDetails.currentNumberOfZonesUtilized
        $hostingEnvironmentId = $planDetails.hostingEnvironmentId
        $hostingEnvironmentProfile = $planDetails.hostingEnvironmentProfile
        
        # Normalize location for comparison
        $locationNormalized = $location.ToLower().Replace(' ', '')
        
        # Check support
        $regionSupportsZones = Test-RegionSupportsZones -Region $locationNormalized
        $skuSupportsZones = Test-SkuSupportsZones -Sku $sku
        $isIsolatedV2 = Test-IsIsolatedV2Sku -Sku $sku
        
        # For Isolated v2 plans, check ASE zone redundancy
        $aseZoneRedundant = $null
        if ($isIsolatedV2 -and $hostingEnvironmentId) {
            $aseDetails = Get-AppServiceEnvironmentDetails -HostingEnvironmentId $hostingEnvironmentId
            if ($aseDetails) {
                $aseZoneRedundant = $aseDetails.zoneRedundant
            }
        }
        
        # Determine status
        if (-not $regionSupportsZones) {
            $zoneStatus = "Region Not Supported"
            $color = "Yellow"
            $regionNotSupported++
        }
        elseif (-not $skuSupportsZones) {
            $zoneStatus = "SKU Not Supported"
            $color = "Yellow"
            $skuNotSupported++
        }
        elseif ($maximumNumberOfZones -eq 1) {
            $zoneStatus = "Requires New Plan"
            $color = "Magenta"
            $requiresNewPlan++
        }
        elseif ($isIsolatedV2 -and $aseZoneRedundant -eq $false) {
            $zoneStatus = "ASE Not Zone Redundant"
            $color = "DarkRed"
            $aseNotZoneRedundant++
        }
        elseif ($isIsolatedV2 -and $aseZoneRedundant -eq $null) {
            $zoneStatus = "ASE Status Unknown"
            $color = "Yellow"
        }
        elseif ($zoneRedundant -eq $true) {
            $zoneStatus = "Enabled"
            $color = "Green"
            $zoneRedundantPlans++
        }
        elseif ($zoneRedundant -eq $false) {
            $zoneStatus = "Disabled"
            $color = "Red"
            $nonZoneRedundantPlans++
        }
        else {
            $zoneStatus = "Status Unknown"
            $color = "Yellow"
        }
        
        # Determine eligibility for zone redundancy conversion
        $isEligible = $false
        $eligibleText = "No"
        
        if ($zoneRedundant -eq $true) {
            $eligibleText = "Already ZR"
        }
        elseif ($regionSupportsZones -and $skuSupportsZones -and $maximumNumberOfZones -gt 1 -and 
                (-not $isIsolatedV2 -or $aseZoneRedundant -eq $true)) {
            $isEligible = $true
            $eligibleText = "Yes"
        }
        
        # Display result
        $displayName = $parsed.PlanName.Substring(0, [Math]::Min(29, $parsed.PlanName.Length))
        $displayRg = $parsed.ResourceGroup.Substring(0, [Math]::Min(19, $parsed.ResourceGroup.Length))
        $displayCapacity = if ($skuCapacity -eq $null) { "null" } else { $skuCapacity.ToString() }
        $displayMaxZones = if ($maximumNumberOfZones -eq $null) { "null" } else { $maximumNumberOfZones.ToString() }
        $displayCurrentZones = if ($currentNumberOfZonesUtilized -eq $null) { "null" } else { $currentNumberOfZonesUtilized.ToString() }
        
        Write-Host ($headerFormat -f $displayName, $displayRg, $location, $sku, $displayCapacity, $displayMaxZones, $displayCurrentZones, $zoneStatus, $eligibleText) -ForegroundColor $color
        
    }
    catch {
        $displayName = $parsed.PlanName.Substring(0, [Math]::Min(29, $parsed.PlanName.Length))
        $displayRg = $parsed.ResourceGroup.Substring(0, [Math]::Min(19, $parsed.ResourceGroup.Length))
        Write-Host ($headerFormat -f $displayName, $displayRg, "Unknown", "Unknown", "-", "-", "-", "Error fetching details", "No") -ForegroundColor Red
    }
}

# Display summary
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Blue
Write-Host "Total App Service Plans: $totalPlans"
Write-Host "Zone Redundancy Enabled: $zoneRedundantPlans" -ForegroundColor Green
Write-Host "Zone Redundancy Disabled: $nonZoneRedundantPlans" -ForegroundColor Red
Write-Host "Requires New Plan: $requiresNewPlan" -ForegroundColor Magenta
Write-Host "ASE Not Zone Redundant: $aseNotZoneRedundant" -ForegroundColor DarkRed
Write-Host "Region Not Supported: $regionNotSupported" -ForegroundColor Yellow
Write-Host "SKU Not Supported: $skuNotSupported" -ForegroundColor Yellow

Write-Host ""
Write-Host "Status Explanations:" -ForegroundColor Blue
Write-Host "• Enabled: Zone redundancy is configured and active" -ForegroundColor Green
Write-Host "• Disabled: Zone redundancy is supported but not enabled" -ForegroundColor Red
Write-Host "• Requires New Plan: Plan supports only 1 zone - deploy new plan in new resource group" -ForegroundColor Magenta
Write-Host "• ASE Not Zone Redundant: Isolated v2 plan requires zone redundant App Service Environment" -ForegroundColor DarkRed
Write-Host "• Region Not Supported: The Azure region doesn't support zone redundancy" -ForegroundColor Yellow
Write-Host "• SKU Not Supported: The pricing tier doesn't support zone redundancy" -ForegroundColor Yellow
Write-Host ""
Write-Host "Note: Zone redundancy requires Premium v2, Premium v3, Premium v4, or Isolated v2 SKUs in supported regions." -ForegroundColor Blue

# Ask user if they want to proceed with conversion
Write-Host ""
Write-Host "=== Zone Redundancy Conversion ===" -ForegroundColor Blue
$eligibleForConversion = $nonZoneRedundantPlans
if ($eligibleForConversion -gt 0) {
    Write-Host "Found $eligibleForConversion plan(s) that can be converted to zone redundant." -ForegroundColor Yellow
    Write-Host "This will:"
    Write-Host "• Enable zone redundancy on eligible plans"
    Write-Host "• Set minimum instance count to 2 (if currently less than 2)"
    Write-Host "• Keep current instance count if already 2 or more"
    Write-Host ""
    $proceed = Read-Host "Do you want to proceed with the conversion? (y/N)"
    
    if ($proceed -eq 'y' -or $proceed -eq 'Y' -or $proceed -eq 'yes' -or $proceed -eq 'YES') {
        Write-Host ""
        Write-Host "=== Converting Plans to Zone Redundant ===" -ForegroundColor Blue
        
        # Re-process resource IDs for conversion
        foreach ($resourceId in $resourceIds) {
            $parsed = Parse-ResourceId -ResourceId $resourceId
            
            if (-not $parsed.IsValid -or $parsed.SubscriptionId -ne $currentAccount.subscriptionId) {
                continue
            }
            
            # Get plan details again
            try {
                $planDetailsJson = az appservice plan show --ids $resourceId --query "{location:location, sku:sku.name, skuCapacity:sku.capacity, zoneRedundant:properties.zoneRedundant, maximumNumberOfZones:properties.maximumNumberOfZones, hostingEnvironmentId:properties.hostingEnvironmentId}" -o json 2>$null
                $planDetails = $planDetailsJson | ConvertFrom-Json
                
                $location = $planDetails.location
                $sku = $planDetails.sku
                $skuCapacity = $planDetails.skuCapacity
                $zoneRedundant = $planDetails.zoneRedundant
                $maximumNumberOfZones = $planDetails.maximumNumberOfZones
                $hostingEnvironmentId = $planDetails.hostingEnvironmentId
                
                # Check if this plan is eligible for conversion
                $locationNormalized = $location.ToLower().Replace(' ', '')
                $regionSupportsZones = Test-RegionSupportsZones -Region $locationNormalized
                $skuSupportsZones = Test-SkuSupportsZones -Sku $sku
                $isIsolatedV2 = Test-IsIsolatedV2Sku -Sku $sku
                
                # For Isolated v2, check ASE zone redundancy
                $aseZoneRedundant = $null
                if ($isIsolatedV2 -and $hostingEnvironmentId) {
                    $aseDetails = Get-AppServiceEnvironmentDetails -HostingEnvironmentId $hostingEnvironmentId
                    if ($aseDetails) {
                        $aseZoneRedundant = $aseDetails.zoneRedundant
                    }
                }
                
                # Check if eligible for conversion
                if ($regionSupportsZones -and $skuSupportsZones -and $maximumNumberOfZones -gt 1 -and 
                    (-not $isIsolatedV2 -or $aseZoneRedundant -eq $true) -and $zoneRedundant -eq $false) {
                    
                    # Determine capacity to use
                    $targetCapacity = if ($skuCapacity -lt 2) { 2 } else { $skuCapacity }
                    
                    Write-Host "Converting: $($parsed.PlanName) (current capacity: $skuCapacity → target capacity: $targetCapacity)" -ForegroundColor Yellow
                    
                    try {
                        # Execute the conversion command
                        $result = az appservice plan update --name $parsed.PlanName --resource-group $parsed.ResourceGroup --set zoneRedundant=true sku.capacity=$targetCapacity 2>&1
                        
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "✓ Successfully converted $($parsed.PlanName) to zone redundant" -ForegroundColor Green
                        } else {
                            Write-Host "✗ Failed to convert $($parsed.PlanName): $result" -ForegroundColor Red
                        }
                    }
                    catch {
                        Write-Host "✗ Error converting $($parsed.PlanName): $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
            catch {
                Write-Host "✗ Error processing $($parsed.PlanName): Unable to retrieve plan details" -ForegroundColor Red
            }
        }
        
        Write-Host ""
        Write-Host "=== Conversion Complete ===" -ForegroundColor Blue
        Write-Host "Re-run the script to verify the updated zone redundancy status." -ForegroundColor Yellow
    }
    else {
        Write-Host "Conversion cancelled by user." -ForegroundColor Yellow
    }
} else {
    Write-Host "No plans are eligible for automatic conversion to zone redundant." -ForegroundColor Yellow
}
