#Requires -Modules Microsoft.Graph

<#
.SYNOPSIS
    Entra ID Lifecycle Automation - Joiner, Mover, Leaver Framework

.DESCRIPTION
    Automates the full identity lifecycle across Microsoft Entra ID using
    Microsoft Graph API. Handles user provisioning (Joiner), role and group
    changes (Mover), and secure offboarding (Leaver) aligned to Zero Trust
    and Essential Eight identity controls.

.AUTHOR
    Daniel Tousi
    Senior Systems Engineer | Azure | Microsoft 365 | Hybrid Infrastructure

.NOTES
    Required Modules: Microsoft.Graph
    Required Permissions:
    - User.ReadWrite.All
    - Group.ReadWrite.All
    - Directory.ReadWrite.All
    - UserAuthenticationMethod.ReadWrite.All
    - AuditLog.Read.All
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("Joiner", "Mover", "Leaver")]
    [string]$LifecycleAction,

    [Parameter(Mandatory = $false)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\logs\lifecycle-$(Get-Date -Format 'yyyyMMdd-HHmm').log"
)

#region --- Initialisation ---

$ErrorActionPreference = "Continue"

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )
    $colours = @{ Info = "Cyan"; Success = "Green"; Warning = "Yellow"; Error = "Red" }
    $prefix = @{ Info = "[INFO]"; Success = "[OK]"; Warning = "[WARN]"; Error = "[ERROR]" }
    $logLine = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $($prefix[$Level]) $Message"
    Write-Host $logLine -ForegroundColor $colours[$Level]

    $logDir = Split-Path $LogPath -Parent
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
    $logLine | Out-File -FilePath $LogPath -Append -Encoding UTF8
}

function Connect-GraphService {
    Write-Log "Connecting to Microsoft Graph..." -Level Info
    $scopes = @(
        "User.ReadWrite.All",
        "Group.ReadWrite.All",
        "Directory.ReadWrite.All",
        "UserAuthenticationMethod.ReadWrite.All",
        "AuditLog.Read.All"
    )
    try {
        Connect-MgGraph -Scopes $scopes -TenantId $TenantId -NoWelcome
        Write-Log "Microsoft Graph connected successfully" -Level Success
    }
    catch {
        Write-Log "Connection failed: $_" -Level Error
        throw
    }
}

#endregion

#region --- Joiner: New User Provisioning ---

function Invoke-Joiner {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$UserData
    )

    Write-Log "Processing Joiner: $($UserData.DisplayName)" -Level Info

    try {
        # Generate UPN
        $upn = "$($UserData.FirstName.ToLower()).$($UserData.LastName.ToLower())@$($UserData.Domain)"

        # Check if user already exists
        $existingUser = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
        if ($existingUser) {
            Write-Log "User $upn already exists. Skipping creation." -Level Warning
            return
        }

        # Generate secure temporary password
        $tempPassword = "Temp@$(Get-Random -Minimum 10000 -Maximum 99999)!"

        # Build user properties
        $userParams = @{
            DisplayName         = $UserData.DisplayName
            GivenName           = $UserData.FirstName
            Surname             = $UserData.LastName
            UserPrincipalName   = $upn
            MailNickname        = "$($UserData.FirstName.ToLower()).$($UserData.LastName.ToLower())"
            JobTitle            = $UserData.JobTitle
            Department          = $UserData.Department
            UsageLocation       = $UserData.UsageLocation ?? "AU"
            AccountEnabled      = $true
            PasswordProfile     = @{
                ForceChangePasswordNextSignIn = $true
                Password                      = $tempPassword
            }
        }

        if ($PSCmdlet.ShouldProcess($upn, "Create new user")) {
            $newUser = New-MgUser @userParams
            Write-Log "User created: $upn (ID: $($newUser.Id))" -Level Success

            # Assign to department group if specified
            if ($UserData.GroupId) {
                $groupMemberParams = @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($newUser.Id)"
                }
                New-MgGroupMember -GroupId $UserData.GroupId -BodyParameter $groupMemberParams
                Write-Log "Added $upn to group $($UserData.GroupId)" -Level Success
            }

            # Assign licence if specified
            if ($UserData.LicenceSku) {
                $licenceParams = @{
                    AddLicenses    = @(@{ SkuId = $UserData.LicenceSku })
                    RemoveLicenses = @()
                }
                Set-MgUserLicense -UserId $newUser.Id -BodyParameter $licenceParams
                Write-Log "Licence assigned to $upn" -Level Success
            }

            # Output credentials securely to log
            Write-Log "Temporary credentials for $upn - Password: $tempPassword (must change on first login)" -Level Info
        }
    }
    catch {
        Write-Log "Joiner failed for $($UserData.DisplayName): $_" -Level Error
    }
}

#endregion

#region --- Mover: Role and Group Changes ---

function Invoke-Mover {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$UserData
    )

    Write-Log "Processing Mover: $($UserData.UserPrincipalName)" -Level Info

    try {
        $user = Get-MgUser -Filter "userPrincipalName eq '$($UserData.UserPrincipalName)'" -ErrorAction Stop

        # Update job title and department
        if ($UserData.NewJobTitle -or $UserData.NewDepartment) {
            $updateParams = @{}
            if ($UserData.NewJobTitle) { $updateParams.JobTitle = $UserData.NewJobTitle }
            if ($UserData.NewDepartment) { $updateParams.Department = $UserData.NewDepartment }

            if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, "Update profile")) {
                Update-MgUser -UserId $user.Id @updateParams
                Write-Log "Profile updated for $($user.UserPrincipalName)" -Level Success
            }
        }

        # Remove from old group
        if ($UserData.RemoveGroupId) {
            if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, "Remove from group $($UserData.RemoveGroupId)")) {
                Remove-MgGroupMemberByRef -GroupId $UserData.RemoveGroupId -DirectoryObjectId $user.Id
                Write-Log "Removed $($user.UserPrincipalName) from group $($UserData.RemoveGroupId)" -Level Success
            }
        }

        # Add to new group
        if ($UserData.AddGroupId) {
            $groupMemberParams = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
            }
            if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, "Add to group $($UserData.AddGroupId)")) {
                New-MgGroupMember -GroupId $UserData.AddGroupId -BodyParameter $groupMemberParams
                Write-Log "Added $($user.UserPrincipalName) to group $($UserData.AddGroupId)" -Level Success
            }
        }

        # Update manager if specified
        if ($UserData.NewManagerId) {
            $managerParams = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($UserData.NewManagerId)"
            }
            if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, "Update manager")) {
                Set-MgUserManagerByRef -UserId $user.Id -BodyParameter $managerParams
                Write-Log "Manager updated for $($user.UserPrincipalName)" -Level Success
            }
        }
    }
    catch {
        Write-Log "Mover failed for $($UserData.UserPrincipalName): $_" -Level Error
    }
}

#endregion

#region --- Leaver: Secure Offboarding ---

function Invoke-Leaver {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$UserData
    )

    Write-Log "Processing Leaver: $($UserData.UserPrincipalName)" -Level Info

    try {
        $user = Get-MgUser -Filter "userPrincipalName eq '$($UserData.UserPrincipalName)'" `
            -Property "Id,DisplayName,UserPrincipalName,AccountEnabled" -ErrorAction Stop

        if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, "Offboard user")) {

            # Step 1: Disable the account immediately
            Update-MgUser -UserId $user.Id -AccountEnabled $false
            Write-Log "Account disabled: $($user.UserPrincipalName)" -Level Success

            # Step 2: Revoke all active sessions and refresh tokens
            Revoke-MgUserSignInSession -UserId $user.Id
            Write-Log "All sessions revoked: $($user.UserPrincipalName)" -Level Success

            # Step 3: Remove from all groups
            $memberOf = Get-MgUserMemberOf -UserId $user.Id -All
            foreach ($group in $memberOf | Where-Object { $_.AdditionalProperties["@odata.type"] -eq "#microsoft.graph.group" }) {
                try {
                    Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $user.Id
                    Write-Log "Removed from group: $($group.Id)" -Level Success
                }
                catch {
                    Write-Log "Could not remove from group $($group.Id): $_" -Level Warning
                }
            }

            # Step 4: Remove all assigned licences
            $licences = Get-MgUserLicenseDetail -UserId $user.Id
            if ($licences) {
                $removeLicenceParams = @{
                    AddLicenses    = @()
                    RemoveLicenses = $licences.SkuId
                }
                Set-MgUserLicense -UserId $user.Id -BodyParameter $removeLicenceParams
                Write-Log "Licences removed: $($user.UserPrincipalName)" -Level Success
            }

            # Step 5: Convert mailbox to shared (if required, done via Exchange Online)
            Write-Log "ACTION REQUIRED: Convert mailbox to shared for $($user.UserPrincipalName) via Exchange Online if needed" -Level Warning

            # Step 6: Reset password to random value to prevent any access
            $randomPassword = [System.Web.Security.Membership]::GeneratePassword(20, 5)
            $passwordParams = @{
                PasswordProfile = @{
                    ForceChangePasswordNextSignIn = $true
                    Password                      = $randomPassword
                }
            }
            Update-MgUser -UserId $user.Id @passwordParams
            Write-Log "Password reset to random value: $($user.UserPrincipalName)" -Level Success

            Write-Log "Offboarding complete for $($user.UserPrincipalName)" -Level Success
        }
    }
    catch {
        Write-Log "Leaver failed for $($UserData.UserPrincipalName): $_" -Level Error
    }
}

#endregion

#region --- CSV Processing ---

function Invoke-BulkLifecycle {
    if (-not (Test-Path $CsvPath)) {
        Write-Log "CSV file not found: $CsvPath" -Level Error
        return
    }

    $users = Import-Csv -Path $CsvPath
    Write-Log "Loaded $($users.Count) records from $CsvPath" -Level Info

    foreach ($user in $users) {
        switch ($LifecycleAction) {
            "Joiner" { Invoke-Joiner -UserData $user }
            "Mover"  { Invoke-Mover -UserData $user }
            "Leaver" { Invoke-Leaver -UserData $user }
        }
    }
}

#endregion

#region --- Main ---

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Entra ID Lifecycle Automation v1.0" -ForegroundColor Cyan
Write-Host "  Action: $LifecycleAction" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

Connect-GraphService

if ($CsvPath) {
    Invoke-BulkLifecycle
}
else {
    Write-Log "No CSV provided. Use -CsvPath to specify a bulk input file." -Level Warning
    Write-Log "See docs/csv-templates/ for input format examples." -Level Info
}

Write-Log "Lifecycle automation run complete. Log saved to $LogPath" -Level Info

#endregion
