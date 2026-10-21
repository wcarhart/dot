# system
alias cp='cp -i'
alias dirs='dirs -v'
alias la='ls -alG'
alias mkdir='mkdir -p'
alias mv='mv -i'
alias rm='rm -i'

# shortcuts
alias c='clear'
alias cppwd='echo -n "$(pwd)" | pbcopy'
alias l='ls'
alias hs='history | grep'
alias p='python3'
alias s='ls'
alias sb='source ~/.bashrc'
alias upls='up && ls'

# typos
alias eit='exit'
alias gi='git'
alias gti='git'
alias gits='git s'
alias ndoe='node'
alias pytho='python'
alias pythoon='python'
alias ptyhon='python'
alias tre='tree'

# fun
alias busy='cat /dev/urandom | hexdump -C | grep "ca fe"'
alias siren="printf '\033[5m\033[91m%b\033[0m' '\'{127,105,105,40,127,117,117} && echo"
# shellcheck disable=SC2154
alias spin='while :; do for s in / - \\ \|; do printf "\r$s"; sleep .1; done; done'
alias starwars='telnet towel.blinkenlights.nl'
