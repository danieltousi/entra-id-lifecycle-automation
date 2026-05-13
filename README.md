# Entra ID Lifecycle Automation

A PowerShell framework using Microsoft Graph API to automate the full identity lifecycle across Microsoft Entra ID. Covers **Joiner** (new user provisioning), **Mover** (role and department changes), and **Leaver** (secure offboarding), aligned to Zero Trust principles and Essential Eight identity controls.

---

## Overview

Manual identity lifecycle processes are slow, inconsistent, and a significant security risk. This framework replaces manual HR-driven provisioning and offboarding with a repeatable, auditable automation pipeline that ensures accounts are created correctly, access changes are applied immediately, and departed users are fully offboarded within minutes rather than days.

---

## Architecture

```
entra-id-lifecycle-automation/
├── src/
│   └── Invoke-LifecycleAutomation.ps1   # Core lifecycle automation module
├── docs/
│   └── csv-templates.md                 # Input CSV format reference
├── logs/                                # Execution logs (auto-generated)
└── README.md
```

---

## Lifecycle Actions

### Joiner - New User Provisioning
- Creates Entra ID user account with secure temporary password
- Assigns to department security group
- Applies Microsoft 365 licence
- Forces password change on first login
- Logs all actions with timestamps

### Mover - Role and Department Changes
- Updates job title and department attributes
- Removes user from previous department group
- Adds user to new department group
- Updates reporting manager
- Full audit trail of all changes

### Leaver - Secure Offboarding
Follows a strict 6-step offboarding sequence:
1. Disable account immediately
2. Revoke all active sessions and refresh tokens
3. Remove from all security and Microsoft 365 groups
4. Remove all assigned licences
5. Flag mailbox for shared mailbox conversion
6. Reset password to random value

---

## Requirements

### PowerShell Module

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

### Required Graph API Permissions (Delegated)

- `User.ReadWrite.All`
- `Group.ReadWrite.All`
- `Directory.ReadWrite.All`
- `UserAuthenticationMethod.ReadWrite.All`
- `AuditLog.Read.All`

---

## Usage

### Single Joiner

```powershell
.\src\Invoke-LifecycleAutomation.ps1 -LifecycleAction Joiner -CsvPath ".\joiner-input.csv" -TenantId "your-tenant-id"
```

### Bulk Mover

```powershell
.\src\Invoke-LifecycleAutomation.ps1 -LifecycleAction Mover -CsvPath ".\mover-input.csv" -TenantId "your-tenant-id"
```

### Leaver Offboarding (WhatIf first)

```powershell
# Preview actions first
.\src\Invoke-LifecycleAutomation.ps1 -LifecycleAction Leaver -CsvPath ".\leaver-input.csv" -WhatIf

# Apply offboarding
.\src\Invoke-LifecycleAutomation.ps1 -LifecycleAction Leaver -CsvPath ".\leaver-input.csv" -TenantId "your-tenant-id"
```

---

## Security Design Decisions

- **WhatIf support throughout.** Every destructive action supports `-WhatIf` for safe pre-flight validation before execution.
- **Session revocation on leaver.** Disabling an account alone is not enough. All active tokens are explicitly revoked to prevent continued access using cached credentials.
- **Password randomisation on leaver.** Even disabled accounts get a randomised password, preventing re-enablement without IT intervention.
- **Least privilege Graph scopes.** Only the minimum required Graph API permissions are requested, following Zero Trust principles.
- **Full audit logging.** Every action is timestamped and written to a structured log file for compliance and incident investigation.

---

## Roadmap

- Azure DevOps pipeline integration for HR system triggered automation
- Microsoft Teams notification on leaver completion
- Entra ID Access Review integration for periodic access certification
- Automated manager notification on joiner completion with onboarding checklist

---

## Author

**Daniel Tousi**
Senior Systems Engineer | Azure | Microsoft 365 | Hybrid Infrastructure
[LinkedIn](https://linkedin.com/in/danieltousi) | [GitHub](https://github.com/danieltousi)

---

## References

- [Microsoft Graph User API](https://learn.microsoft.com/en-us/graph/api/resources/user)
- [Australian Essential Eight - Restrict Administrative Privileges](https://www.cyber.gov.au/resources-business-and-government/essential-cyber-security/essential-eight)
- [Entra ID Lifecycle Workflows](https://learn.microsoft.com/en-us/entra/id-governance/lifecycle-workflow-extensibility)
