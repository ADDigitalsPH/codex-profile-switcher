Codex Profile Switcher for Windows
==================================

Branded for Agentic Revenue Vision with a blue-accented native Windows light interface, visible profile account metadata, a compact usage strip, and Windows 11-style rounded action buttons.

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
- Does not show, export, upload, or inspect raw credentials/tokens
- Decodes only the local ID token payload to show non-secret account metadata such as the email claim; raw tokens are never displayed
- Usage refresh reads saved profile auth locally, sends tokens only as HTTPS authorization headers to ChatGPT's usage and OAuth refresh endpoints, and never displays or logs raw tokens
- Shows a first-time authorized-use agreement stating that users must use only accounts they own, purchased, or are otherwise authorized to use

How to run
----------
1. Extract the release package anywhere, for example Desktop.
2. Recommended: double-click CodexProfileSwitcherSetup.exe to install it for the current Windows user.
3. Portable option: double-click CodexProfileSwitcher.exe.
4. If you are using the script version instead of the packaged exe, double-click: Run-CodexProfileSwitcher.bat
5. Optional: right-click Install-AgenticRevenueVisionCertificate.ps1, run it with PowerShell, and install the included public certificate for the current Windows user. This lets Windows trust the self-signed CodexProfileSwitcher.exe signature.
6. On first-time setup, save your current Codex login as the first profile. You can name this first profile yourself. "Default" is only a suggested name; it is not required.
7. If Codex is open during onboarding, you do not need to close it manually. The switcher asks for confirmation, then closes Codex automatically if closing is needed before it changes active auth files.
8. If no Codex login is available yet, open Codex, log in normally, return to the switcher, and click "Refresh". Then save the logged-in auth as a named profile.
9. After the first real auth profile is saved, the switcher asks whether to open Codex now.
10. Onboarding is complete only after either a real Codex auth profile has been saved or you intentionally skip setup.
11. To add another account later, click "Add account". The switcher asks for the new profile name in a pop-up window, saves the current active auth, closes Codex if needed, clears only the active auth files in %USERPROFILE%\.codex, and marks the new empty profile active.
12. Open Codex and log into the other account manually. Do not log out of the previous account first.
13. After login completes, return to the switcher and click "Save active login" to save the new account auth into its active profile.
14. Select a profile, then click "Switch profile". The app will close Codex.exe first if it is open, restore the selected auth, then try to re-open Codex automatically.
15. To rename a saved profile, select an inactive profile and click "Rename". The switcher asks for the new name in a pop-up window. The active profile cannot be renamed.
16. To delete a saved profile, select an inactive profile and click "Delete". The switcher requires you to type the profile name before deletion.

Installer
---------
- CodexProfileSwitcherSetup.exe installs the app for the current Windows user under %LOCALAPPDATA%\Programs\Codex Profile Switcher.
- The installer creates Start Menu shortcuts and can create a desktop shortcut.
- The installer can optionally trust the included Agentic Revenue Vision public signing certificate for the current Windows user.
- The installer registers an uninstall entry under the current user's Windows Apps & features list.
- To rebuild the installer from source, run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File Build-Installer.ps1

Important notes
---------------
- Switching profiles, starting a new login profile, and onboarding steps that change active auth files automatically close Codex.exe when needed to avoid replacing auth files while Codex is running.
- During onboarding, force-closing Codex requires a separate confirmation if the normal close request does not work.
- The app is intended only for lawful personal account switching. Users agree not to use it to share accounts, bypass account restrictions, or violate OpenAI's or any other service provider's terms, policies, or applicable law.
- Users are responsible for how they use the app. Agentic Revenue Vision provides the utility for lawful use and is not responsible for user misuse.
- Do not use Codex logout to create another profile. Logout may revoke the token in the current profile. Use "Add account" instead.
- Long profile operations run in the background so the switcher window can keep updating instead of freezing.
- Delete only works on inactive profiles. Switch to another profile before deleting the currently active one.
- Rename only works on inactive profiles. Switch to another profile before renaming the currently active one.
- The main action buttons follow the approved light UI design: Switch profile, Add account, Save active login, Rename/Delete, Refresh.
- Use the Light/Dark segmented control to switch the whole interface theme.
- Use "Hide emails" to mask the local part of every visible profile email address while keeping the domain visible.
- Usage rows show the selected profile's live usage when the saved profile auth can be refreshed successfully. If live refresh is unavailable, the app falls back to the profile's saved local usage snapshot.
- The main window includes a "Watch tutorial" link that opens the app tutorial video: https://youtu.be/JA8C-SHFS50
- The app only targets the Codex.exe process name. It does not close unrelated Git, terminal, VS Code, or browser processes.
- The internal/reserved folder name "_backups" is not shown as a selectable profile.
- The first profile does not have to be named "Default". Use a name that identifies the account clearly.
- Existing profile folders created by older versions may contain full .codex backups, but this version only reads and writes auth.json and cap_sid from those folders.
- CodexProfileSwitcher.exe is signed with the included self-signed Agentic Revenue Vision code-signing certificate. Windows will only show it as trusted after AgenticRevenueVision-CodeSigning.cer is installed for the current user.
- Keep your Windows account protected. These profile folders may contain active auth state.
- Do not share the .codex or .codex-profiles folders with anyone.

Troubleshooting
---------------
If PowerShell blocks the script, run the BAT file, not the PS1 directly. The BAT uses:

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File CodexProfileSwitcher.ps1

If switching does not work, Codex may have changed its storage format or may keep additional session state somewhere else. Check the official Codex app docs for the latest Windows storage path. Also check whether Codex is still running in Task Manager after the switcher tries to close it.
