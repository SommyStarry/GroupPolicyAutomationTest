# GroupPolicyAutomation

PowerShell toolkit that automates Windows 10/11 security hardening through local Group Policy (`LGPO.exe`), service start types, registry tweaks, event-log sizing and AppLocker rules. It ships a console menu for applying a profile and a WinForms dashboard for inspecting a machine before and after.

> **Status: demo / portfolio project.** The apply flow changes system settings, so run it in a VM or on a test machine first. The dashboard is read-only.

## Profiles

Each profile exists in a Windows 10 and a Windows 11 variant (GPO backups in `Configs\`).

| Profile | Intended machine | Notes |
|---|---|---|
| **A** | Isolated workstation (no network or closed segment) | Nearly all network-related services disabled |
| **B** | Internet-connected, screen always on | No screensaver / sleep / display-off, Copilot and news widgets disabled |
| **C** | Internet-connected, regular user | Camera and consumer Microsoft accounts left available (needed for collaboration tools) |

`Configs\LGPO-Default` holds the stock Security Settings used by the rollback option.

## What the apply flow does

1. Enables System Protection on `C:`, reserves 10 GB and creates a restore point.
2. Sets event-log maximum sizes (Application, System, PowerShell, Task Scheduler: 1 GB / 150 MB; Security: 2 GB).
3. Applies registry hardening (source routing, ICMP redirects, autorun, 8.3 names, auto-admin-logon, `CrashOnAuditFail`).
4. Applies service start types for the chosen profile (70 services; audio and Bluetooth are asked interactively for profiles B/C).
5. Moves the default user-profile directory to `D:\Користувачі` (skipped when `D:` does not exist).
6. Optionally imports `AppLocker_Policy.xml` (replace / merge / skip).
7. Applies the profile GPO with `lgpo.exe /g`.
8. Offers a reboot.

A separate menu entry rolls policies and services back to defaults, creates local users, and (Windows 11) removes Windows Terminal / PowerShell from the Win+X menu.

## Requirements

- Windows 10 (build 10240+) or Windows 11, Windows PowerShell 5.1
- Administrator rights to apply settings (the dashboard also runs without them)
- `LGPO.exe` placed next to `Config.ps1` — **not included in this repository.** It is part of the Microsoft Security Compliance Toolkit; download it from Microsoft and copy `LGPO.exe` into the project folder.
- A `D:` volume if you want user profiles relocated

## Usage

```text
Run script.bat     console menu (applies a profile, rolls back, creates users)
Run GUI.bat        read-only dashboard
```

### Dashboard

Tabs: **Overview** (readiness checklist: admin rights, OS support, domain membership, required files, free space, pending reboot, restore point), **Disks**, **Configurations** (all profiles and whether they fit this PC), **Services** (current vs. target for each profile), **Registry & logs**, **About** (file hashes). Reports can be exported to a text file; `Config.ps1` can be launched from the window.

The UI language is Ukrainian.

## Repository layout

```text
Config.ps1                 menu, apply and rollback logic
GUI.ps1                    read-only WinForms dashboard
Run script.bat / Run GUI.bat
AppLocker_Policy.xml
Configs\                   GPO backups per profile and OS, plus stock defaults
Get Windows KEY\           prints the OEM / registry Windows key of the local machine
PC info\                   hardware inventory report for the local machine
```




