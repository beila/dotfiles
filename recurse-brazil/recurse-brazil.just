#!/usr/bin/env -S just --justfile
# FIXME group commands

log_decorator1 := ''
#log_decorator1 := `which spacer 2>&1 > /dev/null && echo "spacer --right --force-color |" || echo ""`

# https://gitlab.com/kevincox/watchlog/-/tree/v1

log_decorator2 := `which wl 2>&1 > /dev/null && echo wl || echo cat`
log_decorator := log_decorator1 + log_decorator2
export just_recurse_log := env('just_recurse_log', '')

set shell := ['zsh', '-c']

logger := """
    log_with_name() {
        log_name=$1
        shift

        msg="$just_recurse_indent${log_name}: $*"
        echo "${msg}"
        [ -d $(dirname "$just_recurse_log") ] && echo "$(date "+%F %T") ${msg}" >> "$just_recurse_log"
    }
"""

[no-cd]
recurse dir=".":
    #!/usr/bin/env zsh
    set -eo pipefail
    {{ logger }}

    possible_dependencies=( $(IFS='=' awk '/=/ {print $1}' < "{{ dir }}/Config" | sort | uniq) )
    declare -a dependencies

    # /#/ replaces the empty string at the start with the following string
    for d in ${possible_dependencies[@]/#/{{ dir }}/../}
    do
        [ ! -d $d ] && continue
        [ $(readlink -f $d) = $(readlink -f {{ dir }}) ] && continue
        dependencies+="$d"
    done

    (( ${#dependencies[@]} == 0 )) ||
        log_with_name "$(basename $(readlink -f {{ dir }}))" "Descend into dependencies"

    for d in ${dependencies[@]}
    do
        caller_dir="$(readlink -f {{ dir }})" \
            just_recurse_indent="${just_recurse_indent}    " \
            just release $d ''
            #just recurse $d    # For testing recurse without actual build
    done

export caller_dir := env('caller_dir', 'NO_CALLER')

[no-cd]
[no-exit-message]
_run_package_recipe recipe dir force *previous_recipes:
    #!/usr/bin/env zsh
    {{ logger }}

    cd "{{ dir }}"
    log () { log_with_name "$(basename $(pwd)) {{ recipe }}" "$*"; }

    my_name=$(basename $(pwd))
    caller_name=$(basename "{{ caller_dir }}")

    timestamp="build/timestamp-{{ recipe }}-$my_name"
    previous_recipes=({{ previous_recipes }})
    previous_recipe_timestamps=("${previous_recipes[@]/#/build/timestamp-}")
    previous_recipe_timestamps=("${previous_recipe_timestamps[@]/%/-$my_name}")

    reporting_to_caller_timestamp="{{ caller_dir }}/build/timestamp-recurse-run-$caller_name"
    reported_by_callee_timestamp="build/timestamp-recurse-run-$my_name"
    caller_first_timestamp="{{ caller_dir }}/build/timestamp-init-$caller_name"

    [ "{{ force }}" = "--only-once" ] && only_once="true" || only_once=
    need_to_run=

    if [ "{{ force }}" = "--force" ]
    then
        log "RUN because you asked"
        need_to_run=1
    fi

    if [ -z "$need_to_run" ]
    then
        [ -f "${timestamp}" ] || {
            log "RUN for the first time"
            need_to_run=1
        }
    fi

    if [ -z "$need_to_run" ]
    then
        for previous_timestamp in "${previous_recipe_timestamps[@]}"
        do
            [ "${timestamp}" -nt "${previous_timestamp}" ] || {
                log "RUN due to newer ${previous_timestamp}"
                need_to_run=2
                break
            }
        done
    fi

    if [ -z "$need_to_run" ]
    then
        filter_ignored() { git check-ignore --stdin --non-matching --verbose | grep '^::' | sed 's/^:: *//' }
        newer_file="$(
            find . \
                    -type f \
                    -newer "${timestamp}" \
                    -not -path '*/.git/*' \
                    -not -path '*/__tests__/*' \
                    -not -path '*/__mocks__/*' \
                    -not -name 'package-lock.json' \
                    -not -name 'Cargo.lock' |
                filter_ignored |
                head -1
        )"
        [ -n "${newer_file}" ] &&
            if [ "${timestamp}" -ot ".git/HEAD" ]
            then
                log "RUN due to switching the branch to: $(cat .git/HEAD)"
                need_to_run=3
            elif [ "${timestamp}" -ot ".git/$(awk '{print $2}' < .git/HEAD)" ]
            then
                log "RUN due to a new HEAD in the branch: $(cat .git/HEAD)"
                need_to_run=4
            elif [ -n "$only_once" ]
            then
                reason_not_to_run="due to already run even though a file is modified"
                # do not set need_to_run
            else
                log "RUN due to modified file: ${newer_file}"
                need_to_run=5
            fi
    fi

    if [ -z "$need_to_run" ]
    then
        [ "${timestamp}" -ot "${reported_by_callee_timestamp}" ] && {
            if [ -n "$only_once" ]
            then
                reason_not_to_run="due to already run even though a depenency is built"
                # do not set need_to_run
            else
                log "RUN because $(cat ${reported_by_callee_timestamp}) is built" \
                    "at $(command stat -c %y ${reported_by_callee_timestamp})"
                need_to_run=6
            fi
        }
    fi

    if [ -z "$need_to_run" ]
    then
        # Caller might need to run even when I don't, if I already ran before in this recursion.
        [ "${timestamp}" -ot "${caller_first_timestamp}" ] || {
            [ -d "$(dirname "${reporting_to_caller_timestamp}")" ] &&
                echo "$my_name" >! "${reporting_to_caller_timestamp}"
        }

        log "NOT_RUN ${reason_not_to_run:-due to no change}"
        exit 0
    fi

    echo "Recurse log: $just_recurse_log"
    recipe_log_path="$(readlink -f build)/log-{{ recipe }}-$(date +%F-%H-%M-%S)-$my_name.txt"
    log "Log: $recipe_log_path"

    set -x  # FIXME recipe succeeded but fail?
    log_path="$recipe_log_path" just _find_package_recipe_and_run "{{ recipe }}" .
    my_exit_code=$?

    (( my_exit_code != 0 )) && log "RUN FAILED"
    echo "Recurse log: $just_recurse_log"
    echo "Recurse log: $just_recurse_log" >> "$recipe_log_path"

    (( my_exit_code != 0 )) && exit $my_exit_code

    touch "${timestamp}" || true
    [ -d "$(dirname "${reporting_to_caller_timestamp}")" ] &&
        echo "$my_name" >! "${reporting_to_caller_timestamp}" || true

export default_command := env('default_command', '')

[no-cd]
[no-exit-message]
_find_package_recipe_and_run recipe dir:
    #!/usr/bin/env zsh
    set -eo pipefail
    cd "{{ dir }}"

    package_name=$(basename $(pwd))
    package_specific_recipe={{ recipe }}_${package_name}
    all_recipes=( $(just --summary) )

    if (($all_recipes[(Ie)$package_specific_recipe]))   # if all_recipes includes $package_specific_recipe
    then
        # specify working-directory to avoid adding [no-cd] on all package specific recipes
        just run_with_brazil_env "
            echo Recurse log: $just_recurse_log
            just --justfile={{ justfile() }} --working-directory=$(pwd) --color always $package_specific_recipe
        "
    elif [ -n "{{ default_command }}" ]
    then
        just --justfile={{ justfile() }} --working-directory=$(pwd) --color always run_with_brazil_env "
            echo Recurse log: $just_recurse_log
            {{ default_command }}
        "
    else
        [ -n "$log_path" ] && echo "$package_specific_recipe is not defined." >> "$log_path"
    fi
    # TODO show recurse log at the end of the recipe log without losing exit status

run_preamble := """
    run_preamble() {
        set -eo pipefail
        [ ! -d "${1:?}/build" ] &&
            ln -sf $(cd "$1" && brazil-path package-build-root) "$1"
        export just_recurse_log="${just_recurse_log:-$(readlink -f "$1")/build/log-recurse-$(date +%F-%H-%M).txt}"
    }
    run_preamble\
"""

[no-cd]
init dir="." force="--force": mwinit
    #!/usr/bin/env zsh
    {{ run_preamble }}            "{{ dir }}"
    just recurse                  "{{ dir }}"
    just _run_package_recipe init "{{ dir }}" "{{ force }}"

[no-cd]
init_only dir="." force="--force":
    #!/usr/bin/env zsh
    {{ run_preamble }}            "{{ dir }}"
    just _run_package_recipe init "{{ dir }}" "{{ force }}"

[no-cd]
pre_build dir="." force="--force":
    #!/usr/bin/env zsh
    {{ run_preamble }}                          "{{ dir }}"
    just _find_package_recipe_and_run pre_build "{{ dir }}" || true

[no-cd]
pre_build_only dir="." force="--force":
    #!/usr/bin/env zsh
    {{ run_preamble }}                          "{{ dir }}"
    just _find_package_recipe_and_run pre_build "{{ dir }}" || true

just_run_package_recipe_build := """
    just_run_package_recipe_build() {
        just \
            default_command="echo 'Error: Need to define build_"$(basename $(readlink -f "$1"))" recipe.'; exit 1" \
            _run_package_recipe build "$@"
    }
    just_run_package_recipe_build\
"""

[no-cd]
build dir="." force="--force": mwinit
    #!/usr/bin/env zsh
    {{ run_preamble }}                          "{{ dir }}"
    just recurse                                "{{ dir }}"
    just _run_package_recipe init               "{{ dir }}" "--only-once"
    just _find_package_recipe_and_run pre_build "{{ dir }}" || true
    {{ just_run_package_recipe_build }}         "{{ dir }}" "{{ force }}" init

[no-cd]
build_only dir="." force="--force":
    #!/usr/bin/env zsh
    {{ run_preamble }}                   "{{ dir }}"
    {{ just_run_package_recipe_build }}  "{{ dir }}" "{{ force }}" init

[no-cd]
release dir="." force="--force": mwinit
    #!/usr/bin/env zsh
    {{ run_preamble }}                          "{{ dir }}"
    just recurse                                "{{ dir }}"
    just _run_package_recipe init               "{{ dir }}" "--only-once"
    just _find_package_recipe_and_run pre_build "{{ dir }}" || true
    {{ just_run_package_recipe_build }}         "{{ dir }}" ""            init
    just _run_package_recipe release            "{{ dir }}" "{{ force }}" build

[no-cd]
release_only dir="." force="--force":
    #!/usr/bin/env zsh
    {{ run_preamble }}               "{{ dir }}"
    just _run_package_recipe release "{{ dir }}" "{{ force }}" build

[no-cd]
fresh:
    rm -f ../*/build/timestamp-*

[no-cd]
clean dir=".":
    rm -rf {{ dir }}/build/* {{ dir }}/node_modules

[no-cd]
clean_all:
    #!/usr/bin/env zsh
    setopt -o nullglob
    set -x
    rm -rf ../*/build ../*/node_modules

[no-cd]
clean_everything: clean_all
    rm -rf ../../build/ ../../env/
    brazil-package-cache stop
    rm -rf $(brazil-package-cache cache_root)
    brazil-package-cache start

[no-cd]
[no-exit-message]
run_with_brazil_env +commands:
    #!/usr/bin/env zsh
    just run "
        export PATH=$(dirname $(which brazil-path)):$(brazil-path all.bin):$PATH
        export LD_LIBRARY_PATH=$(brazil-path all.lib)${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
        {{ commands }}
    "

[no-cd]
[no-exit-message]
run +commands:
    #!/bin/bash
    # zsh fails with >&

    if [ -z "${log_path}" ]
    then
        name="${name:-{{ commands }}}"
        name=${name#${log_prefix_ignore}}
        name=${name#just }
        name=${name// /-}
        name=${name//|/-}
        name=${name//&/-}
        name=${name//\//-}
        name=${name//\\/-}
        name=${name//\*/-}
        name=${name//\$/-}
        name=${name//\'/}
        name=${name//\"/}
        name=${name//$'\n'/-}
        name="${name:0:200}"    # file name limit https://serverfault.com/a/9548
        log_file="log-${name}-$(date +%F-%H-%M-%S).txt"
        log_path=$([ -d build ] && echo "build" || echo "/tmp")/$log_file
        echo "Log: $log_path"
    fi

    if [ -z "${log_decorator_invoked}" ]
    then
        export log_decorator_invoked=1
        exec 1>&2>&>({{ log_decorator }})
    fi

    # https://stackoverflow.com/questions/8720508/bash-tee-remove-color#comment10868816_8721194
    # sed expression modified as https://stackoverflow.com/a/18000433
    exec 4<&1 5<&2 1>&2>&>( tee >(sed -r 's/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g' > $log_path ))

    time zsh -ic "
        set -x
        {{ commands }}
    "
    exit_code=$?

    exec 1<&4 4>&- 2<&5 5>&-

    if [ $exit_code -ne 0 ]
    then
        failed_log_path=${log_path/%.txt/.FAILED.txt}
        mv $log_path $failed_log_path
        log_path=
    fi

    echo "Log: $log_path$failed_log_path"
    exit $exit_code

[no-cd]
b *subcommands:
    @name=bb just run_with_brazil_env "just pre_build && (set -x; brazil-build {{ subcommands }} )"

[no-cd]
ws *subcommands: mwinit
    brazil ws {{ subcommands }}

[no-cd]
sync: mwinit
    brazil ws sync

[no-cd]
syncmd: mwinit
    brazil ws sync --md

[no-cd]
mwinit *command:
    #!/usr/bin/env zsh
    mwinit_command="
        mwinit -o -s --fido2 ||
        {
            rm ~/.midway/cookie
            exit 1
        }
    "
    expiration=$(cat ~/.midway/cookie 2> /dev/null |
            cut -d $'\t' -f 5 -s |
            sort -n |
            head -1)
    [ "0$expiration" -gt $(date +%s) ] && mwinit_command=

    exec zsh -ic "set -x; { $mwinit_command } && { {{ command }} }"   # brace it in case it's empty

[no-cd]
mwinitf *command:
    rm -rf ~/.ada ~/.aws ~/.midway ~/.config/ada
    just mwinit {{ command }}

work_branch := ""

new-ws dir main_package *more_packages: mwinit
    #!/usr/bin/env zsh
    set -xeo pipefail
    (
        which brazil &> /dev/null || toolbox install brazilcli

        [ -d "{{ dir }}/src" ] && {
            for d in {{ dir }}/src/*
            do
                [ -n "$(git -C "$d" status --short)" ] && exit 1
            done
            set -x
            rm -rf "{{ dir }}"
        }

        more_packages=({{ more_packages }})

        just ws create --root "{{ dir }}" --package {{ main_package }} ${other_options}

        cd "{{ dir }}/src/{{ main_package }}"

        if (( ${#more_packages[@]} != 0 ))
        then
            just ws use ${more_packages[@]/#/--package }
        fi

        if [ -n "{{ work_branch }}" ]
        then
            for p in {{ main_package }} ${more_packages[@]}
            do
                git -C "{{ dir }}/src/$p" fetch --all || true
                git -C "{{ dir }}/src/$p" checkout {{ work_branch }} || true
            done
        fi

        echo "{{ dir }}/src/{{ main_package }}"
    ) | {{ log_decorator }}

[no-cd]
upload-diff-for-review *args: mwinit
    git diff --no-ext-diff {{ args }} | cr --arbitrary-diff - --arbitrary-diff-create-personal-pkg

[no-cd]
collect_rust_deps:
    #!/usr/bin/env python3
    import pathlib
    import tomllib

    source_dir = pathlib.Path('..')
    patches=({'name':p['name'], 'path':str(path.parent)}
        for path in source_dir.rglob('Cargo.toml')
        for file in [open(path, 'rb')]
        for toml in [tomllib.load(file)]
        if 'package' in toml
        for p in [toml['package']]
        if 'name' in p
        for _ in [file.close()]
    )

    with open("Cargo.toml", "r+") as f:
        main_file = f.read()
        toml = tomllib.loads(main_file)
        lines = main_file.split('\n')

        section_line = '[patch.crates-io]' 
        if toml.get('patch', {}).get('crates-io') is None:
            print('Adding: ' + section_line)
            lines.append(section_line)

        section_index = list(map(str.strip, lines)).index(section_line)
        for p in patches:
            if toml.get('patch', {}).get('crates-io', {}).get(p['name']): continue
            new_line = p['name'] + ' = { path = "' + p['path'] + '"}'
            print('Adding: ' + new_line)
            lines.insert(section_index+1, new_line)

        f.seek(0)
        f.write('\n'.join(lines))
        f.truncate()
