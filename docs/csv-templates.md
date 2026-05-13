## Joiner CSV Template
## Save as: joiner-input.csv

FirstName,LastName,DisplayName,Domain,JobTitle,Department,UsageLocation,GroupId,LicenceSku
John,Smith,John Smith,contoso.com,Systems Engineer,IT,AU,xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx,xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Jane,Doe,Jane Doe,contoso.com,Project Manager,PMO,AU,xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx,xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

## Mover CSV Template
## Save as: mover-input.csv

UserPrincipalName,NewJobTitle,NewDepartment,RemoveGroupId,AddGroupId,NewManagerId
john.smith@contoso.com,Senior Systems Engineer,Infrastructure,xxxxxxxx-old-group-id,xxxxxxxx-new-group-id,xxxxxxxx-manager-id

## Leaver CSV Template
## Save as: leaver-input.csv

UserPrincipalName
john.smith@contoso.com
jane.doe@contoso.com
