# Changelog

## Unreleased — review, refactor, dashboard

### Fixed
- `CrashOnAuditFail` was never written: `Set-ItemProperty` has no `-PropertyType`; now `New-ItemProperty -Force`.
- Main-menu entry 3 called non-existent functions; it now calls `Remove-Win11TerminalAndPowerShell` (Windows 11 only).
- Service existence was detected by an English error message; now the `sc.exe` exit code 1060 is used.
- Rollback: renaming Guest to "Guest" failed when it already had that name and aborted the rollback; the rollback also re-enabled Guest (disabled by default). Both fixed.
- User-profile relocation is skipped when `D:` does not exist, instead of pointing new profiles at a missing drive.
- Console-font registry write no longer errors when the key is absent.
- The "skip" choice for audio/Bluetooth services used `continue` inside `switch` and did not skip; fixed by the refactor below.

### Changed
- Four duplicated service loops merged into `Set-ServicesStartType` (the interactive prompts for `Audiosrv`, `AudioEndpointBuilder`, `bthserv` are data-driven).
- Profiles renamed to A / B / C; GPO folders, function names and menu texts updated accordingly.

### Added
- `GUI.ps1` / `Run GUI.bat`: read-only dashboard (readiness checks, disks, profiles, service comparison, registry and log comparison, file hashes, text report export).
- README and this changelog.
