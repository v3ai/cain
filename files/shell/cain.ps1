# Rhett's PowerShell setup (Windows), dot-sourced from $PROFILE by cain.
# Same commands as cain.sh on Linux/macOS. Edit with `rc`.

$CainConfig = "$HOME\.config\cain"
$env:EDITOR = "micro"

# PowerShell ships aliases with some of these names; ours win.
foreach ($a in "sl", "del", "c", "p", "t", "o", "l", "m", "n", "i", "u", "a") {
    Remove-Item "Alias:$a" -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- packages (winget)
function i          { winget install @args }
function install    { winget install --accept-package-agreements --accept-source-agreements @args }
function uninstall  { winget uninstall @args }
function u          { winget uninstall @args }
function update     { winget source update }
function upgrade    { winget upgrade --all --accept-package-agreements --accept-source-agreements }
function autoremove { Write-Host "winget has no autoremove" }

# ---------------------------------------------------------------- navigation / shortcuts
function clone      { git clone @args }
function pull       { git pull @args }
function des        { Set-Location "$HOME\Desktop" }
function dow        { Set-Location "$HOME\Downloads" }
function doc        { Set-Location "$HOME\Documents" }
function bin        { Set-Location "$HOME\.local\bin" }
function rhett      { Set-Location "$HOME\Desktop\rhettapplestone.com" }
function books      { Set-Location "$HOME\Desktop\books" }
function auc        { Set-Location "$HOME\Desktop\auction-stuff" }
function ..         { Set-Location .. }
function m          { micro @args }
function p          { python @args }
function rc         { micro "$CainConfig\cain.ps1"; . "$CainConfig\cain.ps1" }
function nrc        { micro "$HOME\.nanorc" }
function sl         { Get-ChildItem @args }
function l          { Get-ChildItem @args }
function ll         { Get-ChildItem -Force @args }
function c          { Clear-Host }
function t          { tree.com /F @args }
function delete     { Remove-Item -Recurse -Force @args }
function del        { Remove-Item -Recurse -Force @args }
function n          { nnn -d -e -H -r @args }
function getmp3     { yt-dlp -x --audio-format mp3 @args }
function playlist   { yt-dlp -x --audio-format mp3 -o "%(playlist_index)s - %(title)s.%(ext)s" @args }
function o          { foreach ($x in $args) { Start-Process $x } }
function open       { foreach ($x in $args) { Start-Process $x } }
function mod        { micro "$HOME\Desktop\auction-stuff\modellist.txt" }
function conv       { python "$HOME\Desktop\auction-stuff\convert.py" @args }
function list       { Set-Location $HOME; micro list }
function autosearcher { python "$HOME\Desktop\auction-stuff\autosearcher.py" @args }
function maxbid     { python "$HOME\Desktop\auction-stuff\maxbid.py" @args }
function llm        { open https://claude.ai/ https://chatgpt.com/ https://gemini.google.com/ https://www.perplexity.ai/ }
function vnv        { python -m venv venv }
function src        { . .\venv\Scripts\Activate.ps1 }
function vps        { ssh rhett@192.3.60.227 }
function book       { booklister }
function cain       { python "$env:CAIN_DIR\cain.py" @args }

# ---------------------------------------------------------------- functions
function blackboard {
    Get-Content "$CainConfig\blackboard.txt" | Where-Object { $_.Trim() } | ForEach-Object { Start-Process $_ }
}

function a {
    foreach ($url in Get-Content "$CainConfig\auctions.txt" | Where-Object { $_.Trim() }) {
        Start-Process $url
        Read-Host | Out-Null
    }
}

function ip {
    (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
        Select-Object -First 1).IPAddress
}

function scan {
    $net = "$(ip)/24"
    if ($args.Count -eq 0) { nmap $net } else { nmap $net "-p$($args[0])" }
}

function web {
    Add-Content index.html @'
<!DOCTYPE HTML>
<html>
    <head>
    <title>Website</title>
    <link rel="stylesheet" href="style.css">
    </head>
    <body>
		<h1>hi</h1>
    </body>
</html>
'@
    Add-Content style.css @'
body {
    max-width: 40em;
    margin: 0 auto;
    font-family: "Courier New", monospace;
    text-align: center;
}
'@
}

function finde { Get-ChildItem -Recurse -Filter "*$($args[0])*" | ForEach-Object { $_.FullName } }

function qcom {
    if (-not (Test-Path .git)) { git init }
    else { git add .; git commit -m "qcom"; git push }
}

function com {
    if (-not (Test-Path .git)) { git init }
    else { git add .; git commit -m "qcom" }
}
