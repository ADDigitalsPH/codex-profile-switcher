<#
Codex Profile Switcher for Windows
Local-only utility. It switches the active Codex authentication by backing up/restoring auth files in %USERPROFILE%\.codex.
No credential/token display. No network calls. No external dependencies.
Automatically closes Codex before replacing or clearing active auth files.
#>

param(
    [ValidateSet("", "GetState", "SaveFirstProfile", "StartEmptyProfile", "SwitchProfile", "SaveActive", "RenameProfile", "DeleteProfile")]
    [string]$Operation = "",
    [string]$ProfileName = "",
    [string]$TargetProfile = "",
    [string]$ResultFile = "",
    [string]$ErrorFile = ""
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class ArvGlassButton : Button
{
    public int Radius { get; set; }
    public Color NormalBack { get; set; }
    public Color HoverBack { get; set; }
    public Color DownBack { get; set; }
    public Color DisabledBack { get; set; }
    public Color Border { get; set; }
    public Color DisabledBorder { get; set; }
    public Color TextNormal { get; set; }
    public Color TextDisabled { get; set; }

    private bool hovered;
    private bool pressed;

    public ArvGlassButton()
    {
        Radius = 16;
        NormalBack = Color.FromArgb(12, 27, 56);
        HoverBack = Color.FromArgb(15, 43, 86);
        DownBack = Color.FromArgb(5, 46, 96);
        DisabledBack = Color.FromArgb(8, 18, 38);
        Border = Color.FromArgb(20, 48, 91);
        DisabledBorder = Color.FromArgb(13, 31, 59);
        TextNormal = Color.FromArgb(238, 247, 255);
        TextDisabled = Color.FromArgb(82, 111, 146);
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        FlatStyle = FlatStyle.Flat;
        UseVisualStyleBackColor = false;
        FlatAppearance.BorderSize = 0;
        Cursor = Cursors.Hand;
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        using (GraphicsPath path = RoundedPath(new Rectangle(0, 0, Width, Height), Radius))
        {
            Region old = Region;
            Region = new Region(path);
            if (old != null) old.Dispose();
        }
    }

    protected override void OnMouseEnter(EventArgs e) { hovered = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hovered = false; pressed = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { pressed = true; Invalidate(); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { pressed = false; Invalidate(); base.OnMouseUp(e); }
    protected override void OnEnabledChanged(EventArgs e)
    {
        Cursor = Enabled ? Cursors.Hand : Cursors.Default;
        Invalidate();
        base.OnEnabledChanged(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle rect = new Rectangle(0, 0, Width - 1, Height - 1);
        Color fill = !Enabled ? DisabledBack : pressed ? DownBack : hovered ? HoverBack : NormalBack;
        Color border = Enabled ? Border : DisabledBorder;
        Color text = Enabled ? TextNormal : TextDisabled;

        using (GraphicsPath path = RoundedPath(rect, Radius))
        using (LinearGradientBrush brush = new LinearGradientBrush(rect, ControlPaint.Light(fill, 0.08f), fill, 90f))
        using (Pen pen = new Pen(border))
        {
            e.Graphics.FillPath(brush, path);
            e.Graphics.DrawPath(pen, path);
        }

        TextRenderer.DrawText(e.Graphics, Text, Font, rect, text, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
    }

    private GraphicsPath RoundedPath(Rectangle rect, int radius)
    {
        int d = Math.Max(1, Math.Min(radius * 2, Math.Min(rect.Width, rect.Height)));
        GraphicsPath path = new GraphicsPath();
        path.AddArc(rect.Left, rect.Top, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Top, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.Left, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}

public class ArvChip : Label
{
    public int Radius { get; set; }
    public Color Fill { get; set; }
    public Color Border { get; set; }
    public Color TextColor { get; set; }

    public ArvChip()
    {
        Radius = 12;
        Fill = Color.FromArgb(12, 27, 56);
        Border = Color.FromArgb(20, 48, 91);
        TextColor = Color.FromArgb(139, 166, 196);
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        TextAlign = ContentAlignment.MiddleCenter;
        AutoSize = false;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle rect = new Rectangle(0, 0, Width - 1, Height - 1);
        using (GraphicsPath path = RoundedPath(rect, Radius))
        using (SolidBrush brush = new SolidBrush(Fill))
        using (Pen pen = new Pen(Border))
        {
            e.Graphics.FillPath(brush, path);
            e.Graphics.DrawPath(pen, path);
        }
        TextRenderer.DrawText(e.Graphics, Text, Font, rect, TextColor, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
    }

    private GraphicsPath RoundedPath(Rectangle rect, int radius)
    {
        int d = Math.Max(1, Math.Min(radius * 2, Math.Min(rect.Width, rect.Height)));
        GraphicsPath path = new GraphicsPath();
        path.AddArc(rect.Left, rect.Top, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Top, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.Left, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
"@

$ErrorActionPreference = "Stop"

$CodexHome = Join-Path $env:USERPROFILE ".codex"
$ProfilesRoot = Join-Path $env:USERPROFILE ".codex-profiles"
$ActiveFile = Join-Path $ProfilesRoot ".active_profile.txt"
$OnboardingFile = Join-Path $ProfilesRoot ".onboarding_complete"
$LogFile = Join-Path $ProfilesRoot "switcher.log"
$ReservedProfileNames = @("_backups")
$AuthFileNames = @("auth.json", "cap_sid")
$AppName = "Codex Profile Switcher"
$HeaderText = "$AppName by A.R.V"
$CompanyName = "Agentic Revenue Vision"
$WindowTitle = "$AppName - $CompanyName"

$Ui = @{
    Base = [System.Drawing.Color]::FromArgb(4, 10, 24)
    BaseLift = [System.Drawing.Color]::FromArgb(6, 18, 40)
    Surface = [System.Drawing.Color]::FromArgb(8, 18, 38)
    SurfaceRaised = [System.Drawing.Color]::FromArgb(12, 27, 56)
    SurfaceSelected = [System.Drawing.Color]::FromArgb(15, 43, 86)
    Border = [System.Drawing.Color]::FromArgb(37, 92, 160)
    BorderSoft = [System.Drawing.Color]::FromArgb(20, 48, 91)
    Text = [System.Drawing.Color]::FromArgb(238, 247, 255)
    Muted = [System.Drawing.Color]::FromArgb(139, 166, 196)
    Subtle = [System.Drawing.Color]::FromArgb(82, 111, 146)
    Accent = [System.Drawing.Color]::FromArgb(0, 168, 255)
    AccentBright = [System.Drawing.Color]::FromArgb(40, 169, 255)
    AccentDark = [System.Drawing.Color]::FromArgb(0, 84, 181)
    AccentSoft = [System.Drawing.Color]::FromArgb(5, 46, 96)
    AccentWash = [System.Drawing.Color]::FromArgb(8, 31, 67)
    Danger = [System.Drawing.Color]::FromArgb(255, 83, 116)
    DangerSoft = [System.Drawing.Color]::FromArgb(82, 20, 39)
}

function New-UiFont($Size, $Style) {
    if ($null -eq $Style) { $Style = [System.Drawing.FontStyle]::Regular }

    $fontName = "Segoe UI"
    try {
        $familyNames = @([System.Drawing.FontFamily]::Families | ForEach-Object { $_.Name })
        if ($familyNames -contains "Segoe UI Variable Text") {
            $fontName = "Segoe UI Variable Text"
        }
    } catch {
        $fontName = "Segoe UI"
    }

    return New-Object System.Drawing.Font($fontName, $Size, $Style)
}

function Set-GlassForm($Form) {
    $Form.BackColor = $Ui.Base
    $Form.ForeColor = $Ui.Text
    $Form.Add_Paint({
        param($sender, $eventArgs)
        $graphics = $eventArgs.Graphics
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rect = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $Ui.BaseLift, $Ui.Base, 90)
        $graphics.FillRectangle($brush, $rect)
        $brush.Dispose()
    })
}

function Get-DisplayText($Text, $MaxLength) {
    $value = [string]$Text
    if ($value.Length -le $MaxLength) { return $value }
    if ($MaxLength -le 3) { return $value.Substring(0, $MaxLength) }
    return ($value.Substring(0, ($MaxLength - 3)) + "...")
}

function New-RoundedRectanglePath($Width, $Height, $Radius) {
    $safeWidth = [Math]::Max(1, [int]$Width)
    $safeHeight = [Math]::Max(1, [int]$Height)
    $safeRadius = [Math]::Min([int]$Radius, [Math]::Min([int]($safeWidth / 2), [int]($safeHeight / 2)))
    $diameter = $safeRadius * 2

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    if ($safeRadius -le 0) {
        $path.AddRectangle((New-Object System.Drawing.Rectangle(0, 0, $safeWidth, $safeHeight)))
        return $path
    }

    $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
    $path.AddArc(($safeWidth - $diameter - 1), 0, $diameter, $diameter, 270, 90)
    $path.AddArc(($safeWidth - $diameter - 1), ($safeHeight - $diameter - 1), $diameter, $diameter, 0, 90)
    $path.AddArc(0, ($safeHeight - $diameter - 1), $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function Set-RoundedRegion($Control, $Radius) {
    $regionPath = New-RoundedRectanglePath $Control.Width $Control.Height $Radius
    $newRegion = New-Object System.Drawing.Region($regionPath)
    $oldRegion = $Control.Region
    $Control.Region = $newRegion
    if ($oldRegion -ne $null) { $oldRegion.Dispose() }
    $regionPath.Dispose()
}

function Set-RoundedControlRegion($Control, $Radius) {
    Set-RoundedRegion $Control $Radius
}

function New-GlassPanel($Name, $Location, $Size) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Name = $Name
    $panel.Location = $Location
    $panel.Size = $Size
    $panel.BackColor = $Ui.Surface
    $panel.ForeColor = $Ui.Text
    $panel.Padding = New-Object System.Windows.Forms.Padding(16)
    $panel.Add_SizeChanged({
        param($sender, $eventArgs)
        Set-RoundedRegion $sender 22
    })
    $panel.Add_Paint({
        param($sender, $eventArgs)
        $eventArgs.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
        $path = New-RoundedRectanglePath $sender.Width $sender.Height 22
        $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $Ui.SurfaceRaised, $Ui.Surface, 90)
        $eventArgs.Graphics.FillPath($fill, $path)
        $fill.Dispose()

        $topLine = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(130, $Ui.AccentSoft))
        $eventArgs.Graphics.DrawLine($topLine, 22, 1, ($sender.Width - 23), 1)
        $topLine.Dispose()

        $borderPen = New-Object System.Drawing.Pen($Ui.Border)
        $eventArgs.Graphics.DrawPath($borderPen, $path)
        $borderPen.Dispose()
        $path.Dispose()
    })
    Set-RoundedRegion $panel 22
    return $panel
}

function New-UiLabel($Text, $Size, $Style, $Color) {
    if ($null -eq $Color) { $Color = $Ui.Text }
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Font = New-UiFont $Size $Style
    $label.ForeColor = $Color
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.AutoSize = $true
    return $label
}

function Set-TextControlStyle($Control) {
    $Control.Font = New-UiFont 10 $null
    $Control.BackColor = $Ui.SurfaceRaised
    $Control.ForeColor = $Ui.Text
    $Control.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
}

function Set-CheckControlStyle($Control) {
    $Control.Font = New-UiFont 9 $null
    $Control.BackColor = $Ui.Base
    $Control.ForeColor = $Ui.Text
    $Control.FlatStyle = "Flat"
}

function Set-ButtonStyle($Button, $Kind) {
    $Button.Font = New-UiFont 9 $null
    $Button.FlatStyle = "Flat"
    $Button.UseVisualStyleBackColor = $false
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.FlatAppearance.BorderSize = 1

    switch ($Kind) {
        "Primary" {
            $Button.BackColor = $Ui.AccentDark
            $Button.ForeColor = $Ui.Text
            $Button.FlatAppearance.BorderColor = $Ui.AccentBright
            $Button.FlatAppearance.MouseOverBackColor = $Ui.Accent
            $Button.FlatAppearance.MouseDownBackColor = $Ui.AccentSoft
            if ($Button -is [ArvGlassButton]) {
                $Button.NormalBack = $Ui.AccentDark
                $Button.HoverBack = $Ui.Accent
                $Button.DownBack = $Ui.AccentSoft
                $Button.DisabledBack = $Ui.AccentWash
                $Button.Border = $Ui.AccentBright
                $Button.DisabledBorder = $Ui.BorderSoft
                $Button.TextNormal = $Ui.Text
                $Button.TextDisabled = $Ui.Subtle
                $Button.Radius = 18
            }
        }
        "Danger" {
            $Button.BackColor = $Ui.DangerSoft
            $Button.ForeColor = $Ui.Text
            $Button.FlatAppearance.BorderColor = $Ui.Danger
            $Button.FlatAppearance.MouseOverBackColor = $Ui.Danger
            $Button.FlatAppearance.MouseDownBackColor = $Ui.DangerSoft
            if ($Button -is [ArvGlassButton]) {
                $Button.NormalBack = $Ui.DangerSoft
                $Button.HoverBack = $Ui.Danger
                $Button.DownBack = $Ui.DangerSoft
                $Button.DisabledBack = $Ui.Surface
                $Button.Border = $Ui.Danger
                $Button.DisabledBorder = $Ui.BorderSoft
                $Button.TextNormal = $Ui.Text
                $Button.TextDisabled = $Ui.Subtle
                $Button.Radius = 16
            }
        }
        default {
            $Button.BackColor = $Ui.SurfaceRaised
            $Button.ForeColor = $Ui.Text
            $Button.FlatAppearance.BorderColor = $Ui.BorderSoft
            $Button.FlatAppearance.MouseOverBackColor = $Ui.SurfaceSelected
            $Button.FlatAppearance.MouseDownBackColor = $Ui.AccentSoft
            if ($Button -is [ArvGlassButton]) {
                $Button.NormalBack = $Ui.SurfaceRaised
                $Button.HoverBack = $Ui.SurfaceSelected
                $Button.DownBack = $Ui.AccentSoft
                $Button.DisabledBack = $Ui.Surface
                $Button.Border = $Ui.BorderSoft
                $Button.DisabledBorder = $Ui.BorderSoft
                $Button.TextNormal = $Ui.Text
                $Button.TextDisabled = $Ui.Subtle
                $Button.Radius = 16
            }
        }
    }
    $buttonRadius = if ($Button -is [ArvGlassButton]) { $Button.Radius } else { 16 }
    Set-RoundedControlRegion $Button $buttonRadius
    $Button.Invalidate()
}

function Set-StatusChip($Label, $Kind) {
    $Label.Font = New-UiFont 8 $null
    $Label.AutoSize = $false
    $Label.TextAlign = "MiddleCenter"
    $Label.BackColor = $Ui.SurfaceRaised
    $Label.ForeColor = $Ui.Muted

    switch ($Kind) {
        "Accent" {
            $Label.BackColor = $Ui.AccentDark
            $Label.ForeColor = $Ui.Text
            if ($Label -is [ArvChip]) {
                $Label.Fill = $Ui.AccentDark
                $Label.Border = $Ui.AccentBright
                $Label.TextColor = $Ui.Text
            }
        }
        "Warning" {
            $Label.BackColor = $Ui.AccentWash
            $Label.ForeColor = $Ui.AccentBright
            if ($Label -is [ArvChip]) {
                $Label.Fill = $Ui.AccentWash
                $Label.Border = $Ui.Border
                $Label.TextColor = $Ui.AccentBright
            }
        }
        "Info" {
            $Label.BackColor = $Ui.AccentWash
            $Label.ForeColor = $Ui.AccentBright
            if ($Label -is [ArvChip]) {
                $Label.Fill = $Ui.AccentWash
                $Label.Border = $Ui.Border
                $Label.TextColor = $Ui.AccentBright
            }
        }
        default {
            if ($Label -is [ArvChip]) {
                $Label.Fill = $Ui.SurfaceRaised
                $Label.Border = $Ui.BorderSoft
                $Label.TextColor = $Ui.Muted
            }
        }
    }
    Set-RoundedControlRegion $Label 12
    $Label.Invalidate()
}

function Ensure-Dirs {
    if (!(Test-Path $ProfilesRoot)) { New-Item -ItemType Directory -Path $ProfilesRoot | Out-Null }
}

function Write-Log($Message) {
    try {
        Ensure-Dirs
        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogFile -Value "[$stamp] $Message"
    } catch {
        # Logging must never make a completed profile operation look failed.
    }
}

function Sanitize-ProfileName($Name) {
    $clean = ($Name -replace '[\\/:*?"<>|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { throw "Profile name cannot be empty." }
    if ($ReservedProfileNames -contains $clean) { throw "'$clean' is reserved and cannot be used as a profile name." }
    return $clean
}

function Get-AuthFileCount($Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path $Path)) { return 0 }

    $count = 0
    foreach ($fileName in $AuthFileNames) {
        if (Test-Path (Join-Path $Path $fileName)) { $count++ }
    }
    return $count
}

function HasAuthFiles($Path) {
    return (Get-AuthFileCount $Path) -gt 0
}

function Clear-AuthFilesInPath($Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path $Path)) { return }

    foreach ($fileName in $AuthFileNames) {
        $authPath = Join-Path $Path $fileName
        if (Test-Path $authPath) {
            Remove-Item -LiteralPath $authPath -Force
        }
    }
}

function Test-ProfileFolderExists($Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }

    try {
        $profilePath = Get-ProfilePath $Name
        return (Test-Path $profilePath)
    } catch {
        return $false
    }
}

function Get-ActiveProfile([switch]$ReadOnly) {
    if (Test-Path $ActiveFile) {
        $name = (Get-Content $ActiveFile -Raw).Trim()
        if ($name) {
            try {
                $safe = Sanitize-ProfileName $name
                if (Test-ProfileFolderExists $safe) { return $safe }
                if (!$ReadOnly) { Write-Log "Ignored missing active profile folder '$safe'." }
            } catch {
                if (!$ReadOnly) { Write-Log "Ignored invalid active profile '$name': $($_.Exception.Message)" }
            }
        }
    }
    if (Test-ProfileFolderExists "Default") { return "Default" }
    return ""
}

function Set-ActiveProfile($Name) {
    Ensure-Dirs
    $safe = Sanitize-ProfileName $Name
    Set-Content -Path $ActiveFile -Value $safe -Encoding UTF8
    Write-Log "Set active profile to '$safe'."
}

function Get-ProfilePath($Name) {
    $safe = Sanitize-ProfileName $Name
    return Join-Path $ProfilesRoot $safe
}

function Get-Profiles([switch]$ReadOnly) {
    if (!$ReadOnly) { Ensure-Dirs }
    if (!(Test-Path $ProfilesRoot)) { return @() }
    Get-ChildItem -Path $ProfilesRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike ".*" -and $ReservedProfileNames -notcontains $_.Name } |
        Select-Object -ExpandProperty Name |
        Sort-Object
}

function Get-ProfilesWithAuth {
    @(Get-Profiles) | Where-Object { HasAuthFiles (Get-ProfilePath $_) }
}

function Test-OnboardingComplete {
    return (Test-Path $OnboardingFile)
}

function Set-OnboardingComplete($Reason) {
    Ensure-Dirs
    Set-Content -Path $OnboardingFile -Value $Reason -Encoding UTF8
    Write-Log "Marked onboarding complete: $Reason"
}

function Copy-AuthFiles($Source, $Dest) {
    if (!(Test-Path $Dest)) { New-Item -ItemType Directory -Path $Dest | Out-Null }
    Clear-AuthFilesInPath $Dest

    $copied = 0
    foreach ($fileName in $AuthFileNames) {
        $sourcePath = Join-Path $Source $fileName
        $destPath = Join-Path $Dest $fileName
        if (Test-Path $sourcePath) {
            Copy-Item -LiteralPath $sourcePath -Destination $destPath -Force
            $copied++
        }
    }

    return $copied
}

function Clear-ActiveAuthFiles {
    if (!(Test-Path $CodexHome)) { New-Item -ItemType Directory -Path $CodexHome | Out-Null }
    Clear-AuthFilesInPath $CodexHome
}

function Save-CurrentToProfile($Name) {
    Ensure-Dirs
    $safe = Sanitize-ProfileName $Name

    if (!(HasAuthFiles $CodexHome)) {
        Write-Log "No active auth files found. Profile '$safe' was not changed."
        return 0
    }

    $profilePath = Get-ProfilePath $safe
    if (!(Test-Path $profilePath)) { New-Item -ItemType Directory -Path $profilePath | Out-Null }

    $copied = Copy-AuthFiles $CodexHome $profilePath
    Write-Log "Saved $copied auth file(s) from active .codex to profile '$safe'."
    return $copied
}

function Restore-ProfileToCurrent($Name) {
    $safe = Sanitize-ProfileName $Name
    $profilePath = Get-ProfilePath $safe
    if (!(Test-Path $profilePath)) { throw "Profile not found: $safe" }
    if (!(Test-Path $CodexHome)) { New-Item -ItemType Directory -Path $CodexHome | Out-Null }

    Clear-ActiveAuthFiles
    $copied = Copy-AuthFiles $profilePath $CodexHome
    if ($copied -eq 0) { Write-Log "Profile '$safe' has no saved auth files. Active auth files were cleared." }
    Set-ActiveProfile $safe
    Write-Log "Restored $copied auth file(s) from profile '$safe' to active .codex."
}

function Start-EmptyProfile($Name) {
    Ensure-Dirs
    $safe = Sanitize-ProfileName $Name
    $profilePath = Get-ProfilePath $safe
    if (Test-Path $profilePath) { throw "Profile already exists: $safe" }

    $active = Get-ActiveProfile
    if ($active -and (HasAuthFiles $CodexHome)) {
        [void](Save-CurrentToProfile $active)
    } elseif ($active) {
        Write-Log "Skipped saving active profile '$active' because active .codex has no auth files."
    }

    New-Item -ItemType Directory -Path $profilePath | Out-Null
    Clear-ActiveAuthFiles
    Set-ActiveProfile $safe
    Write-Log "Started empty profile '$safe' for a new login."
}

function Remove-Profile($Name) {
    $safe = Sanitize-ProfileName $Name
    $active = Get-ActiveProfile
    if ($safe -eq $active) { throw "Cannot delete the active profile '$safe'. Switch to another profile first." }

    $profilePath = Get-ProfilePath $safe
    if (!(Test-Path $profilePath)) { throw "Profile not found: $safe" }

    Remove-Item -LiteralPath $profilePath -Recurse -Force
    Write-Log "Deleted profile '$safe'."
}

function Rename-Profile($OldName, $NewName) {
    $oldSafe = Sanitize-ProfileName $OldName
    $newSafe = Sanitize-ProfileName $NewName
    $active = Get-ActiveProfile

    if ($oldSafe -eq $active) { throw "Cannot rename the active profile '$oldSafe'. Switch to another profile first." }
    if ($oldSafe -eq $newSafe) { throw "New profile name must be different from the current name." }

    $oldPath = Get-ProfilePath $oldSafe
    if (!(Test-Path $oldPath)) { throw "Profile not found: $oldSafe" }
    if (Test-ProfileFolderExists $newSafe) { throw "Profile already exists: $newSafe" }

    $newPath = Get-ProfilePath $newSafe
    Move-Item -LiteralPath $oldPath -Destination $newPath
    Write-Log "Renamed profile '$oldSafe' to '$newSafe'."
}

function Get-CodexProcesses {
    # Official Windows app process is Codex.exe in current public reports/docs ecosystem.
    # Use exact process-name matching only to avoid closing unrelated windows whose title contains "Codex".
    return @(Get-Process -Name "Codex" -ErrorAction SilentlyContinue)
}

function Test-CodexProcessRunning {
    return @((Get-CodexProcesses)).Count -gt 0
}

function Close-CodexGracefully {
    $matches = Get-CodexProcesses
    if (@($matches).Count -eq 0) { return $true }

    foreach ($p in $matches) {
        try {
            if ($p.MainWindowHandle -ne 0) {
                [void]$p.CloseMainWindow()
                Write-Log "Requested graceful close for Codex process $($p.ProcessName) ($($p.Id))."
            }
        } catch {}
    }

    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
        if (!(Test-CodexProcessRunning)) { return $true }
    }
    return $false
}

function Stop-CodexProcesses {
    $matches = Get-CodexProcesses
    foreach ($p in $matches) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            Write-Log "Force-stopped Codex process $($p.ProcessName) ($($p.Id))."
        } catch {
            Write-Log "Failed to force-stop Codex process $($p.ProcessName) ($($p.Id)): $($_.Exception.Message)"
        }
    }
}

function Close-CodexForOperation($OperationName) {
    if (!(Test-CodexProcessRunning)) { return }

    $ok = Close-CodexGracefully
    if ($ok) {
        Start-Sleep -Milliseconds 500
        return
    }

    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline) {
        Stop-CodexProcesses
        Start-Sleep -Milliseconds 750
        if (!(Test-CodexProcessRunning)) { return }
    }

    $remaining = Get-CodexProcesses |
        ForEach-Object { "$($_.ProcessName) ($($_.Id))" }

    throw "Could not close Codex automatically. Remaining process(es): $($remaining -join ', '). Close them from Task Manager, then try $OperationName again."
}

function Close-CodexForBackendFirstSave($ProfileName) {
    if (!(Test-CodexProcessRunning)) { return }

    $ok = Close-CodexGracefully
    if ($ok) {
        Start-Sleep -Milliseconds 500
        return
    }

    throw "Codex is still running. Close Codex manually, then try saving first profile '$ProfileName' again."
}

function Close-CodexForOnboardingSave($ProfileName) {
    if (!(Test-CodexProcessRunning)) { return }

    $ok = Close-CodexGracefully
    if ($ok) {
        Start-Sleep -Milliseconds 500
        return
    }

    $confirmed = Ask-YesNo "Codex did not close after a normal close request.`r`n`r`nForce-close Codex now and save profile '$ProfileName'?"
    if (!$confirmed) {
        throw "Codex is still running. The first profile was not saved."
    }

    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline) {
        Stop-CodexProcesses
        Start-Sleep -Milliseconds 750
        if (!(Test-CodexProcessRunning)) { return }
    }

    $remaining = Get-CodexProcesses |
        ForEach-Object { "$($_.ProcessName) ($($_.Id))" }

    throw "Could not close Codex automatically. Remaining process(es): $($remaining -join ', ')."
}

function Start-CodexApp {
    try {
        $app = Get-StartApps |
            Where-Object { $_.Name -eq "Codex" -or $_.AppID -like "*OpenAI.Codex*" } |
            Select-Object -First 1

        if ($app) {
            Start-Process ("shell:AppsFolder\" + $app.AppID)
            Write-Log "Re-opened Codex using Start menu app id '$($app.AppID)'."
            return $true
        }

        Start-Process "Codex.exe"
        Write-Log "Re-opened Codex using Codex.exe."
        return $true
    } catch {
        Write-Log "Could not re-open Codex automatically: $($_.Exception.Message)"
        return $false
    }
}

function Show-ThemedDialog($Text, $Title, $Buttons, $Kind) {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = $Title
    $dialog.Size = New-Object System.Drawing.Size(540, 320)
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    Set-GlassForm $dialog

    $headingText = if ($Kind -eq "Warning") { "Action needs attention" } elseif ($Kind -eq "Question") { "Confirm action" } else { "Operation complete" }
    $heading = New-UiLabel $headingText 13 ([System.Drawing.FontStyle]::Bold) $Ui.Text
    $heading.Location = New-Object System.Drawing.Point(24, 22)
    $dialog.Controls.Add($heading)

    $message = New-Object System.Windows.Forms.Label
    $message.Text = $Text
    $message.Font = New-UiFont 9 $null
    $message.ForeColor = $Ui.Muted
    $message.BackColor = [System.Drawing.Color]::Transparent
    $message.AutoSize = $false
    $message.Size = New-Object System.Drawing.Size(480, 160)
    $message.Location = New-Object System.Drawing.Point(26, 58)
    $dialog.Controls.Add($message)

    $script:ThemedDialogResult = "Cancel"

    if ($Buttons -eq "YesNo") {
        $btnYes = New-Object ArvGlassButton
        $btnYes.Text = "Yes"
        $btnYes.Location = New-Object System.Drawing.Point(322, 248)
        $btnYes.Size = New-Object System.Drawing.Size(88, 34)
        Set-ButtonStyle $btnYes "Primary"
        $btnYes.Add_Click({
            $script:ThemedDialogResult = "Yes"
            $dialog.Close()
        })
        $dialog.Controls.Add($btnYes)

        $btnNo = New-Object ArvGlassButton
        $btnNo.Text = "No"
        $btnNo.Location = New-Object System.Drawing.Point(422, 248)
        $btnNo.Size = New-Object System.Drawing.Size(88, 34)
        Set-ButtonStyle $btnNo "Secondary"
        $btnNo.Add_Click({
            $script:ThemedDialogResult = "No"
            $dialog.Close()
        })
        $dialog.Controls.Add($btnNo)
        $dialog.AcceptButton = $btnYes
        $dialog.CancelButton = $btnNo
    } else {
        $btnOk = New-Object ArvGlassButton
        $btnOk.Text = "OK"
        $btnOk.Location = New-Object System.Drawing.Point(422, 248)
        $btnOk.Size = New-Object System.Drawing.Size(88, 34)
        Set-ButtonStyle $btnOk "Primary"
        $btnOk.Add_Click({
            $script:ThemedDialogResult = "OK"
            $dialog.Close()
        })
        $dialog.Controls.Add($btnOk)
        $dialog.AcceptButton = $btnOk
    }

    if (Get-Variable -Name form -Scope Script -ErrorAction SilentlyContinue) {
        [void]$dialog.ShowDialog($script:form)
    } else {
        [void]$dialog.ShowDialog()
    }

    return $script:ThemedDialogResult
}

function Show-Info($Text) { [void](Show-ThemedDialog $Text $WindowTitle "OK" "Info") }
function Show-Warn($Text) { [void](Show-ThemedDialog $Text $WindowTitle "OK" "Warning") }
function Ask-YesNo($Text) { return ((Show-ThemedDialog $Text $WindowTitle "YesNo" "Question") -eq "Yes") }

function Confirm-DeleteProfile($Name) {
    $safe = Sanitize-ProfileName $Name

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "$WindowTitle - Confirm delete"
    $dialog.Size = New-Object System.Drawing.Size(470, 245)
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    Set-GlassForm $dialog

    $message = New-Object System.Windows.Forms.Label
    $message.Font = New-UiFont 9 $null
    $message.ForeColor = $Ui.Text
    $message.BackColor = [System.Drawing.Color]::Transparent
    $message.AutoSize = $false
    $message.Size = New-Object System.Drawing.Size(410, 72)
    $message.Location = New-Object System.Drawing.Point(24, 20)
    $message.Text = "Delete profile '$safe'?`r`n`r`nThis removes only its saved auth profile folder. Type the profile name to confirm deletion."
    $dialog.Controls.Add($message)

    $confirmBox = New-Object System.Windows.Forms.TextBox
    Set-TextControlStyle $confirmBox
    $confirmBox.Location = New-Object System.Drawing.Point(28, 106)
    $confirmBox.Size = New-Object System.Drawing.Size(250, 28)
    $dialog.Controls.Add($confirmBox)

    $btnDeleteConfirm = New-Object ArvGlassButton
    $btnDeleteConfirm.Text = "Delete"
    $btnDeleteConfirm.Location = New-Object System.Drawing.Point(255, 156)
    $btnDeleteConfirm.Size = New-Object System.Drawing.Size(85, 32)
    $btnDeleteConfirm.Enabled = $false
    Set-ButtonStyle $btnDeleteConfirm "Danger"
    $dialog.Controls.Add($btnDeleteConfirm)

    $btnCancelDelete = New-Object ArvGlassButton
    $btnCancelDelete.Text = "Cancel"
    $btnCancelDelete.Location = New-Object System.Drawing.Point(350, 156)
    $btnCancelDelete.Size = New-Object System.Drawing.Size(85, 32)
    Set-ButtonStyle $btnCancelDelete "Secondary"
    $dialog.Controls.Add($btnCancelDelete)

    $script:DeleteProfileConfirmed = $false
    $confirmBox.Add_TextChanged({ $btnDeleteConfirm.Enabled = (([string]$confirmBox.Text).Trim() -eq $safe) })
    $btnDeleteConfirm.Add_Click({
        $script:DeleteProfileConfirmed = $true
        $dialog.Close()
    })
    $btnCancelDelete.Add_Click({ $dialog.Close() })

    [void]$dialog.ShowDialog($form)
    return $script:DeleteProfileConfirmed
}

function Prompt-ForProfileName($Title, $Prompt, $InitialValue) {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "$WindowTitle - $Title"
    $dialog.Size = New-Object System.Drawing.Size(460, 230)
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    Set-GlassForm $dialog

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Prompt
    $label.Font = New-UiFont 9 $null
    $label.ForeColor = $Ui.Text
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.AutoSize = $false
    $label.Size = New-Object System.Drawing.Size(395, 48)
    $label.Location = New-Object System.Drawing.Point(24, 22)
    $dialog.Controls.Add($label)

    $nameBox = New-Object System.Windows.Forms.TextBox
    Set-TextControlStyle $nameBox
    $nameBox.Location = New-Object System.Drawing.Point(28, 82)
    $nameBox.Size = New-Object System.Drawing.Size(260, 28)
    $nameBox.Text = $InitialValue
    if ($InitialValue) { $nameBox.SelectAll() }
    $dialog.Controls.Add($nameBox)

    $btnOk = New-Object ArvGlassButton
    $btnOk.Text = "OK"
    $btnOk.Location = New-Object System.Drawing.Point(252, 140)
    $btnOk.Size = New-Object System.Drawing.Size(80, 32)
    $btnOk.Enabled = -not [string]::IsNullOrWhiteSpace($nameBox.Text)
    Set-ButtonStyle $btnOk "Primary"
    $dialog.Controls.Add($btnOk)

    $btnCancel = New-Object ArvGlassButton
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(342, 140)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 32)
    Set-ButtonStyle $btnCancel "Secondary"
    $dialog.Controls.Add($btnCancel)

    $script:PromptedProfileName = ""
    $nameBox.Add_TextChanged({ $btnOk.Enabled = -not [string]::IsNullOrWhiteSpace($nameBox.Text) })
    $btnOk.Add_Click({
        try {
            $script:PromptedProfileName = Sanitize-ProfileName $nameBox.Text
            $dialog.Close()
        } catch {
            Show-Warn $_.Exception.Message
        }
    })
    $btnCancel.Add_Click({ $dialog.Close() })

    $dialog.AcceptButton = $btnOk
    $dialog.CancelButton = $btnCancel
    [void]$dialog.ShowDialog($form)
    return $script:PromptedProfileName
}

function Should-ShowOnboarding {
    if (Test-OnboardingComplete) { return $false }
    return @((Get-ProfilesWithAuth)).Count -eq 0
}

function Show-OnboardingConsent {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "$WindowTitle - Setup consent"
    $dialog.Size = New-Object System.Drawing.Size(500, 285)
    $dialog.StartPosition = "CenterScreen"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    Set-GlassForm $dialog

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = "Before first-time setup"
    $heading.Font = New-UiFont 15 ([System.Drawing.FontStyle]::Bold)
    $heading.ForeColor = $Ui.Text
    $heading.BackColor = [System.Drawing.Color]::Transparent
    $heading.AutoSize = $true
    $heading.Location = New-Object System.Drawing.Point(22, 20)
    $dialog.Controls.Add($heading)

    $message = New-Object System.Windows.Forms.Label
    $message.Font = New-UiFont 9 $null
    $message.ForeColor = $Ui.Muted
    $message.BackColor = [System.Drawing.Color]::Transparent
    $message.AutoSize = $false
    $message.Size = New-Object System.Drawing.Size(440, 95)
    $message.Location = New-Object System.Drawing.Point(24, 62)
    $message.Text = "Codex Profile Switcher changes accounts by saving and restoring local Codex auth files in your user folders.`r`n`r`nDuring setup, Codex may need to close automatically so auth files can be saved safely. You will be asked before Codex is closed."
    $dialog.Controls.Add($message)

    $consentBox = New-Object System.Windows.Forms.CheckBox
    $consentBox.Text = "I understand Codex may close during setup."
    Set-CheckControlStyle $consentBox
    $consentBox.AutoSize = $true
    $consentBox.Location = New-Object System.Drawing.Point(28, 168)
    $dialog.Controls.Add($consentBox)

    $btnContinue = New-Object ArvGlassButton
    $btnContinue.Text = "Continue"
    $btnContinue.Location = New-Object System.Drawing.Point(265, 212)
    $btnContinue.Size = New-Object System.Drawing.Size(90, 32)
    $btnContinue.Enabled = $false
    Set-ButtonStyle $btnContinue "Primary"
    $dialog.Controls.Add($btnContinue)

    $btnCancel = New-Object ArvGlassButton
    $btnCancel.Text = "Exit"
    $btnCancel.Location = New-Object System.Drawing.Point(368, 212)
    $btnCancel.Size = New-Object System.Drawing.Size(85, 32)
    Set-ButtonStyle $btnCancel "Secondary"
    $dialog.Controls.Add($btnCancel)

    $script:OnboardingConsentAccepted = $false
    $consentBox.Add_CheckedChanged({ $btnContinue.Enabled = $consentBox.Checked })
    $btnContinue.Add_Click({
        $script:OnboardingConsentAccepted = $true
        $dialog.Close()
    })
    $btnCancel.Add_Click({ $dialog.Close() })

    [void]$dialog.ShowDialog()
    return $script:OnboardingConsentAccepted
}

function Show-OnboardingWizard {
    if (!(Show-OnboardingConsent)) { return $false }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "$WindowTitle - First setup"
    $dialog.Size = New-Object System.Drawing.Size(500, 345)
    $dialog.StartPosition = "CenterScreen"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    Set-GlassForm $dialog

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = "First-time setup"
    $heading.Font = New-UiFont 15 ([System.Drawing.FontStyle]::Bold)
    $heading.ForeColor = $Ui.Text
    $heading.BackColor = [System.Drawing.Color]::Transparent
    $heading.AutoSize = $true
    $heading.Location = New-Object System.Drawing.Point(22, 20)
    $dialog.Controls.Add($heading)

    $message = New-Object System.Windows.Forms.Label
    $message.Font = New-UiFont 9 $null
    $message.ForeColor = $Ui.Muted
    $message.BackColor = [System.Drawing.Color]::Transparent
    $message.AutoSize = $false
    $message.Size = New-Object System.Drawing.Size(440, 85)
    $message.Location = New-Object System.Drawing.Point(24, 62)
    $dialog.Controls.Add($message)

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = "First profile name"
    $profileLabel.Font = New-UiFont 9 $null
    $profileLabel.ForeColor = $Ui.Text
    $profileLabel.BackColor = [System.Drawing.Color]::Transparent
    $profileLabel.AutoSize = $true
    $profileLabel.Location = New-Object System.Drawing.Point(25, 154)
    $dialog.Controls.Add($profileLabel)

    $profileNameBox = New-Object System.Windows.Forms.TextBox
    Set-TextControlStyle $profileNameBox
    $profileNameBox.Text = "Default"
    $profileNameBox.Location = New-Object System.Drawing.Point(28, 178)
    $profileNameBox.Size = New-Object System.Drawing.Size(250, 28)
    $profileNameBox.SelectAll()
    $dialog.Controls.Add($profileNameBox)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = "Default is only a suggestion; rename it if helpful."
    $hint.Font = New-UiFont 8 $null
    $hint.ForeColor = $Ui.Subtle
    $hint.BackColor = [System.Drawing.Color]::Transparent
    $hint.AutoSize = $true
    $hint.Location = New-Object System.Drawing.Point(28, 211)
    $dialog.Controls.Add($hint)

    $btnSave = New-Object ArvGlassButton
    $btnSave.Text = "Save first profile"
    $btnSave.Location = New-Object System.Drawing.Point(28, 252)
    $btnSave.Size = New-Object System.Drawing.Size(135, 32)
    Set-ButtonStyle $btnSave "Primary"
    $dialog.Controls.Add($btnSave)

    $btnOpenCodex = New-Object ArvGlassButton
    $btnOpenCodex.Text = "Open Codex"
    $btnOpenCodex.Location = New-Object System.Drawing.Point(28, 252)
    $btnOpenCodex.Size = New-Object System.Drawing.Size(105, 32)
    Set-ButtonStyle $btnOpenCodex "Primary"
    $dialog.Controls.Add($btnOpenCodex)

    $btnRefresh = New-Object ArvGlassButton
    $btnRefresh.Text = "Refresh"
    $btnRefresh.Location = New-Object System.Drawing.Point(145, 252)
    $btnRefresh.Size = New-Object System.Drawing.Size(95, 32)
    Set-ButtonStyle $btnRefresh "Secondary"
    $dialog.Controls.Add($btnRefresh)

    $btnSkip = New-Object ArvGlassButton
    $btnSkip.Text = "Skip setup"
    $btnSkip.Location = New-Object System.Drawing.Point(252, 252)
    $btnSkip.Size = New-Object System.Drawing.Size(105, 32)
    Set-ButtonStyle $btnSkip "Secondary"
    $dialog.Controls.Add($btnSkip)

    $btnCancel = New-Object ArvGlassButton
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(369, 252)
    $btnCancel.Size = New-Object System.Drawing.Size(85, 32)
    Set-ButtonStyle $btnCancel "Secondary"
    $dialog.Controls.Add($btnCancel)

    $script:OnboardingCanContinue = $false

    $refreshOnboarding = {
        $hasAuth = HasAuthFiles $CodexHome
        $runningText = if (Test-CodexProcessRunning) { "Codex is currently running." } else { "Codex is not running." }

        $profileLabel.Visible = $hasAuth
        $profileNameBox.Visible = $hasAuth
        $hint.Visible = $hasAuth
        $btnSave.Visible = $hasAuth
        $btnCancel.Visible = $hasAuth
        $btnOpenCodex.Visible = -not $hasAuth
        $btnSkip.Visible = -not $hasAuth

        if ($hasAuth) {
            $message.Text = "Codex auth files were found in your active .codex folder. Name this first saved profile, then save it before using the switcher.`r`n`r`n$runningText"
        } else {
            $message.Text = "No Codex auth files were found yet. Open Codex and sign in, then return here and refresh. You can also skip setup and create a profile later.`r`n`r`n$runningText"
        }
    }

    $btnSave.Add_Click({
        try {
            $name = Sanitize-ProfileName $profileNameBox.Text
            if (Test-ProfileFolderExists $name) {
                Show-Warn "Profile '$name' already exists. Choose a different name for the first profile."
                return
            }
            if (!(HasAuthFiles $CodexHome)) {
                Show-Warn "No Codex auth files were found. Open Codex, sign in, then refresh."
                & $refreshOnboarding
                return
            }

            if (Test-CodexProcessRunning) {
                $confirmed = Ask-YesNo "Codex is running. To save this first profile, Codex must be closed first.`r`n`r`nClose Codex now and save profile '$name'?"
                if (!$confirmed) { return }
                Close-CodexForOnboardingSave $name
            }

            $copied = Save-CurrentToProfile $name
            if ($copied -lt 1) {
                throw "No auth files were saved. Open Codex, sign in, then refresh onboarding."
            }

            Set-ActiveProfile $name
            Set-OnboardingComplete "saved first profile '$name'"
            Show-Info "Saved first profile: $name"
            if (Ask-YesNo "Open Codex now?") { [void](Start-CodexApp) }
            $script:OnboardingCanContinue = $true
            $dialog.Close()
        } catch {
            Show-Warn $_.Exception.Message
            & $refreshOnboarding
        }
    })

    $btnOpenCodex.Add_Click({ [void](Start-CodexApp) })
    $btnRefresh.Add_Click({ & $refreshOnboarding })
    $btnSkip.Add_Click({
        Set-OnboardingComplete "skipped setup"
        $script:OnboardingCanContinue = $true
        $dialog.Close()
    })
    $btnCancel.Add_Click({ $dialog.Close() })

    & $refreshOnboarding
    [void]$dialog.ShowDialog()
    return $script:OnboardingCanContinue
}

function Write-OperationResult($Text) {
    if ($ResultFile) {
        Set-Content -LiteralPath $ResultFile -Value $Text -Encoding UTF8
    } else {
        Write-Output $Text
    }
}

function Write-OperationError($Text) {
    if ($ErrorFile) {
        Set-Content -LiteralPath $ErrorFile -Value $Text -Encoding UTF8
    } else {
        [Console]::Error.WriteLine($Text)
    }
}

if ($Operation) {
    try {
        if ($Operation -ne "GetState") {
            Ensure-Dirs
        }
        switch ($Operation) {
            "GetState" {
                $active = Get-ActiveProfile -ReadOnly
                $profiles = @(Get-Profiles -ReadOnly | ForEach-Object {
                    $profilePath = Get-ProfilePath $_
                    $authCount = Get-AuthFileCount $profilePath
                    [pscustomobject]@{
                        name = $_
                        isActive = ($_ -eq $active)
                        authFileCount = $authCount
                        hasAuth = ($authCount -gt 0)
                    }
                })
                $activeAuthCount = if ($active) { Get-AuthFileCount (Get-ProfilePath $active) } else { 0 }
                $currentAuthCount = Get-AuthFileCount $CodexHome
                $state = [pscustomobject]@{
                    profiles = $profiles
                    activeProfile = $active
                    codexRunning = (Test-CodexProcessRunning)
                    onboardingComplete = (Test-OnboardingComplete)
                    codexHomeExists = (Test-Path $CodexHome)
                    activeAuthFileCount = $activeAuthCount
                    currentAuthFileCount = $currentAuthCount
                }
                Write-OperationResult ($state | ConvertTo-Json -Depth 5)
            }
            "StartEmptyProfile" {
                $name = Sanitize-ProfileName $ProfileName
                Close-CodexForOperation "starting a new login profile"
                Start-EmptyProfile $name
                Write-OperationResult "Started new login profile: $name`r`nOpen Codex and log in. Your existing projects and chat sessions stay in the shared .codex folder. After login completes, click 'Save active login' to capture this profile's auth."
            }
            "SaveFirstProfile" {
                $name = Sanitize-ProfileName $ProfileName
                if (Test-ProfileFolderExists $name) { throw "Profile already exists: $name" }
                Close-CodexForBackendFirstSave $name
                $copied = Save-CurrentToProfile $name
                if ($copied -lt 1) { throw "No Codex auth files were found. Open Codex, sign in, then try again." }
                Set-ActiveProfile $name
                Set-OnboardingComplete "saved first profile '$name'"
                Write-OperationResult "Saved first profile: $name"
            }
            "SwitchProfile" {
                $target = Sanitize-ProfileName $TargetProfile
                Close-CodexForOperation "switching profiles"
                $active = Get-ActiveProfile
                if ($active -and (HasAuthFiles $CodexHome)) {
                    [void](Save-CurrentToProfile $active)
                } elseif ($active) {
                    Write-Log "Skipped saving active profile '$active' before switch because active .codex has no auth files."
                }
                [void](Restore-ProfileToCurrent $target)
                $opened = Start-CodexApp
                if ($opened) {
                    Write-OperationResult "Switched to profile: $target`r`nCodex was re-opened."
                } else {
                    Write-OperationResult "Switched to profile: $target`r`nCodex could not be re-opened automatically. Open it manually."
                }
            }
            "SaveActive" {
                $active = Get-ActiveProfile
                if (!$active) { throw "No active profile is saved yet. Complete onboarding or prepare a new account login first." }
                $copied = Save-CurrentToProfile $active
                if ($copied -lt 1) { throw "No Codex auth files were found. Open Codex, sign in, then try again." }
                Write-OperationResult "Saved current auth files into active profile: $active"
            }
            "RenameProfile" {
                $target = Sanitize-ProfileName $TargetProfile
                $name = Sanitize-ProfileName $ProfileName
                Rename-Profile $target $name
                Write-OperationResult "Renamed profile '$target' to '$name'"
            }
            "DeleteProfile" {
                $target = Sanitize-ProfileName $TargetProfile
                Remove-Profile $target
                Write-OperationResult "Deleted profile: $target"
            }
        }
        exit 0
    } catch {
        Write-OperationError $_.Exception.Message
        exit 1
    }
}

Ensure-Dirs
if (Should-ShowOnboarding) {
    if (!(Show-OnboardingWizard)) { exit 0 }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = $WindowTitle
$form.ClientSize = New-Object System.Drawing.Size(555, 362)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(243, 243, 243)
$form.ForeColor = [System.Drawing.Color]::FromArgb(31, 31, 31)

function Set-Windows11ButtonStyle($Button, $Kind) {
    $Button.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $Button.Radius = 7
    $Button.DisabledBack = [System.Drawing.Color]::FromArgb(243, 243, 243)
    $Button.DisabledBorder = [System.Drawing.Color]::FromArgb(224, 224, 224)
    $Button.TextDisabled = [System.Drawing.Color]::FromArgb(150, 150, 150)

    switch ($Kind) {
        "Primary" {
            $Button.NormalBack = [System.Drawing.Color]::FromArgb(0, 103, 192)
            $Button.HoverBack = [System.Drawing.Color]::FromArgb(0, 95, 184)
            $Button.DownBack = [System.Drawing.Color]::FromArgb(0, 84, 163)
            $Button.Border = [System.Drawing.Color]::FromArgb(0, 91, 171)
            $Button.TextNormal = [System.Drawing.Color]::White
            $Button.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        }
        "Danger" {
            $Button.NormalBack = [System.Drawing.Color]::White
            $Button.HoverBack = [System.Drawing.Color]::FromArgb(253, 245, 245)
            $Button.DownBack = [System.Drawing.Color]::FromArgb(249, 232, 232)
            $Button.Border = [System.Drawing.Color]::FromArgb(218, 55, 60)
            $Button.TextNormal = [System.Drawing.Color]::FromArgb(164, 38, 44)
        }
        default {
            $Button.NormalBack = [System.Drawing.Color]::White
            $Button.HoverBack = [System.Drawing.Color]::FromArgb(249, 249, 249)
            $Button.DownBack = [System.Drawing.Color]::FromArgb(238, 238, 238)
            $Button.Border = [System.Drawing.Color]::FromArgb(205, 205, 205)
            $Button.TextNormal = [System.Drawing.Color]::FromArgb(31, 31, 31)
        }
    }
}

$title = New-Object System.Windows.Forms.Label
$title.Text = $HeaderText
$title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(18, 18, 18)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(25, 18)
$form.Controls.Add($title)

$status = New-Object System.Windows.Forms.Label
$status.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$status.ForeColor = [System.Drawing.Color]::FromArgb(55, 55, 55)
$status.AutoSize = $false
$status.Size = New-Object System.Drawing.Size(500, 38)
$status.Location = New-Object System.Drawing.Point(25, 56)
$form.Controls.Add($status)

$list = New-Object System.Windows.Forms.ListBox
$list.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$list.Location = New-Object System.Drawing.Point(25, 101)
$list.Size = New-Object System.Drawing.Size(250, 190)
$list.BackColor = [System.Drawing.Color]::White
$list.ForeColor = [System.Drawing.Color]::FromArgb(31, 31, 31)
$list.BorderStyle = "FixedSingle"
$form.Controls.Add($list)

$btnNewLogin = New-Object ArvGlassButton
$btnNewLogin.Text = "Add account"
$btnNewLogin.Location = New-Object System.Drawing.Point(301, 101)
$btnNewLogin.Size = New-Object System.Drawing.Size(208, 31)
Set-Windows11ButtonStyle $btnNewLogin "Secondary"
$form.Controls.Add($btnNewLogin)

$btnSave = New-Object ArvGlassButton
$btnSave.Text = "Save active login"
$btnSave.Location = New-Object System.Drawing.Point(301, 142)
$btnSave.Size = New-Object System.Drawing.Size(208, 31)
Set-Windows11ButtonStyle $btnSave "Secondary"
$form.Controls.Add($btnSave)

$btnSwitch = New-Object ArvGlassButton
$btnSwitch.Text = "Switch profile"
$btnSwitch.Location = New-Object System.Drawing.Point(301, 183)
$btnSwitch.Size = New-Object System.Drawing.Size(208, 36)
Set-Windows11ButtonStyle $btnSwitch "Primary"
$form.Controls.Add($btnSwitch)

$btnRename = New-Object ArvGlassButton
$btnRename.Text = "Rename"
$btnRename.Location = New-Object System.Drawing.Point(301, 232)
$btnRename.Size = New-Object System.Drawing.Size(98, 31)
Set-Windows11ButtonStyle $btnRename "Secondary"
$form.Controls.Add($btnRename)

$btnDelete = New-Object ArvGlassButton
$btnDelete.Text = "Delete"
$btnDelete.Location = New-Object System.Drawing.Point(411, 232)
$btnDelete.Size = New-Object System.Drawing.Size(98, 31)
Set-Windows11ButtonStyle $btnDelete "Danger"
$form.Controls.Add($btnDelete)

$btnRefresh = New-Object ArvGlassButton
$btnRefresh.Text = "Refresh"
$btnRefresh.Location = New-Object System.Drawing.Point(301, 278)
$btnRefresh.Size = New-Object System.Drawing.Size(208, 31)
Set-Windows11ButtonStyle $btnRefresh "Secondary"
$form.Controls.Add($btnRefresh)

function Refresh-UI {
    $list.Items.Clear()
    $profiles = @(Get-Profiles)
    foreach ($p in $profiles) { [void]$list.Items.Add($p) }
    $active = Get-ActiveProfile
    $script:UiActiveProfile = $active
    if ($profiles -contains $active) { $list.SelectedItem = $active }
    $isRunning = Test-CodexProcessRunning
    $running = if ($isRunning) { "Codex appears to be running. Create/switch will auto-close it first." } else { "Codex appears to be closed." }
    $activeDisplay = if ($active) { Get-DisplayText $active 44 } else { "" }
    $activeText = if ($active) { "Active profile: $activeDisplay" } else { "No active profile saved yet." }
    $authText = ""
    $authCount = 0
    if ($active) {
        $authCount = Get-AuthFileCount (Get-ProfilePath $active)
        $authText = if ($authCount -gt 0) { "Saved auth files: $authCount." } else { "This profile has no saved auth yet." }
    }
    $detailText = if ($authText) { "$authText $running" } else { $running }
    $status.Text = "$activeText`r`n$detailText"
    Update-ActionButtonStates
}

function Update-SwitchButtonState {
    if ($script:CurrentOperationProcess -ne $null) {
        $btnSwitch.Enabled = $false
        return
    }

    if ($list.SelectedItem -eq $null) {
        $btnSwitch.Enabled = $false
        return
    }

    $selected = [string]$list.SelectedItem
    $active = Get-ActiveProfile
    $btnSwitch.Enabled = ($selected -ne $active)
}

function Update-NewLoginButtonState {
    if ($script:CurrentOperationProcess -ne $null) {
        $btnNewLogin.Enabled = $false
        return
    }

    $btnNewLogin.Enabled = $true
}

function Update-SaveButtonState {
    if ($script:CurrentOperationProcess -ne $null) {
        $btnSave.Enabled = $false
        return
    }

    $btnSave.Enabled = -not [string]::IsNullOrWhiteSpace((Get-ActiveProfile))
}

function Update-RenameButtonState {
    if ($script:CurrentOperationProcess -ne $null) {
        $btnRename.Enabled = $false
        return
    }

    if ($list.SelectedItem -eq $null) {
        $btnRename.Enabled = $false
        return
    }

    $selected = [string]$list.SelectedItem
    $active = Get-ActiveProfile
    $btnRename.Enabled = ($selected -ne $active)
}

function Update-DeleteButtonState {
    if ($script:CurrentOperationProcess -ne $null) {
        $btnDelete.Enabled = $false
        return
    }

    if ($list.SelectedItem -eq $null) {
        $btnDelete.Enabled = $false
        return
    }

    $selected = [string]$list.SelectedItem
    $active = Get-ActiveProfile
    $btnDelete.Enabled = ($selected -ne $active)
}

function Update-ActionButtonStates {
    Update-SwitchButtonState
    Update-NewLoginButtonState
    Update-SaveButtonState
    Update-RenameButtonState
    Update-DeleteButtonState
}

function Set-OperationControlsEnabled($Enabled) {
    foreach ($control in @($btnNewLogin, $btnSave, $btnSwitch, $btnRename, $btnDelete, $btnRefresh, $list)) {
        $control.Enabled = $Enabled
    }

    if ($Enabled) { Update-ActionButtonStates }
}

function Quote-CommandLineArgument($Value) {
    return '"' + ([string]$Value -replace '"', '\"') + '"'
}

function Read-TrimmedFile($Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path $Path)) { return "" }

    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { return "" }

    return $content.Trim()
}

function Get-OperationLauncher {
    $currentProcessPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $currentProcessName = [System.IO.Path]::GetFileName($currentProcessPath)
    $hostNames = @("powershell.exe", "powershell_ise.exe", "pwsh.exe")

    if ($hostNames -notcontains $currentProcessName.ToLowerInvariant()) {
        return @{
            FilePath = $currentProcessPath
            Arguments = @()
        }
    }

    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        throw "Could not determine script path for background operation."
    }

    return @{
        FilePath = "powershell.exe"
        Arguments = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", (Quote-CommandLineArgument $scriptPath)
        )
    }
}

function Get-CompletedProcessExitCode($Process) {
    try {
        $Process.Refresh()
        [void]$Process.WaitForExit(1000)
        return $Process.ExitCode
    } catch {
        return $null
    }
}

$script:CurrentOperationProcess = $null
$script:CurrentOperationName = ""
$script:CurrentOperationStartedAt = $null
$script:CurrentOperationOutput = ""
$script:CurrentOperationError = ""

$operationTimer = New-Object System.Windows.Forms.Timer
$operationTimer.Interval = 500
$operationTimer.Add_Tick({
    try {
        if ($script:CurrentOperationProcess -eq $null) { return }

        if (-not $script:CurrentOperationProcess.HasExited) {
            $elapsed = [int]((Get-Date) - $script:CurrentOperationStartedAt).TotalSeconds
            $status.Text = "$($script:CurrentOperationName) in progress | $elapsed seconds elapsed"
            return
        }

        $operationTimer.Stop()
        $exitCode = Get-CompletedProcessExitCode $script:CurrentOperationProcess
        $output = Read-TrimmedFile $script:CurrentOperationOutput
        $errorText = Read-TrimmedFile $script:CurrentOperationError

        Remove-Item -LiteralPath $script:CurrentOperationOutput, $script:CurrentOperationError -Force -ErrorAction SilentlyContinue

        $completedOperation = $script:CurrentOperationName
        $script:CurrentOperationProcess = $null
        $script:CurrentOperationName = ""
        $script:CurrentOperationStartedAt = $null
        $script:CurrentOperationOutput = ""
        $script:CurrentOperationError = ""

        Set-OperationControlsEnabled $true
        Refresh-UI

        $treatAsSuccess = ($exitCode -eq 0) -or ($output -and !$errorText)

        if ($treatAsSuccess) {
            if ($output) { Show-Info $output } else { Show-Info "$completedOperation completed." }
        } else {
            if (!$errorText) {
                if ($null -eq $exitCode) {
                    $errorText = "$completedOperation may have failed, but PowerShell did not report an exit code."
                } else {
                    $errorText = "$completedOperation failed with exit code $exitCode."
                }
            }
            Show-Warn $errorText
        }
    } catch {
        $operationTimer.Stop()
        $script:CurrentOperationProcess = $null
        $script:CurrentOperationName = ""
        $script:CurrentOperationStartedAt = $null
        Remove-Item -LiteralPath $script:CurrentOperationOutput, $script:CurrentOperationError -Force -ErrorAction SilentlyContinue
        $script:CurrentOperationOutput = ""
        $script:CurrentOperationError = ""
        Set-OperationControlsEnabled $true
        Refresh-UI
        Show-Warn "Operation status update failed: $($_.Exception.Message)"
    }
})

function Start-ProfileOperation($OperationName, $DisplayName, $Arguments) {
    if ($script:CurrentOperationProcess -ne $null) {
        Show-Warn "Another operation is already running."
        return
    }

    $outFile = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-profile-switcher-" + [guid]::NewGuid().ToString("N") + ".out")
    $errFile = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-profile-switcher-" + [guid]::NewGuid().ToString("N") + ".err")
    $launcher = Get-OperationLauncher

    $argList = @($launcher.Arguments) + @(
        "-Operation", (Quote-CommandLineArgument $OperationName),
        "-ResultFile", (Quote-CommandLineArgument $outFile),
        "-ErrorFile", (Quote-CommandLineArgument $errFile)
    )

    foreach ($key in $Arguments.Keys) {
        $argList += "-$key"
        $argList += (Quote-CommandLineArgument $Arguments[$key])
    }

    try {
        Set-OperationControlsEnabled $false
        $status.Text = "$DisplayName in progress | Starting background operation"
        $form.Refresh()

        $process = Start-Process -FilePath $launcher.FilePath -ArgumentList ($argList -join " ") -WindowStyle Hidden -PassThru

        $script:CurrentOperationProcess = $process
        $script:CurrentOperationName = $DisplayName
        $script:CurrentOperationStartedAt = Get-Date
        $script:CurrentOperationOutput = $outFile
        $script:CurrentOperationError = $errFile
        $operationTimer.Start()
    } catch {
        Set-OperationControlsEnabled $true
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
        Show-Warn $_.Exception.Message
        Refresh-UI
    }
}

$btnNewLogin.Add_Click({
    try {
        $name = Prompt-ForProfileName "Name new account profile" "Enter a name for the account you want to add." ""
        if (!$name) { return }
        if (Test-ProfileFolderExists $name) { Show-Warn "Profile '$name' already exists."; return }
        if (!(Ask-YesNo "Add account profile '$name'?`r`n`r`nThis saves the current active auth profile, closes Codex, and clears only the active auth files so Codex can show the login screen.`r`n`r`nDo not use this if you only want to switch to an existing profile.")) { return }
        Start-ProfileOperation "StartEmptyProfile" "Preparing new account login '$name'" @{ ProfileName = $name }
    } catch { Show-Warn $_.Exception.Message }
})

$btnSwitch.Add_Click({
    try {
        if ($list.SelectedItem -eq $null) { Show-Warn "Select a profile first."; return }
        $target = [string]$list.SelectedItem
        if (!(HasAuthFiles (Get-ProfilePath $target))) {
            if (!(Ask-YesNo "Profile '$target' has no saved auth files. Switching to it will clear the active Codex auth files.`r`n`r`nSwitch anyway?")) { return }
        }
        $active = Get-ActiveProfile
        if ($target -eq $active) {
            Show-Info "Profile '$target' is already active."
            Update-SwitchButtonState
            return
        }
        Start-ProfileOperation "SwitchProfile" "Switching to profile '$target'" @{ TargetProfile = $target }
    } catch { Show-Warn $_.Exception.Message }
})

$btnRename.Add_Click({
    try {
        if ($list.SelectedItem -eq $null) { Show-Warn "Select a profile first."; return }
        $target = [string]$list.SelectedItem
        $active = Get-ActiveProfile
        if ($target -eq $active) { Show-Warn "Cannot rename the active profile. Switch to another profile first."; return }
        $name = Prompt-ForProfileName "Rename profile" "Enter a new name for profile '$target'." $target
        if (!$name) { return }
        if ($name -eq $target) { Show-Warn "New profile name must be different from the current name."; return }
        if (Test-ProfileFolderExists $name) { Show-Warn "Profile '$name' already exists."; return }
        Start-ProfileOperation "RenameProfile" "Renaming profile '$target'" @{ TargetProfile = $target; ProfileName = $name }
    } catch { Show-Warn $_.Exception.Message }
})

$btnSave.Add_Click({
    try {
        $active = Get-ActiveProfile
        if (!$active) { Show-Warn "No active profile is saved yet. Complete onboarding or prepare a new account login first."; return }
        Start-ProfileOperation "SaveActive" "Saving active profile '$active'" @{}
    } catch { Show-Warn $_.Exception.Message }
})

$btnDelete.Add_Click({
    try {
        if ($list.SelectedItem -eq $null) { Show-Warn "Select a profile first."; return }
        $target = [string]$list.SelectedItem
        if ($target -eq (Get-ActiveProfile)) { Show-Warn "Cannot delete the active profile. Switch to another profile first."; return }
        if (!(Confirm-DeleteProfile $target)) { return }
        Start-ProfileOperation "DeleteProfile" "Deleting profile '$target'" @{ TargetProfile = $target }
    } catch { Show-Warn $_.Exception.Message }
})

$btnRefresh.Add_Click({ Refresh-UI })
$list.Add_SelectedIndexChanged({ Update-ActionButtonStates })

Refresh-UI
[void]$form.ShowDialog()
