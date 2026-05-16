Codex Profile Switcher for Windows
==================================

Branded for Agentic Revenue Vision with a native Windows light interface and Windows 11-style rounded action buttons.

Purpose
-------
This is a local-only utility for switching Codex app authentication on Windows by rotating auth files inside:

  %USERPROFILE%\.codex

OpenAI's Windows Codex app documentation says the Windows app uses the same Codex home directory as native Codex on Windows: %USERPROFILE%\.codex. This switcher stores only the auth-related files in named profiles and leaves projects, chats, logs, sessions, cache, config, and history shared in the live %USERPROFILE%\.codex folder.

What it does
------------
- Creates named local auth profiles under: %USERPROFILE%\.codex-profiles
- Saves/restores only auth-related files: auth.json and cap_sid
- Marks the saved or prepared profile as active because it matches the current auth state
- Prepares a new account login without logging out of the currently saved profile
- Automatically closes Codex.exe before switching profiles or starting a new login profile
- First requests a normal/graceful close, then force-closes Codex.exe if it stays open during switch/new-login operations
- Saves current auth files into the active profile
- Restores the selected profile's auth files back into %USERPROFILE%\.codex
- Renames inactive saved profiles
- Keeps projects, chats, sessions, logs, cache, config, and history shared across profiles
- Deletes inactive saved profiles from %USERPROFILE%\.codex-profiles after typed confirmation
- Does not show, decode, export, upload, or inspect credentials/tokens
- Does not use the internet

How to run
----------
1. Extract this ZIP anywhere, for example Desktop.
2. Double-click: CodexProfileSwitcher.exe
3. If you are using the script version instead of the packaged exe, double-click: Run-CodexProfileSwitcher.bat
4. On first-time setup, save your current Codex login as the first profile. You can name this first profile yourself. "Default" is only a suggested name; it is not required.
5. If Codex is open during onboarding, you do not need to close it manually. The switcher asks for confirmation, then closes Codex automatically if closing is needed before it changes active auth files.
6. If no Codex login is available yet, open Codex, log in normally, return to the switcher, and click "Refresh". Then save the logged-in auth as a named profile.
7. After the first real auth profile is saved, the switcher asks whether to open Codex now.
8. Onboarding is complete only after either a real Codex auth profile has been saved or you intentionally skip setup.
9. To add another account later, click "Add account". The switcher asks for the new profile name in a pop-up window, saves the current active auth, closes Codex if needed, clears only the active auth files in %USERPROFILE%\.codex, and marks the new empty profile active.
10. Open Codex and log into the other account manually. Do not log out of the previous account first.
11. After login completes, return to the switcher and click "Save active login" to save the new account auth into its active profile.
12. Select a profile, then click "Switch profile". The app will close Codex.exe first if it is open, restore the selected auth, then try to re-open Codex automatically.
13. To rename a saved profile, select an inactive profile and click "Rename". The switcher asks for the new name in a pop-up window. The active profile cannot be renamed.
14. To delete a saved profile, select an inactive profile and click "Delete". The switcher requires you to type the profile name before deletion.

Important notes
---------------
- Switching profiles, starting a new login profile, and onboarding steps that change active auth files automatically close Codex.exe when needed to avoid replacing auth files while Codex is running.
- During onboarding, force-closing Codex requires a separate confirmation if the normal close request does not work.
- Do not use Codex logout to create another profile. Logout may revoke the token in the current profile. Use "Add account" instead.
- Long profile operations run in the background so the switcher window can keep updating instead of freezing.
- Delete only works on inactive profiles. Switch to another profile before deleting the currently active one.
- Rename only works on inactive profiles. Switch to another profile before renaming the currently active one.
- The main action buttons are ordered as: Add account, Save active login, Switch profile, Rename, Delete.
- The app only targets the Codex.exe process name. It does not close unrelated Git, terminal, VS Code, or browser processes.
- The internal/reserved folder name "_backups" is not shown as a selectable profile.
- The first profile does not have to be named "Default". Use a name that identifies the account clearly.
- Existing profile folders created by older versions may contain full .codex backups, but this version only reads and writes auth.json and cap_sid from those folders.
- Keep your Windows account protected. These profile folders may contain active auth state.
- Do not share the .codex or .codex-profiles folders with anyone.

Troubleshooting
---------------
If PowerShell blocks the script, run the BAT file, not the PS1 directly. The BAT uses:

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File CodexProfileSwitcher.ps1

If switching does not work, Codex may have changed its storage format or may keep additional session state somewhere else. Check the official Codex app docs for the latest Windows storage path. Also check whether Codex is still running in Task Manager after the switcher tries to close it.
