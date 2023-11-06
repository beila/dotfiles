# print the actual command whenever a command starts, if it's different from the typed command
add-zsh-hook -Uz preexec (){[ "$1" = "$3" ] || echo "$PS4[1,1] $3"}
