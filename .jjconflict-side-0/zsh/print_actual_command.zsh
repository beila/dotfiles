# print the actual command whenever a command starts, if it's different from the typed command
function print_actual_command (){
    [ "$1" = "$3" ] || echo "$PS4[1,1] $3"
}
#add-zsh-hook -Uz preexec print_actual_command
