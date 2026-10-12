# Required permissions

The script requests delegated, **read-only** Microsoft Graph scopes. Nothing in this repo writes to your tenant.

| Scope | Used for | Graph endpoint |
|---|---|---|
| `User.Read.All` | User list, account status, creation date | `GET /users` |
| `AuditLog.Read.All` | `signInActivity` (last sign-in) | `GET /users?$select=signInActivity` |
| `DeviceManagementManagedDevices.Read.All` | Intune managed devices and compliance state | `GET /deviceManagement/managedDevices` |
| `RoleManagement.Read.Directory` | Directory role definitions and assignments | `GET /roleManagement/directory/roleDefinitions`, `GET /roleManagement/directory/roleAssignments` |

## Licensing

- `signInActivity` needs Microsoft Entra ID P1 or P2.
- Intune data needs an Intune license for the tenant.

## Admin consent

These scopes normally require admin consent the first time. Use a test tenant or a dedicated account with the right directory roles, for example Reports Reader or Global Reader.

## What the script does not do

- It does not store tokens or credentials.
- It does not write to Entra ID, Intune or any other service.
- It does not send data anywhere except the local `reports/` folder (which is git-ignored).
