# Azure App Service Zone Redundancy Scripts

PowerShell scripts to check and enable zone redundancy for Azure App Service Plans and App Service Environments.

## Scripts

### Check-AppServicePlanZoneRedundancy.ps1
Analyzes App Service Plans for zone redundancy eligibility and can automatically convert eligible plans, including SKU upgrades when needed.

**Features:**
- Checks zone redundancy status for multiple App Service Plans
- Validates region and SKU support
- Shows eligibility for zone redundancy conversion
- **Automatic SKU upgrade support** for plans with unsupported SKUs
- Can automatically enable zone redundancy on eligible plans
- Interactive planning phase for SKU upgrades with batch execution
- Special handling for Isolated v2 plans (checks underlying ASE)

**SKU Upgrade Logic:**
For plans with unsupported SKUs in supported regions, the script can upgrade them automatically:
- **F1/B1/S1/D1** → **P0v3** (lowest tier plans)
- **B2/S2** → **P1v3** (second tier plans)
- **B3/S3** → **P2v3** (third tier plans)
- **All other plans** → **P1v3** (default)

Users can customize the target SKU during the upgrade process.

### Check-AppServiceEnvironmentZoneRedundancy.ps1
Analyzes App Service Environments for zone redundancy eligibility and can initiate conversions.

**Features:**
- Checks zone redundancy status for multiple ASEs
- Validates region and zone support
- Shows eligibility for zone redundancy conversion
- Can initiate zone redundancy conversion (12-24 hour process)
- Provides guidance for monitoring conversion status

## Prerequisites

- Azure CLI installed and authenticated
- PowerShell (Windows PowerShell or PowerShell Core)
- Resource IDs must be from the currently authenticated subscription

## Usage

1. Create a text file with resource IDs (one per line)
2. Run the appropriate script:

```powershell
# For App Service Plans
.\Check-AppServicePlanZoneRedundancy.ps1 -FilePath "resource_ids.txt"

# For App Service Environments
.\Check-AppServiceEnvironmentZoneRedundancy.ps1 -FilePath "ase_resource_ids.txt"
```

### App Service Plan Conversion Workflow

The script follows a two-phase approach:

**Phase 1: Analysis & Planning**
1. Analyzes all plans and displays their current status
2. Shows eligibility: `Already ZR`, `Yes`, `Requires SKU Upgrade`, `Region Not Supported`, etc.
3. For plans requiring SKU upgrades, prompts user for each plan:
   - Shows current SKU and recommended upgrade
   - Allows custom SKU input
   - Requires individual confirmation

**Phase 2: Batch Execution**
1. Displays summary of all planned conversions
2. Executes all conversions without further interruption
3. Shows progress and results for each plan

This workflow ensures all decisions are made upfront, then execution runs uninterrupted.

## Eligibility Status Explanations

### App Service Plans
- **Already ZR**: Zone redundancy is already enabled
- **Yes**: Ready for direct zone redundancy conversion (supported SKU + region)
- **Requires SKU Upgrade**: Plan can be converted after upgrading to a supported SKU
- **Region Not Supported**: The Azure region doesn't support zone redundancy
- **Requires New Plan**: Plan only supports 1 zone - deploy new plan in new resource group
- **ASE Not ZR**: Isolated v2 plan requires zone redundant App Service Environment

### Supported SKUs for Zone Redundancy
- **Premium v2**: P1v2, P2v2, P3v2
- **Premium v3**: P0v3, P1v3, P2v3, P3v3, P1mv3, P2mv3, P3mv3, P4mv3, P5mv3
- **Premium v4**: P0v4, P1v4, P2v4, P3v4, P1mv4, P2mv4, P3mv4, P4mv4, P5mv4
- **Isolated v2**: I1v2, I2v2, I3v2, I4v2, I5v2, I6v2, I1mv2, I2mv2, I3mv2, I4mv2, I5mv2

## Sample Resource ID Files

### resource_ids.txt (App Service Plans)
```
/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/resource-group-1/providers/Microsoft.Web/serverFarms/app-service-plan-1
/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/resource-group-2/providers/Microsoft.Web/serverFarms/app-service-plan-2
```

### ase_resource_ids.txt (App Service Environments)
```
/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/ase-resource-group-1/providers/Microsoft.Web/hostingEnvironments/app-service-environment-1
/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/ase-resource-group-2/providers/Microsoft.Web/hostingEnvironments/app-service-environment-2
```

## Documentation

### App Service Plans
- [App Service Reliability Guide](https://learn.microsoft.com/en-us/azure/reliability/reliability-app-service)
- [Configure Zone Redundancy](https://learn.microsoft.com/en-us/azure/app-service/configure-zone-redundancy?tabs=portal)

### App Service Environments
- [ASE Reliability Guide](https://learn.microsoft.com/en-us/azure/reliability/reliability-app-service-environment)
- [Configure ASE Zone Redundancy](https://learn.microsoft.com/en-us/azure/app-service/environment/configure-zone-redundancy-environment?tabs=portal)

## Notes

- Zone redundancy conversion is typically immediate for App Service Plans
- SKU upgrades may incur additional costs - review pricing before confirming
- Plans requiring SKU upgrades will prompt for individual confirmation
- ASE zone redundancy conversion takes 12-24 hours to complete
- No downtime occurs during conversion
- Minimum instance count of 2 is automatically applied for zone redundant plans
