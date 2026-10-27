# Rhett's shell setup, sourced from ~/.bashrc / ~/.zshrc by cain.
# Works in bash and zsh on Linux and macOS. Edit with `rc`.

CAIN_CONFIG="$HOME/.config/cain"

# ---------------------------------------------------------------- platform bits
case "$(uname -s)" in
    Darwin) _cain_os=macos ;;
    *)      _cain_os=linux ;;
esac

if [ "$_cain_os" = linux ] && ! command -v open >/dev/null 2>&1; then
    open() { for f in "$@"; do xdg-open "$f" >/dev/null 2>&1 & done; }
fi

# install / uninstall / update ... for whichever package manager exists
if   command -v brew    >/dev/null 2>&1; then _pm_install="brew install";              _pm_remove="brew uninstall";             _pm_update="brew update";          _pm_upgrade="brew upgrade";                 _pm_autoremove="brew autoremove"
elif command -v apt-get >/dev/null 2>&1; then _pm_install="sudo apt install -y";       _pm_remove="sudo apt purge -y";          _pm_update="sudo apt update -y";   _pm_upgrade="sudo apt upgrade -y";          _pm_autoremove="sudo apt autoremove -y"
elif command -v dnf     >/dev/null 2>&1; then _pm_install="sudo dnf install -y";       _pm_remove="sudo dnf remove -y";         _pm_update="sudo dnf check-update"; _pm_upgrade="sudo dnf upgrade -y";         _pm_autoremove="sudo dnf autoremove -y"
elif command -v pacman  >/dev/null 2>&1; then _pm_install="sudo pacman -S --needed";   _pm_remove="sudo pacman -Rns";           _pm_update="sudo pacman -Sy";      _pm_upgrade="sudo pacman -Syu";             _pm_autoremove='sudo pacman -Rns $(pacman -Qdtq)'
elif command -v zypper  >/dev/null 2>&1; then _pm_install="sudo zypper install -y";    _pm_remove="sudo zypper remove -y";      _pm_update="sudo zypper refresh";  _pm_upgrade="sudo zypper update -y";        _pm_autoremove="sudo zypper remove --clean-deps"
fi

i()          { eval "$_pm_install \"\$@\""; }
install()    { eval "$_pm_install \"\$@\""; }
uninstall()  { eval "$_pm_remove \"\$@\""; }
u()          { eval "$_pm_remove \"\$@\""; }
update()     { eval "$_pm_update"; }
upgrade()    { eval "$_pm_upgrade"; }
autoremove() { eval "$_pm_autoremove"; }

# ---------------------------------------------------------------- shell options
[ -t 0 ] && stty -ixon
if [ -n "$BASH_VERSION" ]; then
    bind 'set completion-ignore-case on'
elif [ -n "$ZSH_VERSION" ]; then
    zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
fi

export EDITOR='micro'

# ---------------------------------------------------------------- aliases
alias grep='grep --color=auto -i'
alias ll='ls -la -h'
alias clone="git clone"
alias pull="git pull"
alias des="cd ~/Desktop"
alias dow="cd ~/Downloads"
alias doc="cd ~/Documents"
alias bin="cd /usr/local/bin"
alias rhett="cd ~/Desktop/rhettapplestone.com"
alias m="micro"
alias p="python3"
alias books="cd ~/Desktop/books"
alias rc='micro "$CAIN_CONFIG/cain.sh" && . "$CAIN_CONFIG/cain.sh"'
alias nrc="micro ~/.nanorc"
alias sl="ls"
alias l="ls"
alias c="clear"
alias t="tree"
alias delete="rm -rf"
alias del="rm -rf"
alias ..="cd .."
alias n='nnn -d -e -H -r'
alias getmp3='yt-dlp -x --audio-format mp3'
alias playlist='yt-dlp -x --audio-format mp3 -o "%(playlist_index)s - %(title)s.%(ext)s"'
alias o="open"
alias mod="micro ~/Desktop/auction-stuff/modellist.txt"
alias conv="python3 ~/Desktop/auction-stuff/convert.py"
alias auc="cd ~/Desktop/auction-stuff"
alias list="cd && micro list"
alias autosearcher="python3 ~/Desktop/auction-stuff/autosearcher.py"
alias maxbid="python3 ~/Desktop/auction-stuff/maxbid.py"
alias llm="open https://claude.ai/ https://chatgpt.com/ https://gemini.google.com/ https://www.perplexity.ai/"
alias vnv="python3 -m venv venv"
alias src="source ./venv/bin/activate"
alias vps="ssh rhett@192.3.60.227"
alias viv="$HOME/Desktop/2025.2/Vivado/bin/vivado"
alias book="cain booklister"
alias booklister="cain booklister"
alias listlauncher="cain listlauncher"

# ---------------------------------------------------------------- functions
# open every URL in a list file at once
blackboard() { grep -v '^\s*$' "$CAIN_CONFIG/blackboard.txt" | while read -r url; do open "$url"; done; }

# open auction searches one at a time, Enter for the next
a() {
    grep -v '^\s*$' "$CAIN_CONFIG/auctions.txt" > "${TMPDIR:-/tmp}/cain-a.$$"
    while read -r url <&3; do
        open "$url"
        read -r _
    done 3< "${TMPDIR:-/tmp}/cain-a.$$"
    rm -f "${TMPDIR:-/tmp}/cain-a.$$"
}

ip() {
    if [ "$_cain_os" = macos ]; then
        ipconfig getifaddr en0 || ipconfig getifaddr en1
    else
        hostname -I | cut -d' ' -f1
    fi
}

scan() {
    IPVAR=$(ip)
    if [ $# -eq 0 ]; then
        sudo nmap "$IPVAR"/24
    else
        sudo nmap "$IPVAR"/24 -p"$1"
    fi
}

web() {
    cat >> index.html <<'HTML'
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
HTML
    cat >> style.css <<'CSS'
body {
    max-width: 40em;
    margin: 0 auto;
    font-family: "Courier New", monospace;
    text-align: center;
}
CSS
}

finde() { find . -iname "*$1*"; }

qcom() {
    if [ ! -d ".git" ]; then
        git init
    else
        git add .
        git commit -m "qcom"
        git push
    fi
}

com() {
    if [ ! -d ".git" ]; then
        git init
    else
        git add .
        git commit -m "qcom"
    fi
}
