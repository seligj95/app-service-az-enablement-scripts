# Azure App Service Zone Redundancy Scripts

PowerShell scripts to check and enable zone redundancy for Azure App Service Plans and App Service Environments.

## Scripts

### Check-AppServicePlanZoneRedundancy.ps1
Analyzes App Service Plans for zone redundancy eligibility and can automatically convert eligible plans.

**Features:**
- Checks zone redundancy status for multiple App Service Plans
- Validates region and SKU support
- Shows eligibility for zone redundancy conversion
- Can automatically enable zone redundancy on eligible plans
- Special handling for Isolated v2 plans (checks underlying ASE)

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
- ASE zone redundancy conversion takes 12-24 hours to complete
- No downtime occurs during conversion
