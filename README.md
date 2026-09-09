# Multi VS Code Codex

A Windows PowerShell installer for two VS Code environments that can run side by side with separate VS Code data, extensions, and Codex authentication storage.

Built to max out the vibe-coding flow. Alice and Bob code side by side like two lovers at neighboring keyboards, sharing the desk but never the session.

- **Alice** uses a dark cobalt-blue appearance.
- **Bob** uses a dark red appearance.
- Each environment gets its own `--user-data-dir`, `--extensions-dir`, and process-local `CODEX_HOME`.
- The official `openai.chatgpt` extension is installed independently in both environments.
- Existing VS Code settings, projects, Git configuration, and the default `%USERPROFILE%\.codex` directory are not modified.

## Install

Run from Windows PowerShell 5.1 or later:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-VSCode-Codex.ps1
```

The installer creates `%LOCALAPPDATA%\VSCode-Codex` and two desktop shortcuts. Sign in to the two ChatGPT accounts manually and one at a time.

Use `-SkipExtensionInstall` to skip the extension installation step, or `-SkipLaunchTest` to skip launcher probes.

## Notes

The installer never copies authentication files or enables Settings Sync. The two environments are isolated at the application-data level, but they are not a security boundary: both still run as the same Windows user.

Before removing `%LOCALAPPDATA%\VSCode-Codex`, back up anything you want to keep. Deleting either environment's `codex` directory also deletes its local Codex authentication and history.
