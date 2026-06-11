# Vault User Workflow

This specification describes all user-facing scenarios for working with vaults in Noetec.

---

## Create New Vault

A user creates a vault by selecting a parent directory and providing a vault name. The application creates a new subdirectory with that name inside the parent.

### Successful Creation

**Scenario** User creates a vault with a name in a parent directory

| Step       | Detail                                                        |
|------------|---------------------------------------------------------------|
| **Given**  | the application is running with no vault open                 |
| **And**    | the directory `C:\projects` exists                            |
| **And**    | `C:\projects\my-vault` does NOT exist                         |
| **When**   | the user taps "Create Vault"                                  |
| **And**    | the user selects `C:\projects` as the parent directory        |
| **And**    | the user enters `my-vault` as the vault name                  |
| **Then**   | the directory `C:\projects\my-vault` is created               |
| **And**    | a new vault is created with a unique ID                       |
| **And**    | `.noetec\vault.json` is written with the name `my-vault`      |
| **And**    | the vault is added to the recent vaults list                  |
| **And**    | the application navigates to the Editor screen                |

### Creation Fails When Directory With That Name Already Exists

**Scenario** User creates a vault but the directory name is already taken

| Step       | Detail                                                        |
|------------|---------------------------------------------------------------|
| **Given**  | the directory `C:\projects` exists                            |
| **And**    | `C:\projects\work` already exists                             |
| **When**   | the user taps "Create Vault"                                  |
| **And**    | the user selects `C:\projects` as the parent directory        |
| **And**    | the user enters `work` as the vault name                      |
| **Then**   | an error is displayed to the user                             |
| **And**    | the error message indicates a directory with that name exists |
| **And**    | no new vault is created                                       |
| **And**    | the application remains on the Welcome screen                 |

### Creation Fails With Empty Vault Name

**Scenario** User creates a vault with an empty name

| Step       | Detail                                                        |
|------------|---------------------------------------------------------------|
| **Given**  | the application is running with no vault open                 |
| **When**   | the user taps "Create Vault"                                  |
| **And**    | the user selects `C:\projects` as the parent directory        |
| **And**    | the user submits an empty vault name                          |
| **Then**   | the dialog does not close                                     |
| **And**    | no new vault is created                                       |

---

## Open Existing Vault

A user can open an already-existing vault by pointing to its directory.

### Successful Open

**Scenario** User opens an existing vault

| Step       | Detail                                                          |
|------------|-----------------------------------------------------------------|
| **Given**  | the application is running with no vault open                   |
| **And**    | a vault exists at `C:\projects\my-vault`                        |
| **When**   | the user taps "Open Vault"                                      |
| **And**    | the user selects `C:\projects\my-vault`                         |
| **Then**   | the vault is loaded from `.noetec\vault.json`                   |
| **And**    | the vault name is displayed in the Editor header                |
| **And**    | the vault is moved to the top of the recent vaults list         |
| **And**    | the application navigates to the Editor screen                  |

### Open Fails on Invalid Path

**Scenario** User attempts to open a directory that is not a vault

| Step       | Detail                                                         |
|------------|----------------------------------------------------------------|
| **Given**  | the directory `C:\projects\not-a-vault` exists                 |
| **And**    | the directory does NOT contain `.noetec\vault.json`            |
| **When**   | the user taps "Open Vault"                                     |
| **And**    | the user selects `C:\projects\not-a-vault`                     |
| **Then**   | an error is displayed to the user                              |
| **And**    | the error message indicates the directory is not a valid vault |
| **And**    | no vault is opened                                             |
| **And**    | the application remains on the Welcome screen                  |

---

## Open Vault from Recent List

The Welcome screen shows a list of recently opened vaults for quick access.

### Successful Open from Recent

**Scenario** User opens a vault from the recent list

| Step       | Detail                                                         |
|------------|----------------------------------------------------------------|
| **Given**  | the application is running with no vault open                  |
| **And**    | the recent vaults list contains `Work` and `Personal`          |
| **When**   | the user taps on `Work` in the recent list                     |
| **Then**   | the `Work` vault is loaded                                     |
| **And**    | the vault is moved to the top of the recent list               |
| **And**    | the application navigates to the Editor screen                 |

### Open from Recent Fails If Vault Directory Is Missing

**Scenario** User opens a recent vault whose directory no longer exists

| Step       | Detail                                                         |
|------------|----------------------------------------------------------------|
| **Given**  | the recent vaults list contains `Deleted-Vault`                |
| **And**    | the directory for `Deleted-Vault` has been removed             |
| **When**   | the user taps `Deleted-Vault` in the recent list               |
| **Then**   | an error is displayed to the user                              |
| **And**    | the application remains on the Welcome screen                  |

---

## Close Vault

A user can close the currently open vault and return to the Welcome screen.

### Successful Close

**Scenario** User closes the current vault

| Step       | Detail                                                         |
|------------|----------------------------------------------------------------|
| **Given**  | the `My Vault` vault is open                                   |
| **And**    | the application is on the Editor screen                        |
| **When**   | the user taps the "Close Vault" button                         |
| **Then**   | the vault is no longer open                                    |
| **And**    | the application navigates to the Welcome screen                |
| **And**    | `My Vault` remains in the recent vaults list                   |

---

## Rename Vault

A user can rename an open vault to change its display name.

> **Status:** Not yet implemented.

### Successful Rename

**Scenario** User renames an open vault

| Step       | Detail                                                        |
|------------|---------------------------------------------------------------|
| **Given**  | the vault `Old Name` is open                                  |
| **When**   | the user initiates a rename operation                         |
| **And**    | the user enters `New Name`                                    |
| **Then**   | the vault display name is updated to `New Name`               |
| **And**    | `vault.json` is updated with the new name                     |
| **And**    | the recent vaults list reflects the new name                  |
| **And**    | the vault ID remains unchanged                                |

### Rename With Empty Name

**Scenario** User attempts to rename a vault to an empty name

| Step       | Detail                                                        |
|------------|---------------------------------------------------------------|
| **Given**  | the vault `Current` is open                                   |
| **When**   | the user initiates a rename operation                         |
| **And**    | the user submits an empty name                                |
| **Then**   | an error is displayed to the user                             |
| **And**    | the vault name is NOT changed                                 |

---

## Delete Vault

A user can permanently delete a vault and all its data.

> **Status:** Not yet implemented.

### Successful Delete

**Scenario** User deletes a vault

| Step       | Detail                                                        |
|------------|---------------------------------------------------------------|
| **Given**  | the vault `Old Vault` is open                                 |
| **When**   | the user initiates a delete operation                         |
| **And**    | the user confirms the deletion                                |
| **Then**   | the vault directory and all contents are deleted              |
| **And**    | the vault is removed from the recent vaults list              |
| **And**    | the application navigates to the Welcome screen               |

### Delete Requires Confirmation

**Scenario** User attempts to delete a vault without confirming

| Step       | Detail                                                        |
|------------|---------------------------------------------------------------|
| **Given**  | the vault `Important` is open                                 |
| **When**   | the user initiates a delete operation                         |
| **And**    | the user cancels the confirmation dialog                      |
| **Then**   | the vault is NOT deleted                                      |
| **And**    | the vault remains open                                        |

### Remove from Recent List Without Deleting Data

**Scenario** User removes a vault from the recent list without deleting data

| Step       | Detail                                                        |
|------------|---------------------------------------------------------------|
| **Given**  | the recent vaults list contains `Stale Vault`                 |
| **And**    | no vault is currently open                                    |
| **When**   | the user initiates a remove action on `Stale Vault`           |
| **Then**   | `Stale Vault` is removed from the recent list                 |
| **And**    | the vault data on disk is NOT deleted                         |

---

## Vault Metadata Display

The application shows vault information in the UI.

### Vault Name in Editor

**Scenario** Editor displays the current vault name

| Step       | Detail                                                        |
|------------|---------------------------------------------------------------|
| **Given**  | the vault `My Project` is open                                |
| **And**    | the application is on the Editor screen                       |
| **Then**   | the header displays `My Project`                              |

### Recent Vault Information

**Scenario** Recent vaults show their name and path

| Step       | Detail                                                        |
|------------|---------------------------------------------------------------|
| **Given**  | the recent vaults list contains vaults                        |
| **When**   | the user views the Welcome screen                             |
| **Then**   | each entry displays the vault name                            |
| **And**    | each entry displays the vault path or last-accessed info      |

---

## Multiple Vault Sessions

The application supports only one open vault at a time.

### Opening a Second Vault Closes the First

**Scenario** User opens a second vault while one is already open

| Step       | Detail                                                        |
|------------|---------------------------------------------------------------|
| **Given**  | the vault `Vault A` is open                                   |
| **When**   | the user navigates to Welcome and opens `Vault B`             |
| **Then**   | `Vault B` is now the active vault                             |
| **And**    | `Vault A` is no longer open                                   |
| **And**    | both vaults appear in the recent vaults list                  |
| **And**    | `Vault B` is at the top of the recent list                    |

---

## Vault Persistence

The vault state survives application restart.

### Recent Vault Survives Restart

**Scenario** Recent vaults are restored after application restart

| Step       | Detail                                                        |
|------------|---------------------------------------------------------------|
| **Given**  | `Vault A` and `Vault B` are in the recent vaults list         |
| **When**   | the application is closed and reopened                        |
| **Then**   | the recent vaults list contains `Vault A` and `Vault B`       |
| **And**    | the order is preserved                                        |

### Auto-Open Last Vault on Restart

**Scenario** The last open vault is restored on restart

| Step       | Detail                                                        |
|------------|---------------------------------------------------------------|
| **Given**  | the vault `My Vault` is open                                  |
| **When**   | the application is closed and reopened                        |
| **Then**   | `My Vault` is automatically opened                            |
| **And**    | the application navigates to the Editor screen                |

> **Status:** Not yet implemented.
