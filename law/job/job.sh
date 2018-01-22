#!/usr/bin/env bash

# generic law job script

# render variables:
# - bootstrap_file: file that is sourced before running tasks

# arguments:
# 1. task_module
# 2. task_family
# 3. task_params
# 4. start_branch
# 5. end_branch
# 6. auto_retry

action() {
    local cwd="$( /bin/pwd )"


    #
    # store arguments
    #

    local task_module="$1"
    local task_family="$2"
    local task_params="$( echo "$3" | tr _ = | base64 --decode )"
    local start_branch="$4"
    local end_branch="$5"
    local auto_retry="$6"


    #
    # create a new base and tmp dirs that will be deleted at the end of the job
    #

    local job_hash="$( python -c "import uuid; print(str(uuid.uuid4())[-12:])" )"
    local base="$cwd/base_${job_hash}"
    local base_tmp="$base/tmp"

    mkdir -p "$base_tmp"

    export HOME="$base"
    export TMP="$base_tmp"
    export TEMP="$base_tmp"
    export TMPDIR="$base_tmp"


    #
    # helper functions
    #

    section() {
        echo
        echo "--------------------------------------------------------------------------------"
        echo
    }

    cleanup() {
        section

        echo "pre cleanup"
        echo "ls -hal $base:"
        ls -hal $base
        rm -rf "$base"

        section

        echo "post cleanup"
        echo "ls -hal $cwd:"
        ls -hal $cwd
    }


    #
    # some logs
    #

    section

    echo "starting $0"
    echo "shell: '$SHELL'"
    echo "args : '$@'"
    echo "pwd  : '$cwd'"
    echo "home : '$HOME'"
    echo "base : '$base'"
    echo "tmp  : '$( python -c "from tempfile import gettempdir; print(gettempdir())" )'"
    echo "ls -hal:"
    ls -hal

    section

    echo "task module : $task_module"
    echo "task family : $task_family"
    echo "task params : $task_params"
    echo "start branch: $start_branch"
    echo "end branch  : $end_branch"
    echo "auto retry  : $auto_retry"


    #
    # custom bootstrap file
    #

    run_bootstrap_file() {
        local bootstrap_file="{{bootstrap_file}}"
        if [ ! -z "$bootstrap_file" ]; then
            echo "run bootstrap file: $bootstrap_file"
            source "$bootstrap_file"
        else
            echo "bootstrap file empty, skip"
        fi
    }

    section

    run_bootstrap_file
    local ret="$?"

    section

    if [ "$ret" != "0" ]; then
        2>&1 echo "bootstrap file failed, abort"
        cleanup
        return "$ret"
    fi


    #
    # run the law task commands
    #

    echo "run tasks from branch $start_branch to $end_branch"
    for (( branch=$start_branch; branch<$end_branch; branch++ )); do
        section

        local cmd="law run $task_module.$task_family --branch $branch $task_params"
        echo "branch: $branch"
        echo "cmd   : $cmd"

        section

        echo "dependecy tree:"
        eval "$cmd --print-deps 2"
        ret="$?"
        if [ "$?" != "0" ]; then
            2>&1 echo "dependency tree for branch $branch failed, abort"
            cleanup
            return "$ret"
        fi

        section

        echo "execute attempt 1:"
        eval "$cmd"
        ret="$?"
        echo "return code: $ret"

        if [ "$ret" != "0" ] && [ "%auto_retry" = "yes" ]; then
            section

            echo "execute attempt 2:"
            eval "$cmd"
            ret="$?"
            echo "return code: $ret"
        fi

        if [ "$ret" != "0" ]; then
            2>&1 echo "branch $branch failed, abort"
            cleanup
            return "$ret"
        fi
    done


    #
    # le fin
    #

    cleanup
    return "0"
}

action "$@"
