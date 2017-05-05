#!/bin/bash

# Functions to manage "pid file"
# Useful when script is executed on shceduled basis (i.e. cron), but need to check whether previous instance is still running

# You can configure following options:
#
# PID_FILE	- Path to pid file
#
#		default: PID_FILE=/var/run/$(basename $0).pid
#
# PID_USE_LOG	- Trigger to use the logging from log_*() functions

function pid_setup() {

	PID_FILE=${PID_FILE:-/var/run/$(basename ${0}).pid}
	PID_USE_LOG=${PID_USE_LOG:+y}

}

# pid_read - function to read pid file
# $1 - Variable to receive the value from pid file (if argument is missing, the pid is printed to stdout)
#
# Return values:
# 0 - succesfully read the pid file
# 1 - pid file not readable
# 2 - pid file does not exist

function pid_read() {

	if [ -r ${PID_FILE} ]
	then
		[ -n "${1}" ] && eval ${1}=$( <${PID_FILE} ) || cat ${PID_FILE}
		return 0
	fi

	if [ -e ${PID_FILE} ]
	then
		[ -n "${PID_USE_LOG}" ] && log_error "${FUNCNAME[0]}() pid file '${PID_FILE}' exists but is not readable"
		return 1
	fi
	return 2

}

# pid_store
# $1 - function to store PID into pid file (if argument is missing, the pid is read from $$ variable)
#
# Return values:
# 		0 - pid file already exists or successfuly created with our PID
# 		1 - pid file already exists with different PID and another PID process exists
# 		2 - pid file already exists with different PID, another PID process does not exist, but can't be removed
# 		3 - pid file already exists, but can't be read
# 		4 - pid file created, but another process just insterted its own PID into it
# 		5 - pid file created, but can't be read
# 		6 - pid file created by another process

function pid_store() {

	local PID=${1:-$$}	#local PID=${1:-${BASHPID}}
	local PID_FILE_PID=
	
	if [ -e ${PID_FILE} ]
	then
		if pid_read PID_FILE_PID
		then
			[ ${PID} -eq ${PID_FILE_PID} ] && return 0
	
			if ps -e | grep "^${PID_FILE_PID}" 2>&1 >/dev/null
			then
				[ -n "${PID_USE_LOG}" ] && log_error "${FUNCNAME[0]}() pid file '${PID_FILE}' contains different pid: ${PID_FILE_PID}"
				return 1
      			else
				[ -n "${PID_USE_LOG}" ] && log_info "${FUNCNAME[0]}() removing stale pid file '${PID_FILE}' with pid: ${PID_FILE_PID}"
				rm -f ${PID_FILE} || return 2
			fi
    		else
			[ -n "${PID_USE_LOG}" ] && log_error "${FUNCNAME[0]}() can not read pid file '${PID_FILE}' trying to remove ..."
			rm -f ${PID_FILE} || return 3
		fi
	fi

	if [ ! -e ${PID_FILE} ]
	then
		echo $PID 2>/dev/null >${PID_FILE}

		if pid_read PID_FILE_PID
		then
			[ ${PID} -eq ${PID_FILE_PID} ] && return 0
			[ -n "${PID_USE_LOG}" ] && log_error "${FUNCNAME[0]}() different process ${PID_FILE_PID} just created pid file '${PID_FILE}'"
			return 4
		else
			[ -n "${PID_USE_LOG}" ] && log_error "${FUNCNAME[0]}() created but can not read pid file '${PID_FILE}'"
			return 5
		fi
	else
		[ -n "${PID_USE_LOG}" ] && log_error "${FUNCNAME[0]}() different process ${PID_FILE_PID} just created pid file '${PID_FILE}'"
		return 6
	fi

}

function pid_cleanup() {

	rm -f ${PID_FILE} 2>&1 >/dev/null
	local RM_RC=$?
	[ ${RM_RC} -ne 0 -a -n "${PID_USE_LOG}" ] && log_error "${FUNCNAME[0]}() failed to remove pid file '${PID_FILE}'"
	return ${RM_RC}

}
