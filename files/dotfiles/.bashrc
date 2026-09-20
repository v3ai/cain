# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto -i'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -la -h'


# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi


stty -ixon

#Rhett's Aliases
alias i="sudo apt install"
alias clone="git clone"
alias pull="git pull"
alias install="sudo apt install -y"
alias uninstall="sudo apt purge -y"
alias u="sudo apt purge -y"
alias autoremove="sudo apt autoremove -y"
alias update="sudo apt update -y"
alias upgrade="sudo apt upgrade -y"
alias des="cd ~/Desktop"
alias dow="cd ~/Downloads"
alias doc="cd ~/Documents"
alias bin="cd /usr/local/bin"
alias rhett="cd ~/Desktop/rhettapplestone.com"
alias m="micro"
alias p="python3"
alias books="cd ~/Desktop/books"
alias rc="micro ~/.bashrc +163:1 && source ~/.bashrc"
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
alias playlist="yt-dlp -x --audio-format mp3 -o \"%(playlist_index)s - %(title)s.%(ext)s\""
alias o="open"
alias mod="micro ~/Desktop/auction-stuff/modellist.txt"
alias conv="python3 ~/Desktop/auction-stuff/convert.py"
alias auc="cd ~/Desktop/auction-stuff"
alias list="cd && micro list"
alias autosearcher="python3 ~/Desktop/auction-stuff/autosearcher.py"
alias maxbid="python3 ~/Desktop/auction-stuff/maxbid.py"
alias llm="open https://claude.ai/ && open https://chatgpt.com/ && open https://gemini.google.com/ && open https://www.perplexity.ai/"
alias vnv="python3 -m venv venv"
alias src="source ./venv/bin/activate"
alias vps="ssh rhett@192.3.60.227"
alias viv="/home/rhett/Desktop/2025.2/Vivado/bin/vivado"


blackboard(){
	open	https://ualearn.blackboard.com/ultra/courses/_406718_1/outline
	open	https://ualearn.blackboard.com/ultra/courses/_409363_1/outline
	open	https://ualearn.blackboard.com/ultra/courses/_409345_1/outline
	open	https://ualearn.blackboard.com/ultra/courses/_405624_1/outline
	open	https://ualearn.blackboard.com/ultra/courses/_410357_1/outline
}

auction(){

links=(

	#miata all
	"https://www.copart.com/vehicle-search-make/mazda?displayStr=Mazda&from=%2FvehicleFinder&searchOrigin=vehicleFinderLink&qId=e0b36303-f769-4e9a-bd1b-b90208d64922-1789586131687&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22MAKE%22:%5B%22lot_make_desc:%5C%22MAZDA%5C%22%22%5D,%22MODL%22:%5B%22lot_model_desc:%5C%22MX-5%20MIATA%5C%22%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D"
	"https://www.iaai.com/Search?url=HGF513wR2S2g%2fG%2bW8MzGhPF5p7Ug91wUZvLUkGQ%2fbbg%3d"
	#s2000
	"https://www.copart.com/vehicle-search-make/honda?displayStr=Honda&from=%2FvehicleFinder&searchOrigin=vehicleFinderLink&qId=e0b36303-f769-4e9a-bd1b-b90208d64922-1789587785421&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22MAKE%22:%5B%22lot_make_desc:%5C%22HONDA%5C%22%22%5D,%22MODL%22:%5B%22lot_model_desc:%5C%22S2000%5C%22%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D"
	"https://www.iaai.com/Search?url=h16%2bFxcDnZrj2joVpCAfX5QxqiP7ePRARenh%2fJUTTiE%3d"
	#240sx
	"https://www.copart.com/vehicle-search-make/nissan?displayStr=Nissan&from=%2FvehicleFinder&searchOrigin=vehicleFinderLink&qId=e0b36303-f769-4e9a-bd1b-b90208d64922-1789588076463&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22MAKE%22:%5B%22lot_make_desc:%5C%22NISSAN%5C%22%22%5D,%22MODL%22:%5B%22lot_model_desc:%5C%22240SX%5C%22%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D"
	"https://www.iaai.com/Search?url=pXw30QvZGZgPL9ts4mdpNf5Z6ZwiqWPFK0zGd10E6gI%3d"
	#cars older than 1990
	"https://www.copart.com/lotSearchResults?free=false&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22ODM%22:%5B%22odometer_reading_received:%5B0%20TO%209999999%5D%22%5D,%22YEAR%22:%5B%22lot_year:%5B1920%20TO%201990%5D%22%5D,%22MISC%22:%5B%22%23VehicleTypeCode:VEHTYPE_V%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false%7D%20&displayStr=AUTOMOBILE,%5B0%20TO%209999999%5D,%5B1920%20TO%201990%5D&from=%2FvehicleFinder&fromSource=widget&searchOrigin=vehicleFinder&qId=e0b36303-f769-4e9a-bd1b-b90208d64922-1789588286026"
	"https://www.iaai.com/Search?url=DdmuJzVO0ck5J%2bfo2NpoAzzNM2OHFlziy1XXOuApYSk%3d"
	#frs brz gr86 (be careful)
	"https://www.copart.com/vehicle-search-make/scion?displayStr=Scion&from=%2FvehicleFinder&qId=c50f6fac-f50b-4b51-b2f5-85d03c9f4449-1788306551696&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22MAKE%22:%5B%22lot_make_desc:%5C%22SCION%5C%22%22%5D,%22MODL%22:%5B%22lot_model_desc:%5C%22FR-S%5C%22%22,%22lot_model_desc:%5C%22FRS%5C%22%22%5D,%22TITL%22:%5B%22title_group_code:TITLEGROUP_C%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D"
	"https://www.copart.com/vehicle-search-make/subaru?displayStr=Subaru&from=%2FvehicleFinder&qId=c50f6fac-f50b-4b51-b2f5-85d03c9f4449-1788306546318&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22MAKE%22:%5B%22lot_make_desc:%5C%22SUBARU%5C%22%22%5D,%22MODL%22:%5B%22lot_model_desc:%5C%22BRZ%5C%22%22,%22lot_model_desc:%5C%22BRZ%20LIMITED%5C%22%22,%22lot_model_desc:%5C%22BRZ%20LIMITED%20AUTOMATI%5C%22%22,%22lot_model_desc:%5C%22BRZ%20TS%5C%22%22%5D,%22TITL%22:%5B%22title_group_code:TITLEGROUP_C%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D"
	##"https://www.copart.com/vehicle-search-make/toyota?displayStr=Toyota&from=%2FvehicleFinder&qId=c50f6fac-f50b-4b51-b2f5-85d03c9f4449-1788306614816&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22MAKE%22:%5B%22lot_make_desc:%5C%22TOYOTA%5C%22%22%5D,%22MODL%22:%5B%22lot_model_desc:%5C%22GR%2086%5C%22%22,%22lot_model_desc:%5C%22GR86%5C%22%22%5D,%22TITL%22:%5B%22title_group_code:TITLEGROUP_C%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D"

	"https://www.iaai.com/Search?url=BKg5WUaNYXDF9tFcHCtOQHILqEquwVHHQEd%2bX8p6Nig%3d"
	"https://www.iaai.com/Search?url=bFnpbxymmeCkHqDTIEhYNKSMYlf2z6i0cdA%2b3O0wKIQ%3d"
	"https://www.iaai.com/Search?url=gnAi9gprwGBo2eJbkFRHi%2fkVAYnAumG7lVal7cOXA68%3d"

	## skyline
	"https://www.copart.com/vehicle-search-make/nissan?displayStr=Nissan&from=%2FvehicleFinder&searchOrigin=vehicleFinderLink&qId=e0b36303-f769-4e9a-bd1b-b90208d64922-1789599517226&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22MAKE%22:%5B%22lot_make_desc:%5C%22NISSAN%5C%22%22%5D,%22MODL%22:%5B%22lot_model_desc:%5C%22SKYLINE%5C%22%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D"
	"https://www.iaai.com/Search?url=uykH33LKt%2bAApuVjZylos3VYwqPw%2bHtyvqMCnFb2pS4%3d"
#	
	## manual bmw?
	## supra
	## pontiac gto, ls1 camaro
	"https://www.copart.com/vehicle-search-make/pontiac?displayStr=Pontiac&from=%2FvehicleFinder&searchOrigin=vehicleFinderLink&qId=e0b36303-f769-4e9a-bd1b-b90208d64922-1789599632393&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22MAKE%22:%5B%22lot_make_desc:%5C%22PONTIAC%5C%22%22%5D,%22MODL%22:%5B%22lot_model_desc:%5C%22GTO%5C%22%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D"
	"https://www.iaai.com/Search?url=xKVHX0nLFQFGnaboWeu3E9d%2f3cf2kqBrLrNspwp0nYg%3d"
	##c5 corvettes
	"https://www.copart.com/vehicle-search-make/chevrolet?displayStr=Chevrolet&from=%2FvehicleFinder&searchOrigin=vehicleFinderLink&qId=e0b36303-f769-4e9a-bd1b-b90208d64922-1789601516740&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22MAKE%22:%5B%22lot_make_desc:%5C%22CHEVROLET%5C%22%22%5D,%22MODL%22:%5B%22lot_model_desc:%5C%22CORVETTE%5C%22%22%5D,%22TITL%22:%5B%22title_group_code:TITLEGROUP_C%22%5D,%22YEAR%22:%5B%22lot_year:%5B1997%20TO%202004%5D%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D"
	"https://www.iaai.com/Search?url=d4Kd44eFoJ8AeTrx0%2fjJrTYDRYpgVd3x3%2bD0OEP15uY%3d"
	##open peakautoaucitons
	"https://peakautoauctionsal.com/"
	"https://peakautoauctionsms.com/"
	"https://peakautoauctionstn.com/"
	"https://peakautoauctionsga.com/"
	"https://peakautoauctionsfl.com/"
	
#
	##govdeals near I
	"https://www.govdeals.com/en/transportation/filters?zipcode=35405&miles=100&so=asc&sf=auctionclose"
#
	##vans
	"https://www.copart.com/lotSearchResults?free=true&query=&qId=e0b36303-f769-4e9a-bd1b-b90208d64922-1789607698771&index=undefined&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22BODY%22:%5B%22body_style:%5C%22CARGO%20VAN%5C%22%22,%22body_style:%5C%22EXTENDED%20SPORT%20VAN%5C%22%22,%22body_style:%5C%22SPORTS%20VAN%5C%22%22,%22body_style:%5C%22VAN%20CARGO%5C%22%22,%22body_style:%5C%22VAN%20PASSENGER%5C%22%22,%22body_style:%5C%22MINI-VAN%5C%22%22%5D,%22MISC%22:%5B%22%23LocRange:%7B%5C%22latitude%5C%22:33.110098,%5C%22longitude%5C%22:-87.552052,%5C%22miles%5C%22:%5C%22100%5C%22,%5C%22zip%5C%22:%5C%2235405%5C%22%7D%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D"
	
	
	
	
)


for element in "${links[@]}"
do
    open "$element"
    read i
    #not needex currently, read i waits    
    #sleep 0.5
done

#for copart & iaai
#all miatas all years
#s2000
#240sx, 180sx, s13, s14, s15, silvia
#cars older than 1980 (maybe 1990 bill of sale)
#frs brz gr86 (be careful)
# 350z g35?
# skyline
# manual bmw?
# supra
# pontiac gto, ls1 camaro
#open peakautoaucitons



#copart


#na miatas
#open	'https://www.copart.com/vehicle-search-make/mazda?displayStr=Mazda&from=%2FvehicleFinder&qId=c50f6fac-f50b-4b51-b2f5-85d03c9f4449-1787951011498&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22MAKE%22:%5B%22lot_make_desc:%5C%22MAZDA%5C%22%22%5D,%22TITL%22:%5B%22title_group_code:TITLEGROUP_C%22%5D,%22MODL%22:%5B%22lot_model_desc:%5C%22MX-5%20MIATA%5C%22%22%5D,%22YEAR%22:%5B%22lot_year:%5B1989%20TO%201997%5D%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false%7D'
#sleep 0.5
##240sx
#open	'https://www.copart.com/lotSearchResults?free=true&query=240sx&qId=c50f6fac-f50b-4b51-b2f5-85d03c9f4449-1787951258663&index=undefined&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false%7D'
#sleep 0.5
##cars older than 1980
#open	'https://www.copart.com/lotSearchResults?free=false&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22ODM%22:%5B%22odometer_reading_received:%5B0%20TO%209999999%5D%22%5D,%22YEAR%22:%5B%22lot_year:%5B1920%20TO%201980%5D%22%5D,%22MISC%22:%5B%22%23VehicleTypeCode:VEHTYPE_V%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false%7D&displayStr=AUTOMOBILE,%5B0%20TO%209999999%5D,%5B1920%20TO%201980%5D&from=%2FvehicleFinder&fromSource=widget&qId=c50f6fac-f50b-4b51-b2f5-85d03c9f4449-1788043790293'
#sleep 0.5
##motorcycles
#open	'https://www.copart.com/vehicle-search-type/motorcycles?displayStr=Motorcycles&from=%2FvehicleFinder&qId=c50f6fac-f50b-4b51-b2f5-85d03c9f4449-1788043728972&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22VEHT%22:%5B%22vehicle_type_code:VEHTYPE_C%22%5D,%22TITL%22:%5B%22title_group_code:TITLEGROUP_C%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false%7D'
#sleep 0.5
#
#open	'https://www.copart.com/vehicle-search-make/scion?displayStr=Scion&from=%2FvehicleFinder&qId=c50f6fac-f50b-4b51-b2f5-85d03c9f4449-1788306551696&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22MAKE%22:%5B%22lot_make_desc:%5C%22SCION%5C%22%22%5D,%22MODL%22:%5B%22lot_model_desc:%5C%22FR-S%5C%22%22,%22lot_model_desc:%5C%22FRS%5C%22%22%5D,%22TITL%22:%5B%22title_group_code:TITLEGROUP_C%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D'
#sleep 0.5
#open	'https://www.copart.com/vehicle-search-make/subaru?displayStr=Subaru&from=%2FvehicleFinder&qId=c50f6fac-f50b-4b51-b2f5-85d03c9f4449-1788306546318&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22MAKE%22:%5B%22lot_make_desc:%5C%22SUBARU%5C%22%22%5D,%22MODL%22:%5B%22lot_model_desc:%5C%22BRZ%5C%22%22,%22lot_model_desc:%5C%22BRZ%20LIMITED%5C%22%22,%22lot_model_desc:%5C%22BRZ%20LIMITED%20AUTOMATI%5C%22%22,%22lot_model_desc:%5C%22BRZ%20TS%5C%22%22%5D,%22TITL%22:%5B%22title_group_code:TITLEGROUP_C%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D'
#sleep 0.5
#open	'https://www.copart.com/vehicle-search-make/toyota?displayStr=Toyota&from=%2FvehicleFinder&qId=c50f6fac-f50b-4b51-b2f5-85d03c9f4449-1788306614816&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22MAKE%22:%5B%22lot_make_desc:%5C%22TOYOTA%5C%22%22%5D,%22MODL%22:%5B%22lot_model_desc:%5C%22GR%2086%5C%22%22,%22lot_model_desc:%5C%22GR86%5C%22%22%5D,%22TITL%22:%5B%22title_group_code:TITLEGROUP_C%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D'
#sleep 0.5
#
#
##iaai
#
##na miatas
#open	'https://www.iaai.com/Search?url=983O8apx3A4RYh4KTOnUZd%2bJdhaiqgN2fLtvAsFeRm0%3d'
#sleep 0.5
##240sx
#open	'https://www.iaai.com/Search?url=pXw30QvZGZgPL9ts4mdpNf5Z6ZwiqWPFK0zGd10E6gI%3d'
#sleep 0.5
##cars older than 1980
#open	'https://www.iaai.com/Search?url=kg9wWvV2qM%2fk%2fLbOcF4bZq84fmAPadf27nuCleiQ9T0%3d'
#sleep 0.5
##motorcycles
#open	'https://www.iaai.com/Vehiclelisting/Motorcycles'
#sleep 0.5
#
#open	'https://www.iaai.com/Search?url=BKg5WUaNYXDF9tFcHCtOQHILqEquwVHHQEd%2bX8p6Nig%3d'
#sleep 0.5
#open	'https://www.iaai.com/Search?url=bFnpbxymmeCkHqDTIEhYNKSMYlf2z6i0cdA%2b3O0wKIQ%3d'
#sleep 0.5
#gr86	'https://www.iaai.com/Search?url=gnAi9gprwGBo2eJbkFRHi%2fkVAYnAumG7lVal7cOXA68%3d'
#sleep 0.5
#
##manual clean title
#open 'https://www.copart.com/lotSearchResults?free=true&query=&qId=e0b36303-f769-4e9a-bd1b-b90208d64922-1788907079119&index=undefined&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22TMTP%22:%5B%22transmission_type:%5C%22MANUAL%5C%22%22%5D,%22TITL%22:%5B%22title_group_code:TITLEGROUP_C%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D'
#sleep 0.5
#
#
#
#
##autotempest section
#
##na miata
#open 'https://www.autotempest.com/results?zip=35401&make_model=mazda_mx5miata&minyear=1988&maxyear=1997&localization=country'
#sleep 0.5
#
##240sx
#open 'https://www.autotempest.com/results?zip=35401&make_model=nissan_240sx*nissan_180sx*nissan_200sx*nissan_silvia&localization=country'
#sleep 0.5
#
#autotempest for nd miata, frs, brz, maybe copart and iia for nd miata
#look at ecoboost /gt mustang
#skyline
# wrx
#manual trans cars
#s2000
# cars that are close to me (maybe 75 miles)
#open 'https://www.copart.com/lotSearchResults?free=false&displayStr=AUTOMOBILE,%5B0%20TO%209999999%5D,%5B1920%20TO%202027%5D,35405&from=%2FvehicleFinder&fromSource=widget&qId=c50f6fac-f50b-4b51-b2f5-85d03c9f4449-1788652241951&searchCriteria=%7B%22query%22:%5B%22*%22%5D,%22filter%22:%7B%22ODM%22:%5B%22odometer_reading_received:%5B0%20TO%209999999%5D%22%5D,%22YEAR%22:%5B%22lot_year:%5B1920%20TO%202027%5D%22%5D,%22VEHT%22:%5B%22vehicle_type_code:VEHTYPE_V%22%5D,%22MISC%22:%5B%22%23LocRange:%7B%5C%22latitude%5C%22:33.110098,%5C%22longitude%5C%22:-87.552052,%5C%22miles%5C%22:%5C%22100%5C%22,%5C%22zip%5C%22:%5C%2235405%5C%22%7D%22%5D,%22TITL%22:%5B%22title_group_code:TITLEGROUP_C%22%5D%7D,%22searchName%22:%22%22,%22watchListOnly%22:false,%22freeFormSearch%22:false,%22exclusions%22:%5B%5D%7D'
#put nd miata and mk5 supra

#gto
#copart lists some bill of sales as salvage title

}





export EDITOR='micro'

ip(){
	#made by ai
	hostname -I | cut -d' ' -f1
}

scan(){
	IPVAR=$(ip)
	if [ $# -eq 0 ]; then
  		sudo nmap "$IPVAR"/24  
	else
		sudo nmap "$IPVAR"/24 -p"$1"  
	fi
}

#godsend very important
bind 'set completion-ignore-case on'

#list(){
#	cwd=$(pwd)
#	cd ~/Desktop/rhettapplestone.com
#	micro list.html
#	qcom
#	cd $cwd
#}

# simple website generator
web(){
	touch index.html
	touch style.css
	
	echo "<!DOCTYPE HTML>" >> index.html
	echo "<html>" >> index.html
	echo "    <head>" >> index.html
	echo "    <title>Website</title>" >> index.html
	echo "    <link rel=\"stylesheet\" href=\"style.css\">" >> index.html
	echo "    </head>" >> index.html
	echo "    <body>" >> index.html
	echo "		<h1>hi</h1>" >> index.html
	echo "    </body>" >> index.html
	echo "</html>" >> index.html
	

	echo "body {" >> style.css
	echo "    max-width: 40em;" >> style.css
	echo "    margin: 0 auto;" >> style.css
	echo "    font-family: \"Courier New\", monospace;" >> style.css
	echo "    text-align: center;" >> style.css
	echo "}" >> style.css
}

finde(){
	find . -iname "*$1*"
}

# book was written by ai

book(){

	declare -A files
	IFS=$'\n' read -d '' -r -a arr < <(find /home/rhett/Desktop/books -type f)
	
	for i in "${arr[@]}"; do
	    base=$(basename "$i")
	    files["$base"]="$i"
	done
	
	choice=$(printf "%s\n" "${!files[@]}" | dmenu -i -l 25)
	
	if [ -n "$choice" ]; then
	    xdg-open "${files["$choice"]}"
	fi
	
}

cain(){
	cd ~/cain || return
	./cain $@
	cd || return
}

qcom(){
	if [ ! -d ".git" ]; then
		git init
	else
	    git add .
		git commit -m "qcom"
		git push	
	fi
}

com(){
	if [ ! -d ".git" ]; then
		git init
	else
	    git add .
		git commit -m "qcom"
	fi
}



# >>> Open Interpreter installer >>>
export PATH="/home/rhett/.local/bin:$PATH"
# <<< Open Interpreter installer <<<
