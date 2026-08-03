.PHONY: help check preflight apply-config native-windowing native-taskbar rollback-native-taskbar apps browser repair-nvidia barebones barebones-machine rollback-barebones rollback-barebones-machine atlas rollback-atlas rollback-config low-memory audit guard remove-guard export baseline verify

PWSH_RUNNER = powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-Pwsh.ps1 -ScriptPath

help:
	@echo "make check                       Validate public repository files and release hygiene"
	@echo "make preflight                   Check required software without changing Windows"
	@echo "make apply-config                Apply tracked shell, native Snap, and native taskbar configuration"
	@echo "make native-windowing            Reapply native Windows Snap and layout settings"
	@echo "make native-taskbar              Retire custom bars and configure the native Windows taskbar"
	@echo "make rollback-native-taskbar     Restore the original pre-managed taskbar state"
	@echo "make app-control                 Install and open ongoing app, startup, and process control"
	@echo "make remove-app-control          Remove App Control launchers while retaining saved state"
	@echo "make browser                     Reapply the Brave and Firefox low-memory browser profiles"
	@echo "make repair-nvidia               Repair Windows notification dependencies used by NVIDIA App"
	@echo "make apps                        Audit optional apps, startup entries, processes, and services"
	@echo "make barebones                   Apply aggressive current-user cleanup with rollback capture"
	@echo "make barebones-machine           Apply machine cleanup from an elevated shell"
	@echo "make rollback-barebones          Roll back the latest current-user barebones batch"
	@echo "make rollback-barebones-machine  Roll back the latest machine-wide barebones batch"
	@echo "make atlas                       Apply the AtlasOS-derived performance policy (elevated shell applies the machine section)"
	@echo "make rollback-atlas              Roll back the latest AtlasOS-derived performance batch"
	@echo "make rollback-config             Restore the previous tracked configuration from its backup"
	@echo "make low-memory                  Apply the explicit low-memory policy once"
	@echo "make audit                       Audit the startup/app policy without changing anything"
	@echo "make guard                       Install the startup guard scheduled task"
	@echo "make remove-guard                Remove the startup guard scheduled task"
	@echo "make export                      Export private machine snapshots under manifests/local/"
	@echo "make baseline                    Capture a performance and state snapshot under baseline/"
	@echo "make verify                      Run the read-only workstation verification suite"

check:
	$(PWSH_RUNNER) scripts/Test-Repository.ps1

preflight:
	$(PWSH_RUNNER) scripts/Test-Prerequisites.ps1

apply-config:
	$(PWSH_RUNNER) scripts/Apply-Config.ps1

native-windowing:
	$(PWSH_RUNNER) scripts/Configure-NativeWindowing.ps1

native-taskbar:
	$(PWSH_RUNNER) scripts/Remove-ZebarDockService.ps1
	$(PWSH_RUNNER) scripts/Configure-NativeTaskbar.ps1

rollback-native-taskbar:
	$(PWSH_RUNNER) scripts/Rollback-NativeTaskbar.ps1

apps:
	$(PWSH_RUNNER) scripts/Manage-OptionalApps.ps1 -Action Audit

app-control:
	$(PWSH_RUNNER) scripts/Install-AppControl.ps1 -Launch

remove-app-control:
	$(PWSH_RUNNER) scripts/Remove-AppControl.ps1

browser:
	$(PWSH_RUNNER) scripts/Configure-Brave.ps1

repair-nvidia:
	$(PWSH_RUNNER) scripts/Repair-NvidiaApp.ps1

barebones:
	$(PWSH_RUNNER) scripts/Apply-Barebones.ps1

barebones-machine:
	powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/Apply-Barebones-Machine.ps1

rollback-barebones:
	$(PWSH_RUNNER) scripts/Rollback-Barebones.ps1

rollback-barebones-machine:
	powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/Rollback-Barebones-Machine.ps1

atlas:
	$(PWSH_RUNNER) scripts/Apply-AtlasPerformance.ps1

rollback-atlas:
	$(PWSH_RUNNER) scripts/Rollback-AtlasPerformance.ps1

rollback-config:
	$(PWSH_RUNNER) scripts/Rollback-Config.ps1

low-memory:
	$(PWSH_RUNNER) scripts/Enforce-StartupPolicy.ps1

audit:
	$(PWSH_RUNNER) scripts/Enforce-StartupPolicy.ps1 -AuditOnly

guard:
	$(PWSH_RUNNER) scripts/Install-StartupGuard.ps1

remove-guard:
	$(PWSH_RUNNER) scripts/Remove-StartupGuard.ps1

export:
	$(PWSH_RUNNER) scripts/Export-Manifests.ps1

baseline:
	$(PWSH_RUNNER) scripts/Capture-Baseline.ps1

verify:
	$(PWSH_RUNNER) scripts/Verify-Workstation.ps1
