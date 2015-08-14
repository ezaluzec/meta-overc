#! /bin/bash

function lxc_log {
    local msg=${1}

    echo ${msg}
}

function match_cn_name {

    # If a container is not through lxc-stop
    # command then next time this container started
    # will have some suffix added the real container
    # name.  This helper function makes sure the container
    # names match.

    [ -z "${1}" -o -z "${2}" ] && return 0
    match1=`echo ${1} | grep "^${2}"`
    match2=`echo ${2} | grep "^${1}"`
    [ -n "${match1}" -o -n "${match2}" ] && return 1
    return 0
}

function get_cn_name_from_init_pid {
    local init_pid=${1}

    cn_name=`cat /proc/${init_pid}/cgroup | grep ":cpuset:" |\
            cut -d ":" -f 3 | xargs basename`
    echo "${cn_name}"
}

function get_lxc_mgr_pid_from_cn_name {
    local cn_name=${1}

    # lxc-start process is the main controller
    # of lxc container.  All lxc-xxxx commands must
    # inherit net namespace of this process.

    lxc_mgr_pid_list=`ps -e -o comm,pid | grep "^lxc-start" | awk '{print $2}'`
    for i in ${lxc_mgr_pid_list}; do
        lxc_cn_init_pid=`pgrep -P $i`
        this_cn_name=`get_cn_name_from_init_pid ${lxc_cn_init_pid}`

        match_cn_name ${this_cn_name} ${cn_name}
        if [ $? -eq 1 ]; then
            echo "${i}"
            return 0
        fi
    done
    echo ""
    return 1
}

function get_lxc_init_pid_from_cn_name {
    local cn_name=${1}

    lxc_init_pid=""

    # Each of lxc-start process has exactly
    # 1 child process which is the first process
    # (normally /sbin/init") of container

    lxc_mgr_pid=`get_lxc_mgr_pid_from_cn_name ${cn_name}`
    if [ -n "${lxc_mgr_pid}" ]; then
        lxc_init_pid=`pgrep -P ${lxc_mgr_pid}`
    fi
    echo ${lxc_init_pid}
}

function get_parent_cn_name_from_cn_name {
    local cn_name=${1}

    parent_cn_name=""
    lxc_init_pid=`get_lxc_init_pid_from_cn_name ${cn_name}`
    if [ -n "${lxc_init_pid}" ]; then
        parent_cn_name=`cat /proc/${lxc_init_pid}/cgroup | grep ":cpuset:" | \
                cut -d ":" -f 3 | sed 's:/lxc/:/:g' | xargs dirname | xargs basename`
    fi

    echo ${parent_cn_name}
}

function is_cn_exist {
    local cn_name=${1}

    cn_list=`lxc-ls`
    for i in ${cn_list}; do
        [ "${i}" == "${cn_name}" ] && return 1
    done
    return 0
}

function is_current_cn {
    local cn_name=${1}

    current_cn_name=`get_cn_name_from_init_pid 1`
    [ "${current_cn_name}" == "${cn_name}" ] && return 1
    return 0
}

function exec_cmd_container {
    local cn_name=${1}
    shift

    is_cn_exist ${cn_name}
    [ $? -eq 0 ] && lxc_log "Error, container ${cn_name} does not exist." && return 1

    is_current_cn ${cn_name}
    if [ $? -eq 1 ] ; then
        $@
    else
        lxc_init_pid=`get_lxc_init_pid_from_cn_name ${cn_name}`
        if [ -n "${lxc_init_pid}" ]; then
            nsenter -u -i -m -n -p -t ${lxc_init_pid} -- $@
        else
            lxc_log "Error, exec_lxc_cmd_cn, container ${cn_name} is not running or started from host."
            return 1
        fi
    fi
}

function exec_lxc_cmd_cn {
    local cn_name=${1}
    shift

    is_cn_exist ${cn_name}
    [ $? -eq 0 ] && lxc_log "Error, container ${cn_name} does not exist." && return 1

    is_current_cn ${cn_name}
    if [ $? -eq 1 ] ; then
        $@
    else
        lxc_mgr_pid=`get_lxc_mgr_pid_from_cn_name ${cn_name}`
        if [ -n "${lxc_mgr_pid}" ]; then
            nsenter --net --target ${lxc_mgr_pid} -- $@
        else
            lxc_log "Error, exec_lxc_cmd_cn, container ${cn_name} is not running or started from host."
            return 1
        fi
    fi
}

function get_lxc_cn_state_from_cn_name {
    local cn_name=${1}

    state=`exec_lxc_cmd_cn ${cn_name} lxc-info -n ${cn_name} \
            | grep "State:" | awk '{print $2}'`
    echo "${state}"
}

function is_cn_running {
    local cn_name=${1}

    state=`get_lxc_cn_state_from_cn_name ${cn_name}`
    if [ "${state}" == "RUNNING" ]; then
        return 1
    else
        return 0
   fi
}