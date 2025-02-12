#!/usr/bin/env -S just --justfile

# FIXME group commands

log_decorator1 := `which spacer 2>&1 > /dev/null && echo "spacer --right --force-color |"`
log_decorator2 := `which wl 2>&1 > /dev/null && echo wl || echo cat`
log_decorator := log_decorator1 + log_decorator2
export just_recurse_log := env('just_recurse_log', '')

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

    need_to_run={{ force }}

    if [ -n "$need_to_run" ]
    then
        log "RUN because you asked"
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
        set -x  # FIXME
        [ -n "${newer_file}" ] &&
            if [ "${timestamp}" -ot ".git/HEAD" ]
            then
                log "RUN due to switching the branch to: $(cat .git/HEAD)"
                need_to_run=3
            elif [ "${timestamp}" -ot "$(awk '{print $2}' < .git/HEAD)" ]
            then
                log "RUN due to a new HEAD in the branch: $(cat .git/HEAD)"
                need_to_run=4
            else
                log "RUN due to modified file: ${newer_file}"
                need_to_run=5
            fi
        set +x  # FIXME
    fi

    if [ -z "$need_to_run" ]
    then
        [ "${timestamp}" -ot "${reported_by_callee_timestamp}" ] && {
            log "RUN because $(cat ${reported_by_callee_timestamp}) is built" \
                "at $(command stat -c %y ${reported_by_callee_timestamp})"
            need_to_run=6
        }
    fi

    [ -n "${need_to_run}" ] || {
        # Caller might need to run even when I don't, if I already ran before.
        [ "${timestamp}" -nt "${caller_first_timestamp}" ] &&
            echo "$my_name" >! "${reporting_to_caller_timestamp}"

        log "NOT_RUN due to no change"
        exit 0
    }

    echo "Recurse log: $just_recurse_log"
    recipe_log_path="$(readlink -f build)/log-{{ recipe }}-$(date +%F-%H-%M-%S)-$my_name.txt"
    log "Logs: $recipe_log_path"

    log_path="$recipe_log_path" just _find_package_recipe_and_run "{{ recipe }}" . || {
        my_exit_code=$?
        log "RUN FAILED"
        echo "Recurse log: $just_recurse_log"
        exit $my_exit_code
    }

    [ -d "$(basename "${reporting_to_caller_timestamp}")" ] &&
        echo "$my_name" >! "${reporting_to_caller_timestamp}"
    touch "${timestamp}"
    echo "Recurse log: $just_recurse_log"

export default_command := env('default_command', '')

[no-cd]
[no-exit-message]
_find_package_recipe_and_run recipe dir:
    #!/usr/bin/env zsh
    set -eo pipefail
    cd "{{ dir }}"

    old_ld_library_path=${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH}
    dependent_libs=($(readlink -f ../*/build/lib || true))
    export LD_LIBRARY_PATH=$(IFS=: ; echo "${dependent_libs[*]}")${old_ld_library_path}

    package_name=$(basename $(pwd))
    package_specific_recipe={{ recipe }}_${package_name}
    all_recipes=( $(just --summary) )

    if (($all_recipes[(Ie)$package_specific_recipe]))   # if all_recipes includes $package_specific_recipe
    then
        # specify working-directory to avoid adding [no-cd] on all package specific recipes
        just run "
            echo Recurse log: $just_recurse_log
            just --justfile={{ justfile() }} --working-directory=$(pwd) --color always $package_specific_recipe
        "
        # TODO show recurse log at the end of the recipe log without losing exit status
    else
        if [ -n "{{ default_command }}" ]
        then
            just --justfile={{ justfile() }} --working-directory=$(pwd) --color always run "
                echo Recurse log: $just_recurse_log
                {{ default_command }}
            "
        fi
    fi

[no-cd]
init dir="." force="true": mwinit
    #!/usr/bin/env zsh
    set -eo pipefail
    ln -sf $(cd "{{ dir }}" && brazil-path package-build-root) "{{ dir }}/"
    export just_recurse_log="${just_recurse_log:-$(readlink -f "{{ dir }}")/build/log-recurse-$(date +%F-%H-%M).txt}"
    set -x

    just recurse "{{ dir }}"

    just _run_package_recipe init "{{ dir }}" "{{ force }}"

[no-cd]
init_only dir="." force="true":
    #!/usr/bin/env zsh
    set -eo pipefail
    ln -sf $(cd "{{ dir }}" && brazil-path package-build-root) "{{ dir }}/"
    export just_recurse_log="${just_recurse_log:-$(readlink -f "{{ dir }}")/build/log-recurse-$(date +%F-%H-%M).txt}"

    just _run_package_recipe init "{{ dir }}" "{{ force }}"

[no-cd]
pre_build dir="." force="true":
    #!/usr/bin/env zsh
    set -eo pipefail
    ln -sf $(cd "{{ dir }}" && brazil-path package-build-root) "{{ dir }}/"
    export just_recurse_log="${just_recurse_log:-$(readlink -f "{{ dir }}")/build/log-recurse-$(date +%F-%H-%M).txt}"
    set -x

    just _find_package_recipe_and_run pre_build "{{ dir }}" || true

[no-cd]
pre_build_only dir="." force="true":
    #!/usr/bin/env zsh
    set -eo pipefail
    ln -sf $(cd "{{ dir }}" && brazil-path package-build-root) "{{ dir }}/"
    export just_recurse_log="${just_recurse_log:-$(readlink -f "{{ dir }}")/build/log-recurse-$(date +%F-%H-%M).txt}"

    just _find_package_recipe_and_run pre_build "{{ dir }}" || true

[no-cd]
build dir="." force="true": mwinit
    #!/usr/bin/env zsh
    set -eo pipefail
    ln -sf $(cd "{{ dir }}" && brazil-path package-build-root) "{{ dir }}/"
    export just_recurse_log="${just_recurse_log:-$(readlink -f "{{ dir }}")/build/log-recurse-$(date +%F-%H-%M).txt}"
    set -x

    just recurse "{{ dir }}"

    just _run_package_recipe init "{{ dir }}" ""
    just _find_package_recipe_and_run pre_build "{{ dir }}" || true
    just \
        default_command="echo 'Error: Need to define build_"$(readlink -f $(basename {{ dir }}))" recipe.'; exit 1" \
        _run_package_recipe build "{{ dir }}" "{{ force }}" init

[no-cd]
build_only dir="." force="true":
    #!/usr/bin/env zsh
    set -eo pipefail
    ln -sf $(cd "{{ dir }}" && brazil-path package-build-root) "{{ dir }}/"
    export just_recurse_log="${just_recurse_log:-$(readlink -f "{{ dir }}")/build/log-recurse-$(date +%F-%H-%M).txt}"

    just \
        default_command="echo 'Error: Need to define build_"$(readlink -f $(basename {{ dir }}))" recipe.'; exit 1" \
        _run_package_recipe build "{{ dir }}" "{{ force }}" init

[no-cd]
release dir="." force="true": mwinit
    #!/usr/bin/env zsh
    set -eo pipefail
    ln -sf $(cd "{{ dir }}" && brazil-path package-build-root) "{{ dir }}/"
    export just_recurse_log="${just_recurse_log:-$(readlink -f "{{ dir }}")/build/log-recurse-$(date +%F-%H-%M).txt}"
    set -x

    just recurse "{{ dir }}"

    just _run_package_recipe init "{{ dir }}" ""
    just _find_package_recipe_and_run pre_build "{{ dir }}" || true
    just \
        default_command="echo 'Error: Need to define build_"$(readlink -f $(basename {{ dir }}))" recipe.'; exit 1" \
        _run_package_recipe build "{{ dir }}" "" init
    just _run_package_recipe release "{{ dir }}" "{{ force }}" build

[no-cd]
release_only dir="." force="true":
    #!/usr/bin/env zsh
    set -eo pipefail
    ln -sf $(cd "{{ dir }}" && brazil-path package-build-root) "{{ dir }}/"
    export just_recurse_log="${just_recurse_log:-$(readlink -f "{{ dir }}")/build/log-recurse-$(date +%F-%H-%M).txt}"

    just _run_package_recipe release "{{ dir }}" "{{ force }}" build

[no-cd]
fresh:
    rm -f ../*/build/timestamp-*

[no-cd]
clean dir=".":
    rm -rf {{ dir }}/build/* {{ dir }}/node_modules

[no-cd]
clean_all:
    rm -rf ../*/build/* ../*/node_modules

[no-cd]
clean_everything: clean_all
    rm -rf ../../env/
    brazil-package-cache stop
    rm -rf $(brazil-package-cache cache_root)
    brazil-package-cache start

[no-cd]
[no-exit-message]
run +commands:
    #!/bin/bash
    # zsh fails with >&

    if [ -z "${log_path}" ]
    then
        name="${name:-{{ commands }}}"
        name=${name##*$'\n'}
        name=${name// /-}
        name=${name//\//-}
        log_file="log-${name}-$(date +%F-%H-%M-%S).txt"
        log_path=$([ -d build ] && echo "build" || echo "/tmp")/$log_file
    fi

    if [ -z "${log_decorator_invoked}" ]
    then
        export log_decorator_invoked=1
        exec 1>&2>&>({{ log_decorator }})
    fi

    # https://stackoverflow.com/questions/8720508/bash-tee-remove-color#comment10868816_8721194
    # sed expression modified as https://stackoverflow.com/a/18000433
    exec 4<&1 5<&2 1>&2>&>( tee >(sed -r 's/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g' > $log_path ))

    time ${SHELL} -ic "set -x; {{ commands }}"
    exit_code=$?

    exec 1<&4 4>&- 2<&5 5>&-

    [ -d build ] && mv -f $log_path build/ 2> /dev/null || true
    exit $exit_code

[no-cd]
b *subcommands:
    @name=bb just run "just pre_build && (set -x; brazil-build {{ subcommands }} )"

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
            cut -d $'\t' -f 5 --only-delimited |
            sort -n |
            head -1)
    [ "0$expiration" -gt $(date +%s) ] && mwinit_command=

    exec ${SHELL} -ic "set -x; { $mwinit_command } && { {{ command }} }"   # brace it in case it's empty

[no-cd]
mwinitf *command:
    rm -rf ~/.ada ~/.aws ~/.midway ~/.config/ada
    just mwinit {{ command }}

work_branch := ""

new-ws dir main_package *more_packages: mwinit
    #!/usr/bin/env zsh
    set -xeo pipefail
    (
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
