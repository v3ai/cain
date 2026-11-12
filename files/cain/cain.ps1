# cain - Collects And INstalls dotfiles, keybindings and programs: the Windows version.
#
# Plain Windows PowerShell 5.1 (built into Windows 10 and 11), so there's nothing to
# install or build. Run it through cain.cmd: `cain`, `cain -i`, `cain keys`, ...
# Linux and macOS use the `cain` shell script instead; both read files/cain.json.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$Usage = @'
usage: cain [command] [args...] [-n]

  cain                 first time on this PC: install; after that, ask install or collect
  cain -c | collect    copy this PC's configs into the repo, commit and push
  cain -i | install    pick what to install from a menu (full, light, dotfiles, ...)
  cain install light   skip the menu: full light dotfiles keybindings
  cain install keys    or name install steps: packages git files bin shell keys desktop
  cain keys            shorthand for `cain install keys`
  cain generate        print the AutoHotkey script cain would write
  cain booklister      pick a book from ~/Desktop/books and open it
  cain listlauncher    edit list.html on the website, then commit and push
  -y, --yes            install everything without the menu
  -n, --dry-run        show what would happen without changing anything

'@

$Ascii = @'

                         db

      ,p6"bo   ,6"Yb.  `7MM  `7MMpMMMb.
     6M'  OO  8)   MM    MM    MM    MM
     8M        ,pm9MM    MM    MM    MM
     YM.    , 8M   MM    MM    MM    MM
      YMbmd'  `Moo9^Yo..JMML..JMML  JMML.

'@

$Steps = @('packages', 'git', 'files', 'bin', 'shell', 'keys', 'desktop')
$script:Dry = $false
$script:Remembered = $false

# ------------------------------------------------------------------ messages

function Say([string]$text) { [Console]::Out.WriteLine($text) }
function Warn([string]$text) { [Console]::Out.WriteLine("  WARNING: $text") }
function Die([string]$text) { [Console]::Error.WriteLine("cain: $text"); exit 1 }
function Step([string]$title) { Say ''; Say "== $title ==" }

# ------------------------------------------------------------------ paths

# $HOME (if set, like on Linux) or the user profile folder
$script:Home_ = $env:HOME
if (-not $script:Home_) { $script:Home_ = $env:USERPROFILE }

function Expand-Path([string]$p) {
    if ($p -eq '~') { return $script:Home_ }
    if ($p.StartsWith('~/') -or $p.StartsWith('~\')) { $p = $script:Home_ + $p.Substring(1) }
    return $p -replace '/', '\'
}

# ------------------------------------------------------------------ running things

function Quote-Arg([string]$a) {
    if ($a -eq '') { return '""' }
    if ($a -match '[\s"]') { return '"' + ($a -replace '"', '\"') + '"' }
    return $a
}

function Test-Command([string]$name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }

# Run a program, showing the command; in dry-run only show it. Returns the exit code.
function Invoke-Cain([string]$exe, [string[]]$arguments = @()) {
    $shown = (@($exe) + $arguments | ForEach-Object { Quote-Arg $_ }) -join ' '
    if ($script:Dry) { Say "  [dry-run] $shown"; return 0 }
    Say "  `$ $shown"
    if (-not (Test-Command $exe)) { Warn "command not found: $exe"; return 127 }
    & $exe @arguments | ForEach-Object { Say "$_" }
    return $LASTEXITCODE
}

function Ask([string]$question, [bool]$default) {
    if ($script:Dry -or [Console]::IsInputRedirected) { return $default }
    $suffix = if ($default) { ' [Y/n]: ' } else { ' [y/N]: ' }
    [Console]::Out.Write($question + $suffix)
    $answer = [Console]::In.ReadLine()
    if (-not $answer) { return $default }
    return $answer.Trim().StartsWith('y', 'OrdinalIgnoreCase')
}

$script:Utf8 = New-Object System.Text.UTF8Encoding $false

function Write-Text([string]$path, [string]$content) {
    if ($script:Dry) { Say "  [dry-run] write $path ($($script:Utf8.GetByteCount($content)) bytes)"; return }
    try {
        $dir = Split-Path $path -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        [IO.File]::WriteAllText($path, $content, $script:Utf8)
        Say "  wrote $path"
    } catch { Warn "can't write ${path}: $($_.Exception.Message)" }
}

function Test-SameFile([string]$a, [string]$b) {
    if (-not (Test-Path $a -PathType Leaf) -or -not (Test-Path $b -PathType Leaf)) { return $false }
    $x = [IO.File]::ReadAllBytes($a); $y = [IO.File]::ReadAllBytes($b)
    if ($x.Length -ne $y.Length) { return $false }
    return [Convert]::ToBase64String($x) -eq [Convert]::ToBase64String($y)
}

# Copy src -> dest, first backing up a different existing dest into $backup.
function Copy-CainFile([string]$src, [string]$dest, [string]$backup = '') {
    if ($backup -and (Test-Path $dest) -and -not (Test-SameFile $src $dest)) {
        $target = Join-Path $backup (Split-Path $dest -Leaf)
        if ($script:Dry) { Say "  [dry-run] backup $dest -> $target" }
        else { New-Item -ItemType Directory -Force -Path $backup | Out-Null; Copy-Item $dest $target -Force }
    }
    if ($script:Dry) { Say "  [dry-run] copy $src -> $dest"; return }
    try {
        $dir = Split-Path $dest -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Copy-Item $src $dest -Force
    } catch { Warn "can't write ${dest}: $($_.Exception.Message)" }
}

# Insert or replace a '# >>> cain >>>' managed block in a text file (e.g. $PROFILE).
function Set-Block([string]$path, [string]$block) {
    $start = '# >>> cain >>>'; $end = '# <<< cain <<<'
    $text = ''
    if (Test-Path $path) { $text = [IO.File]::ReadAllText($path) }
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $new = "$start$nl$block$nl$end$nl"
    $s = $text.IndexOf($start)
    $e = if ($s -ge 0) { $text.IndexOf($end, $s) } else { -1 }
    if ($s -ge 0 -and $e -ge 0) {
        $after = $text.Substring($e + $end.Length).TrimStart("`r", "`n")
        $out = $text.Substring(0, $s) + $new + $after
    } elseif ($text -eq '') {
        $out = $new
    } elseif ($text.EndsWith("`n")) {
        $out = $text + $nl + $new
    } else {
        $out = $text + $nl + $nl + $new
    }
    Write-Text $path $out
}

# ------------------------------------------------------------------ cain.json

function Get-Prop($obj, [string]$name) {
    if ($null -eq $obj -or $obj -isnot [psobject]) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($p) { return $p } else { return $null }
}

function Get-Str($obj, [string]$name, [string]$default = '') {
    $p = Get-Prop $obj $name
    if ($p -and $p.Value -is [string]) { return $p.Value }
    return $default
}

function Test-Applies($entry) {
    $os = Get-Prop $entry 'os'
    if ($os -and -not (@($os.Value) -contains 'windows')) { return $false }
    if (Get-Prop $entry 'desktop') { return $false }   # desktop entries are for Linux desktops
    return $true
}

# Modifier bits, in print order. (PowerShell names ignore case: never call another variable $bits.)
$ModNames = @('super', 'lsuper', 'rsuper', 'ctrl', 'lctrl', 'rctrl', 'alt', 'lalt', 'ralt', 'shift')
$Bits = @{ SUPER = 1; LSUPER = 2; RSUPER = 4; CTRL = 8; LCTRL = 16; RCTRL = 32; ALT = 64; LALT = 128; RALT = 256; SHIFT = 512 }
$AnyAlt = 64 + 128 + 256
$NamedKeys = @(
    'comma period slash semicolon quote bracketleft bracketright backslash minus equal grave tab enter',
    'esc backspace delete space capslock left right up down home end pageup pagedown',
    'a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9',
    'f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12') -join ' ' -split ' '
$Aliases = @{ escape = 'esc'; return = 'enter'; dot = 'period'; apostrophe = 'quote'; leftbrace = 'bracketleft'
    rightbrace = 'bracketright'; control = 'ctrl'; win = 'super'; cmd = 'super'; meta = 'super'; option = 'alt'
    caps = 'capslock'; bksp = 'backspace'; del = 'delete' }

function ConvertTo-Combo([string]$text) {
    $parts = $text.ToLower().Replace(' ', '').Split('+')
    $mods = 0
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $name = $parts[$i]; if ($Aliases.ContainsKey($name)) { $name = $Aliases[$name] }
        $bit = [array]::IndexOf($ModNames, $name)
        if ($bit -lt 0) { return $null }
        $mods = $mods -bor (1 -shl $bit)
    }
    $key = $parts[-1]; if ($Aliases.ContainsKey($key)) { $key = $Aliases[$key] }
    if ($NamedKeys -notcontains $key) { return $null }
    return @{ m = $mods; k = $key }
}

function Get-Combo([string]$text) {
    $c = ConvertTo-Combo $text
    if ($null -eq $c) { Die "cain.json: can't understand the key combo `"$text`"" }
    return $c
}

function Format-Combo($c) {
    $s = ''
    for ($i = 0; $i -lt 10; $i++) { if ($c.m -band (1 -shl $i)) { $s += $ModNames[$i] + '+' } }
    return $s + $c.k
}

function Get-Generic([int]$mods) {
    $g = $mods -band ($Bits.SUPER -bor $Bits.CTRL -bor $Bits.ALT -bor $Bits.SHIFT)
    if ($mods -band ($Bits.LSUPER -bor $Bits.RSUPER)) { $g = $g -bor $Bits.SUPER }
    if ($mods -band ($Bits.LCTRL -bor $Bits.RCTRL)) { $g = $g -bor $Bits.CTRL }
    if ($mods -band ($Bits.LALT -bor $Bits.RALT)) { $g = $g -bor $Bits.ALT }
    return $g
}

function Read-Manifest {
    $path = Join-Path $script:Root 'files\cain.json'
    try { $text = [IO.File]::ReadAllText($path) } catch { Die "can't read $path" }
    try { $j = $text | ConvertFrom-Json } catch { Die "${path}: $($_.Exception.Message)" }
    if ($j -isnot [psobject]) { Die "${path}: expected a JSON object" }
    $script:J = $j
    $script:Settings = if (Get-Prop $j 'settings') { $j.settings } else { $null }

    $script:Remaps = @()
    if (Get-Prop $j 'remaps') {
        foreach ($r in @($j.remaps)) {
            if (-not (Test-Applies $r)) { continue }
            $from = Get-Str $r 'from'; $to = Get-Str $r 'to'
            if (-not $from -or -not $to) { Die 'cain.json: every remap needs "from" and "to"' }
            $f = Get-Combo $from
            $ov = Get-Prop $r 'windows'   # e.g. "windows": "ctrl+shift+v", or null to skip
            if ($ov) {
                if ($ov.Value -isnot [string]) { continue }
                $t = Get-Combo $ov.Value
            } else { $t = Get-Combo $to }
            if ($f.m -eq $t.m -and $f.k -eq $t.k) { continue }
            $script:Remaps += , @{ from = $f; to = $t }
        }
    }

    $script:Shortcuts = @()
    if (Get-Prop $j 'shortcuts') {
        foreach ($s in @($j.shortcuts)) {
            if (-not (Test-Applies $s)) { continue }
            $action = Get-Str $s 'action'
            $keys = Get-Prop $s 'keys'
            if (-not $action -or -not $keys) { Die 'cain.json: every shortcut needs "action" and a "keys" list' }
            $combos = @()
            foreach ($k in @($keys.Value)) {
                if ($k -isnot [string]) { Die 'cain.json: shortcut keys must be strings' }
                $combos += , (Get-Combo $k)
            }
            $script:Shortcuts += , @{ entry = $s; action = $action; keys = $combos }
        }
    }
}

# ------------------------------------------------------------------ AutoHotkey

$AhkKeys = @{ comma = 'vkBC'; period = 'vkBE'; slash = 'vkBF'; semicolon = 'vkBA'; quote = 'vkDE'
    bracketleft = 'vkDB'; bracketright = 'vkDD'; backslash = 'vkDC'; minus = 'vkBD'; equal = 'vkBB'; grave = 'vkC0'
    tab = 'Tab'; enter = 'Enter'; esc = 'Esc'; backspace = 'Backspace'; delete = 'Delete'; space = 'Space'
    capslock = 'CapsLock'; left = 'Left'; right = 'Right'; up = 'Up'; down = 'Down'; home = 'Home'; end = 'End'
    pageup = 'PgUp'; pagedown = 'PgDn' }
$AhkMods = @('#', '<#', '>#', '^', '<^', '>^', '!', '<!', '>!', '+')
$Selectable = @('left', 'right', 'up', 'down', 'home', 'end', 'pageup', 'pagedown', 'tab')
$WmActions = @('close_window', 'minimize', 'toggle_maximize', 'tile_left', 'tile_right', 'show_desktop', 'switch_windows', 'lock_screen')
$AhkWm = @{ close_window = 'WinClose "A"'; minimize = 'WinMinimize "A"'; toggle_maximize = 'ToggleMax()'
    tile_left = 'Send "#{Left}"'; tile_right = 'Send "#{Right}"'; show_desktop = 'Send "#d"'
    lock_screen = 'DllCall("LockWorkStation")' }

function Get-AhkKey([string]$k) {
    if ($AhkKeys.ContainsKey($k)) { return $AhkKeys[$k] }
    if ($k -match '^f[1-9]') { return $k.ToUpper() }
    return $k
}

function Get-AhkHotkey($c) {
    $s = ''
    for ($i = 0; $i -lt 10; $i++) { if ($c.m -band (1 -shl $i)) { $s += $AhkMods[$i] } }
    return $s + (Get-AhkKey $c.k)
}

function Get-AhkSend($c) {
    $g = Get-Generic $c.m
    $s = ''
    if ($g -band $Bits.SUPER) { $s += '#' }
    if ($g -band $Bits.CTRL) { $s += '^' }
    if ($g -band $Bits.ALT) { $s += '!' }
    if ($g -band $Bits.SHIFT) { $s += '+' }
    $k = Get-AhkKey $c.k
    if ($k.Length -gt 1) { return "$s{$k}" } else { return "$s$k" }
}

function ConvertTo-AhkString([string]$s) { return '"' + $s.Replace('`', '``').Replace('"', '`"') + '"' }

# The command a launch shortcut runs, or '' (window-manager action, or none for Windows).
function Get-LaunchCommand($sc) {
    $a = $sc.action
    if ($WmActions -contains $a) { return '' }
    $run = Get-Prop $sc.entry 'run'
    if ($run) {
        if ($run.Value -is [string]) { return $run.Value }
        return Get-Str $run.Value 'windows'
    }
    if ($a.StartsWith('tool:')) {
        $exe = ($script:Home_ + '/.local/bin/cain.cmd') -replace '/', '\'
        return "`"$exe`" " + $a.Substring(5)
    }
    $url = Get-Str $script:Settings 'homepage' 'https://www.google.com'
    switch ($a) {
        'terminal' { return 'wt.exe' }
        'calculator' { return 'calc.exe' }
        'browser' { return $url }
        'file_manager' { return "explorer.exe `"$($script:Home_)`"" }
    }
    Die "cain.json: unknown shortcut action `"$a`" (give it a `"run`" command)"
}

function New-AhkScript {
    $out = New-Object System.Text.StringBuilder
    $seen = @{}
    $add = {
        param($hk, $body)
        if ($seen.ContainsKey($hk)) { Warn "duplicate Windows hotkey $hk skipped"; return }
        $seen[$hk] = $true
        [void]$out.Append("${hk}::$body`n")
    }
    [void]$out.Append("; Generated by cain from cain.json - edit that file and re-run ``cain keys``.`n")
    [void]$out.Append("#Requires AutoHotkey v2.0`n#SingleInstance Force`nSendMode `"Input`"`n")
    [void]$out.Append("A_MenuMaskKey := `"vkE8`"  ; stops a lone Alt tap from opening menus`n`n; ---- key remaps`n")
    foreach ($r in $script:Remaps) {
        $src = $r.from; $dst = $r.to
        $body = 'Send "' + (Get-AhkSend $dst) + '"'
        if ($src.m -eq 0) {
            if ($dst.m) { & $add (Get-AhkKey $src.k) $body } else { & $add (Get-AhkKey $src.k) (Get-AhkKey $dst.k) }
        } else {
            & $add (Get-AhkHotkey $src) $body
            if ($dst.m -eq 0 -and $Selectable -contains $dst.k -and -not ($src.m -band $Bits.SHIFT)) {
                # keep Shift working for selecting: Alt+Shift+H -> Shift+Left
                $hk = Get-AhkHotkey @{ m = ($src.m -bor $Bits.SHIFT); k = $src.k }
                & $add $hk ('Send "' + (Get-AhkSend @{ m = $Bits.SHIFT; k = $dst.k }) + '"')
            }
        }
    }
    [void]$out.Append("`n; ---- shortcuts`n")
    foreach ($sc in $script:Shortcuts) {
        foreach ($c in $sc.keys) {
            $cs = Format-Combo $c
            $hk = Get-AhkHotkey $c
            $native = ($sc.action -eq 'switch_windows' -and $cs -eq 'alt+tab') -or ($sc.action -eq 'show_desktop' -and $cs -eq 'super+d')
            if ($native) { continue }   # Windows already does this one
            if ($sc.action -eq 'switch_windows') {
                # AltTab only works on "LAlt & key" style hotkeys
                $alt = $c.m -band $AnyAlt
                $key = Get-AhkKey $c.k
                if ($alt -and $c.m -eq $alt) {
                    if ($alt -ne $Bits.RALT) { & $add "LAlt & $key" 'AltTab' }
                    if ($alt -ne $Bits.LALT) { & $add "RAlt & $key" 'AltTab' }
                } else { & $add $hk 'Send "!{Tab}"' }
            } elseif ($AhkWm.ContainsKey($sc.action)) {
                & $add $hk $AhkWm[$sc.action]
            } else {
                $cmd = Get-LaunchCommand $sc
                if ($cmd) {
                    $q = ConvertTo-AhkString $cmd
                    # cain's own tools run in a console: hide it
                    if ($sc.action.StartsWith('tool:')) { & $add $hk "RunCmd($q, `"Hide`")" } else { & $add $hk "RunCmd($q)" }
                }
            }
        }
    }
    $footer = @'

ToggleMax() {
    try {
        if WinGetMinMax("A") = 1
            WinRestore "A"
        else
            WinMaximize "A"
    }
}

RunCmd(cmd, opts := "") {
    try Run cmd, , opts
    catch as e
        MsgBox "cain could not run:`n" cmd "`n`n" e.Message
}

'@
    [void]$out.Append($footer.Replace("`r`n", "`n"))
    return $out.ToString()
}

# ------------------------------------------------------------------ install steps

function Find-Winget { return Test-Command 'winget' }

function Install-Winget([string[]]$ids) {
    if (-not (Find-Winget) -and -not $script:Dry) {
        Warn ("winget not found (it ships with Windows 10 21H2+/11 as 'App Installer'). Install by hand: " + ($ids -join ' '))
        return
    }
    foreach ($id in $ids) {
        Invoke-Cain 'winget' @('install', '--id', $id, '-e', '--silent', '--accept-source-agreements', '--accept-package-agreements') | Out-Null
    }
}

function Install-Packages {
    $ids = @(); $missing = @()
    if (Get-Prop $script:J 'packages') {
        foreach ($p in @($script:J.packages)) {
            if (-not (Test-Applies $p)) { continue }
            $name = Get-Str $p 'name'
            if (-not $name) { Die 'cain.json: every package needs a "name"' }
            $id = Get-Str $p 'winget'
            if ($id) { $ids += $id } else { $missing += $name }
        }
    }
    if ($missing) { Say ("  no winget id in cain.json for: " + ($missing -join ', ') + ' (skipped)') }
    Install-Winget $ids
}

function Install-Git {
    $g = if (Get-Prop $script:J 'git') { $script:J.git } else { $null }
    $name = Get-Str $g 'name'; $email = Get-Str $g 'email'
    if ($name) { Invoke-Cain 'git' @('config', '--global', 'user.name', $name) | Out-Null }
    if ($email) { Invoke-Cain 'git' @('config', '--global', 'user.email', $email) | Out-Null }
}

function Get-CainFiles {
    $list = @()
    if (Get-Prop $script:J 'files') {
        foreach ($f in @($script:J.files)) {
            if (-not (Test-Applies $f)) { continue }
            $src = Get-Str $f 'src'; $dest = Get-Str $f 'dest'
            if (-not $src -or -not $dest) { Die 'cain.json: every file needs "src" and "dest"' }
            $list += , @{ src = $src; dest = $dest }
        }
    }
    return , $list
}

function Install-Files {
    $backup = Expand-Path ('~/.cain-backup/' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    foreach ($f in (Get-CainFiles)) {
        $src = Join-Path $script:Root ($f.src -replace '/', '\'); $dest = Expand-Path $f.dest
        if (Test-SameFile $src $dest) { Say "  SAME:      $($f.dest)" }
        else { Copy-CainFile $src $dest $backup; Say "  INSTALLED: $($f.dest)" }
    }
    if (Test-Path $backup) { Say "  (previous versions backed up in $backup)" }
}

function Send-SettingChange {
    if (-not ('Cain.Native' -as [type])) {
        Add-Type -Namespace Cain -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
[DllImport("user32.dll", CharSet = CharSet.Auto)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@
    }
    $r = [UIntPtr]::Zero
    [void][Cain.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 2000, [ref]$r)
}

function Add-UserPath([string]$folder) {
    if ($script:Dry) { Say "  [dry-run] add $folder to the user PATH"; return }
    $key = Get-Item 'HKCU:\Environment'
    $current = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $parts = @($current -split ';' | Where-Object { $_ })
    if ($parts | Where-Object { $_.TrimEnd('\') -ieq $folder.TrimEnd('\') }) { return }
    Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value (($parts + $folder) -join ';') -Type ExpandString
    Send-SettingChange
    Say "  added $folder to your PATH (new terminals will see it)"
}

function Save-Repo {
    if ($script:Remembered) { return }
    $script:Remembered = $true
    $marker = Expand-Path '~/.config/cain/repo'
    $line = $script:Root + "`n"
    if (-not (Test-Path $marker) -or [IO.File]::ReadAllText($marker) -ne $line) { Write-Text $marker $line }
}

# Put a small `cain.cmd` on PATH that runs this repo's cain.ps1.
function Install-Bin {
    $dir = Expand-Path '~/.local/bin'
    $dest = Join-Path $dir 'cain.cmd'
    # PSModulePath is cleared because, started from PowerShell 7, it points at modules Windows PowerShell can't load
    $shim = "@echo off`r`nsetlocal`r`nset PSModulePath=`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $script:Root 'files\cain\cain.ps1')`" %*`r`n"
    if ((Test-Path $dest) -and [IO.File]::ReadAllText($dest) -eq $shim) { Say "  SAME:      $dest" }
    else { Write-Text $dest $shim; Say "  INSTALLED: $dest" }
    Add-UserPath $dir
    Save-Repo
}

function Install-Shell {
    $block = 'if (Test-Path "$HOME\.config\cain\cain.ps1") { . "$HOME\.config\cain\cain.ps1" }'
    $profiles = @()
    foreach ($shell in 'powershell', 'pwsh') {
        if (-not (Test-Command $shell)) { continue }
        $p = (& $shell -NoProfile -Command '$PROFILE' | Select-Object -First 1)
        if ($p -and $profiles -notcontains $p) { $profiles += $p }
    }
    foreach ($p in $profiles) { Set-Block $p $block }
    # Windows refuses to run profile scripts until this is relaxed for the user
    if ($script:Dry) { Say '  [dry-run] Set-ExecutionPolicy -Scope CurrentUser RemoteSigned' }
    else {
        Say '  $ Set-ExecutionPolicy -Scope CurrentUser RemoteSigned'
        try { Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force } catch { Warn $_.Exception.Message }
    }
}

function Test-AutoHotkey {
    $places = @()
    if ($env:ProgramFiles) { $places += Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe' }
    if ($env:LOCALAPPDATA) { $places += Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe' }
    foreach ($p in $places) { if (Test-Path $p) { return $true } }
    return (Test-Command 'AutoHotkey64') -or (Test-Command 'AutoHotkey')
}

function Install-Keys {
    if (-not (Test-AutoHotkey)) { Install-Winget @('AutoHotkey.AutoHotkey') }
    $startup = if ($env:APPDATA) { $env:APPDATA } else { Expand-Path '~/AppData/Roaming' }
    $ahk = Join-Path $startup 'Microsoft\Windows\Start Menu\Programs\Startup\cain.ahk'
    Write-Text $ahk ((New-AhkScript).Replace("`n", "`r`n"))
    if (-not $script:Dry) {
        # (re)start it now; #SingleInstance replaces the old copy
        try { Invoke-Item $ahk } catch { Warn "couldn't start $ahk. Is AutoHotkey v2 installed?" }
    }
}

function Install-Desktop {
    $rel = Get-Str $script:Settings 'wallpaper'
    if ($rel) {
        $src = Join-Path $script:Root ($rel -replace '/', '\')
        if (-not (Test-Path $src)) { Warn "wallpaper $src not found" }
        else {
            $dest = Expand-Path ('~/.config/cain/wallpaper' + [IO.Path]::GetExtension($src))
            Copy-CainFile $src $dest
            if ($script:Dry) { Say "  [dry-run] set the wallpaper to $dest" }
            else {
                Send-SettingChange
                [void][Cain.Native]::SystemParametersInfo(20, 0, $dest, 3)   # SPI_SETDESKWALLPAPER, save + broadcast
                Say "  set the wallpaper to $dest"
            }
        }
    }
    $dark = Get-Prop $script:Settings 'dark_mode'
    if ($dark -and $dark.Value -eq $true) {
        if ($script:Dry) { Say '  [dry-run] set AppsUseLightTheme/SystemUsesLightTheme = 0'; return }
        $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
        Set-ItemProperty -Path $k -Name AppsUseLightTheme -Value 0 -Type DWord
        Set-ItemProperty -Path $k -Name SystemUsesLightTheme -Value 0 -Type DWord
        Say '  dark mode on'
    }
}

function Get-PresetSteps([string]$name) {
    switch ($name) {
        'full' { return $Steps }
        'light' { return @('git', 'files', 'bin', 'shell', 'keys') }
        'dotfiles' { return @('git', 'files', 'bin', 'shell') }
        'keybindings' { return @('keys') }
    }
    return $null
}

function Install-Cain([string[]]$list) {
    Say 'INSTALLING on windows'
    $visual = $false
    foreach ($s in $list) {
        Step $s
        switch ($s) {
            'packages' { Install-Packages }
            'git' { Install-Git }
            'files' { Install-Files }
            'bin' { Install-Bin }
            'shell' { Install-Shell }
            'keys' { Install-Keys; $visual = $true }
            'desktop' { Install-Desktop; $visual = $true }
        }
    }
    Save-Repo   # even a keys-only install counts as "cain is set up here"
    Say ''
    Say 'Done. Log out and back in (or reboot) so every change takes effect.'
    if ($visual -and (Ask 'Reboot now?' $false)) { Invoke-Cain 'shutdown' @('/r', '/t', '0') | Out-Null }
}

# ------------------------------------------------------------------ collect

function Invoke-Collect {
    $changed = @()
    Say "Files Changed:`n"
    foreach ($f in (Get-CainFiles)) {
        $repo = Join-Path $script:Root ($f.src -replace '/', '\'); $sys = Expand-Path $f.dest
        if (-not (Test-Path $sys)) { Say "    MISSING: $($f.dest)" }
        elseif (Test-SameFile $sys $repo) { Say "    SAME: $($f.dest)" }
        else { Copy-CainFile $sys $repo; $changed += $f.dest; Say "    CHANGED: $($f.dest)" }
    }
    if (-not $changed) { Say "`nALL FILES ARE THE SAME`n"; return }
    Invoke-Cain 'git' @('-C', $script:Root, 'add', '-A') | Out-Null
    if ((Invoke-Cain 'git' @('-C', $script:Root, 'commit', '-m', ('CHANGED: ' + ($changed -join ' ')))) -eq 0) {
        Invoke-Cain 'git' @('-C', $script:Root, 'push') | Out-Null
    }
}

# ------------------------------------------------------------------ menu

# Arrow keys (or j/k), Enter to pick, Space to tick, q/Esc to quit. Returns the chosen
# index or -1. With $checked (a bool array) it's a checklist.
function Show-Menu([string]$title, [string[][]]$items, $checked = $null) {
    if ([Console]::IsInputRedirected) { return -1 }
    $multi = $null -ne $checked
    $hint = if ($multi) { 'up/down move   space tick   a all/none   enter go   q quit' } else { 'up/down move   enter pick   q quit' }
    $width = ($items | ForEach-Object { $_[0].Length } | Measure-Object -Maximum).Maximum
    $cur = 0; $top = -1
    try { [Console]::CursorVisible = $false } catch { }
    Say ''
    try {
        while ($true) {
            if ($top -ge 0) { [Console]::SetCursorPosition(0, $top) }
            $cols = [Math]::Max(20, [Console]::WindowWidth - 1)
            $lines = @(@($title, 'White'), @($hint, 'DarkGray'), @('', 'Gray'))
            for ($i = 0; $i -lt $items.Count; $i++) {
                $box = if (-not $multi) { '' } elseif ($checked[$i]) { '[x] ' } else { '[ ] ' }
                $mark = if ($i -eq $cur) { ' > ' } else { '   ' }
                $color = if ($i -eq $cur) { 'Cyan' } else { 'Gray' }
                $lines += , @(($mark + $box + $items[$i][0].PadRight($width) + '  ' + $items[$i][1]), $color)
            }
            foreach ($l in $lines) {
                $text = $l[0]; if ($text.Length -gt $cols) { $text = $text.Substring(0, $cols) }
                Write-Host $text.PadRight($cols) -ForegroundColor $l[1]
            }
            if ($top -lt 0) { $top = [Console]::CursorTop - $lines.Count }
            $k = [Console]::ReadKey($true)
            switch -Regex ($k.Key.ToString()) {
                '^(UpArrow)$' { $cur = ($cur + $items.Count - 1) % $items.Count; continue }
                '^(DownArrow)$' { $cur = ($cur + 1) % $items.Count; continue }
                '^Home$' { $cur = 0; continue }
                '^End$' { $cur = $items.Count - 1; continue }
                '^Enter$' { return $cur }
                '^Escape$' { return -1 }
            }
            switch -CaseSensitive ([string]$k.KeyChar) {
                { $_ -in 'k', 'K', 'w' } { $cur = ($cur + $items.Count - 1) % $items.Count }
                { $_ -in 'j', 'J', 's' } { $cur = ($cur + 1) % $items.Count }
                { $_ -in ' ', 'x' } { if ($multi) { $checked[$cur] = -not $checked[$cur] } }
                { $_ -in 'a', 'A' } { if ($multi) { $all = -not ($checked -contains $false); for ($i = 0; $i -lt $checked.Count; $i++) { $checked[$i] = -not $all } } }
                { $_ -in 'q', 'Q' } { return -1 }
                { $_ -match '^[1-9]$' } { if ([int]$_ -le $items.Count) { $cur = [int]$_ - 1 } }
            }
        }
    } finally {
        try { [Console]::CursorVisible = $true } catch { }
        Say ''
    }
}

# The install menu: returns the steps, or $null if the user backed out.
function Select-Install {
    $choice = Show-Menu 'What should cain install?' @(
        @('Full', 'programs, dotfiles, keybindings and desktop settings'),
        @('Light', 'dotfiles and keybindings; no programs, no desktop changes'),
        @('Dotfiles', 'just configs, shell aliases and git settings'),
        @('Keybindings', 'just key remaps and shortcuts'),
        @('Custom', 'tick each part yourself'))
    if ($choice -lt 0) { return $null }
    if ($choice -lt 4) { return Get-PresetSteps (@('full', 'light', 'dotfiles', 'keybindings')[$choice]) }
    $checked = [bool[]]@($true) * $Steps.Count
    $pick = Show-Menu 'Pick what to install' @(
        @('packages', 'programs from cain.json'),
        @('git', 'your git name and email'),
        @('files', 'dotfiles: micro, nano, shell aliases...'),
        @('bin', 'put the cain command on your PATH'),
        @('shell', "load the aliases from your PowerShell profile"),
        @('keys', 'key remaps and keyboard shortcuts'),
        @('desktop', 'wallpaper, dark mode')) $checked
    if ($pick -lt 0) { return $null }
    $list = @(for ($i = 0; $i -lt $Steps.Count; $i++) { if ($checked[$i]) { $Steps[$i] } })
    if (-not $list) { return $null }
    return $list
}

# ------------------------------------------------------------------ tools

function Invoke-Booklister {
    $dir = if ($env:CAIN_BOOKS_DIR) { $env:CAIN_BOOKS_DIR } else { Expand-Path '~/Desktop/books' }
    if (-not (Test-Path $dir -PathType Container)) { Die "no books folder at $dir (set CAIN_BOOKS_DIR to change it)" }
    $books = @{}   # the same file name twice: the last one wins
    Get-ChildItem -Path $dir -Recurse -File | ForEach-Object { $books[$_.Name] = $_.FullName }
    if (-not $books.Count) { Die "no books in $dir" }
    $names = @($books.Keys | Sort-Object)

    # a small search-as-you-type window
    Add-Type -AssemblyName System.Windows.Forms
    $form = New-Object Windows.Forms.Form
    $form.Text = 'Books'; $form.Width = 560; $form.Height = 520; $form.TopMost = $true; $form.KeyPreview = $true
    $form.StartPosition = 'CenterScreen'
    $search = New-Object Windows.Forms.TextBox
    $search.Dock = 'Top'
    $list = New-Object Windows.Forms.ListBox
    $list.Dock = 'Fill'; $list.IntegralHeight = $false
    $form.Controls.Add($list); $form.Controls.Add($search)
    $script:BookChoice = $null
    $refill = {
        $words = @($search.Text.ToLower() -split ' ' | Where-Object { $_ })
        $list.BeginUpdate(); $list.Items.Clear()
        foreach ($n in $names) {
            $l = $n.ToLower(); $ok = $true
            foreach ($w in $words) { if (-not $l.Contains($w)) { $ok = $false; break } }
            if ($ok) { [void]$list.Items.Add($n) }
        }
        if ($list.Items.Count) { $list.SelectedIndex = 0 }
        $list.EndUpdate()
    }
    $choose = { if ($list.SelectedItem) { $script:BookChoice = [string]$list.SelectedItem }; $form.Close() }
    $search.Add_TextChanged($refill)
    $list.Add_DoubleClick($choose)
    $form.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq 'Down' -and $list.SelectedIndex + 1 -lt $list.Items.Count) { $list.SelectedIndex++; $e.Handled = $true }
        elseif ($e.KeyCode -eq 'Up' -and $list.SelectedIndex -gt 0) { $list.SelectedIndex--; $e.Handled = $true }
        elseif ($e.KeyCode -eq 'Enter') { & $choose; $e.SuppressKeyPress = $true }
        elseif ($e.KeyCode -eq 'Escape') { $form.Close() }
    })
    $form.Add_Shown({ $search.Focus() })
    & $refill
    [void]$form.ShowDialog()
    if ($script:BookChoice) { Invoke-Item $books[$script:BookChoice] }
}

function Invoke-Listlauncher {
    $site = if ($env:CAIN_SITE_DIR) { $env:CAIN_SITE_DIR } else { Expand-Path '~/Desktop/rhettapplestone.com' }
    if (-not (Test-Path $site)) { Die "can't open $site (set CAIN_SITE_DIR to change it)" }
    Set-Location $site
    $editor = if ($env:EDITOR) { $env:EDITOR } else { 'micro' }
    & $editor list.html   # not through Invoke-Cain: the editor needs the console to itself
    Invoke-Cain 'git' @('add', '.') | Out-Null
    Invoke-Cain 'git' @('commit', '-m', 'qcom') | Out-Null
    Invoke-Cain 'git' @('push') | Out-Null
}

# ------------------------------------------------------------------ main

# $CAIN_DIR, then the repo this script is in (it's files\cain\cain.ps1), then the repo
# `cain install` remembered, then here.
function Find-Root {
    if ($env:CAIN_DIR -and (Test-Path (Join-Path $env:CAIN_DIR 'files\cain.json'))) { return (Resolve-Path $env:CAIN_DIR).Path }
    $repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    if (Test-Path (Join-Path $repo 'files\cain.json')) { return $repo }
    $marker = Expand-Path '~/.config/cain/repo'
    if (Test-Path $marker) {
        $saved = (Get-Content $marker -TotalCount 1)
        if ($saved -and (Test-Path (Join-Path $saved 'files\cain.json'))) { return $saved }
    }
    if (Test-Path 'files\cain.json') { return (Get-Location).Path }
    return $null
}

$command = $null; $rest = @(); $yes = $false
foreach ($a in $args) {
    switch -CaseSensitive ([string]$a) {
        { $_ -in '-n', '--dry-run' } { $script:Dry = $true; continue }
        { $_ -in '-c', '--collect' } { $command = 'collect'; continue }
        { $_ -in '-i', '--install' } { $command = 'install'; continue }
        { $_ -in '-y', '--yes', '--all' } { $yes = $true; continue }
        { $_ -in '-h', '--help', 'help' } { [Console]::Out.Write($Usage); exit 0 }
        { $_.StartsWith('-') } { [Console]::Error.Write("cain: unknown option $_`n`n$Usage"); exit 2 }
        default { if (-not $command) { $command = $_ } else { $rest += $_ } }
    }
}

if ($command -eq 'booklister') { Invoke-Booklister; exit 0 }
if ($command -eq 'listlauncher') { Invoke-Listlauncher; exit 0 }

$script:Root = Find-Root
if (-not $script:Root) { Die "can't find the cain repo (the folder with files\cain.json). Run cain from inside it, or set CAIN_DIR." }

if ($command -eq 'generate') {
    $os = if ($rest) { $rest[0] } else { 'windows' }
    if ($os -ne 'windows') { Die "generate ${os}: run the cain shell script (on Linux, macOS or in Git Bash) for that" }
    Read-Manifest
    [Console]::Out.Write((New-AhkScript) + "`n")
    exit 0
}

[Console]::Out.WriteLine($Ascii.Replace("`r`n", "`n"))
if (-not $command -and -not (Test-Path (Expand-Path '~/.config/cain/repo'))) {
    Say "cain isn't set up on this PC yet, so let's install it."
    $command = 'install'
}
if (-not $command -and -not [Console]::IsInputRedirected) {
    $choice = Show-Menu 'What do you want to do?' @(
        @('Install', 'put my programs, configs and keybindings on this PC'),
        @('Collect', "copy this PC's configs into the repo, commit and push"))
    if ($choice -lt 0) { exit 0 }
    $command = @('install', 'collect')[$choice]
}
while (-not $command) {
    [Console]::Out.Write('Would you like to Collect (C) or Install (I)?: ')
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { exit 1 }
    if ($line -match '^[cC]') { $command = 'collect' }
    elseif ($line -match '^[iI]') { $command = 'install' }
    else { Say "`nNon valid input, please try again`n" }
}

Read-Manifest   # a broken cain.json stops here, before anything changes

switch ($command) {
    { $_ -in 'collect', 'c' } { Invoke-Collect; break }
    { $_ -in 'install', 'i', 'keys' } {
        $list = @()
        foreach ($a in $rest) {   # preset names expand to their steps
            $p = Get-PresetSteps $a
            if ($a -eq 'server') { Die 'the server install is for Linux' }
            foreach ($s in $(if ($p) { $p } else { @($a) })) { if ($list -notcontains $s) { $list += $s } }
        }
        if (-not $list -and $command -ne 'keys' -and -not $yes -and -not [Console]::IsInputRedirected) {
            $list = Select-Install
            if (-not $list) { Say 'Nothing installed.'; exit 0 }
        }
        if (-not $list -and $command -eq 'keys') { $list = @('keys') }
        if (-not $list) { $list = $Steps }
        foreach ($s in $list) {
            if ($Steps -notcontains $s) { Die ("unknown install step `"$s`"; choose from: " + ($Steps -join ' ')) }
        }
        Install-Cain $list
        break
    }
    'vps' { Die 'cain vps is for Linux servers' }
    default { [Console]::Error.Write("cain: unknown command `"$command`"`n`n$Usage"); exit 2 }
}
