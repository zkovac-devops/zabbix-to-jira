#!/bin/bash

# log_setup - setup the LOG_* values used by the rest of log_*() functions
#
# You can configure following options:
#
# LOG_CONF_FILE		- Path to configurtion file
#			- Can be provided as the first argument to this function, the file will be sourced
#			
#			default: LOG_CONF_FILE=
#
# LOG_TS_PREFIX		- Prefix for each log line even before the timestamp
#			
# 			default: LOG_TS_PREFIX=
#
# LOG_TIMESTAMP_FORMAT	- Log time stamp prefix
#			- Format is used for the date command (without the + sign)
#			
#			default: LOG_TIMESTAMP_FORMAT="%Y-%m-%dT%H:%M:%S%:z"
#
# LOG_PREFIX		- Prefix for each log line even right after the timestamp
#			
#			default: LOG_PREFIX=
#
# LOG_FILE		- Path to log file
#
#		  	default: LOG_FILE=
#
# LOG_OUTPUT		- Specify where to write the logs
#			- Can be one of "stdout", "file" or "tee" (tee means stdout and file)
#			
#			if LOG_FILE is empty "stdout" is forced
#
#		  	default: LOG_OUTPUT=stdout
#
# LOG_LEVEL_DEBUG	- "y"/"n", will activate the function log_debug()
#
#			default: LOG_LEVEL_DEBUG=
#
# LOG_LEVEL_INFO	- "y"/"n", will activate the function log_info()
#
#			default: LOG_LEVEL_INFO=${LOG_LEVEL_DEBUG}
#
# LOG_LEVEL_ERROR	- "y"/"n", will activate the function log_error()
#
#			default: LOG_LEVEL_ERROR=y
#
# LOG_PROTECT_WITH	- String that will replace the protected string when calling log_exec*() functions
#
#			default: "****"
 
function log_setup() {

	LOG_CONF_FILE=${LOG_CONF_FILE:-${1}}

	[ -n "${LOG_CONF_FILE}" -a -r "${LOG_CONF_FILE}" ] && source "${LOG_CONF_FILE}"
	[ -n "${LOG_CONF_FILE}" -a ! -r "${LOG_CONF_FILE}" ] && echo "log_setup() can not read log file LOG_CONF_FILE=${LOG_CONF_FILE}"

	[ -z "${LOG_TIMESTAMP_FORMAT}" ] && LOG_TIMESTAMP_FORMAT="%Y-%m-%dT%H:%M:%S%:z"

	[ -z "${LOG_FILE}" -a \( "${LOG_OUTPUT}" == "file" -o "${LOG_OUTPUT}" == "tee" \) ] && echo "log_setup() invalid setup: no log file defined yet output set to file, forcing stdout"
	[ -z "${LOG_FILE}" ] && LOG_OUTPUT=stdout
	[ -n "${LOG_FILE}" ] && mkdir -p `dirname ${LOG_FILE}`  # make sure the directory for log file exists

	# If info is not set, use setting from the debug level

	LOG_LEVEL_INFO=${LOG_LEVEL_INFO:-${LOG_LEVEL_DEBUG}}

	# Preferred to have error level always on

	LOG_LEVEL_ERROR=${LOG_LEVEL_ERROR:-y}

	# Since [ -n "${VAR}" ] is faster than [ "${VAR}" == "y" ] we translate the log levels to empty/non-empty internal vars

	[ "${LOG_LEVEL_DEBUG}" == "y" ] && LOG_INTERNAL_LEVEL_DEBUG=y || LOG_INTERNAL_LEVEL_DEBUG=
	[ "${LOG_LEVEL_INFO}" == "y" ] && LOG_INTERNAL_LEVEL_INFO=y || LOG_INTERNAL_LEVEL_INFO=
	[ "${LOG_LEVEL_ERROR}" == "y" ] && LOG_INTERNAL_LEVEL_ERROR=y || LOG_INTERNAL_LEVEL_ERROR=

	LOG_PROTECT_WITH="${LOG_PROTECT_WITH:-****}"

	return 0

}

function log_internal_out() {

	if [ "${LOG_OUTPUT:0:1}" == "f" ]
	then
		echo "${LOG_TS_PREFIX}${LOG_TS_PREFIX:+ }$(date +${LOG_TIMESTAMP_FORMAT})${LOG_PREFIX:+ }${LOG_PREFIX} $*" >> ${LOG_FILE}
	elif [ "${LOG_OUTPUT:0:1}" == "t" ]
	then
		echo "${LOG_TS_PREFIX}${LOG_TS_PREFIX:+ }$(date +${LOG_TIMESTAMP_FORMAT})${LOG_PREFIX:+ }${LOG_PREFIX} $*" | tee -a ${LOG_FILE}
	else
		echo "${LOG_TS_PREFIX}${LOG_TS_PREFIX:+ }$(date +${LOG_TIMESTAMP_FORMAT})${LOG_PREFIX:+ }${LOG_PREFIX} $*"
	fi

}

function log() {

	local RC=$?;
	if [ "${1}" == "-n" ]
	then
		shift
		log_internal_out "$*"
	else
		[ -p /dev/stdin ] && while read -s LINE
		do 
			[ $# -eq 0 ] && log_internal_out "${LINE}" || log_internal_out "$* ${LINE}"; done || log_internal_out "$*"
	fi
	return ${RC}

}

function log_debug() { local RC=$? P=; [ "${1}" == "-n" ] && { P=-n; shift; }; [ -n "${LOG_INTERNAL_LEVEL_DEBUG}" ] && [ $# -eq 0 ] && log "DEBUG" || { true; log $P "DEBUG $*";      }; return ${RC}; }
function log_info()  { local RC=$? P=; [ "${1}" == "-n" ] && { P=-n; shift; }; [ -n "${LOG_INTERNAL_LEVEL_INFO}"  ] && [ $# -eq 0 ] && log "INFO"  || { true; log $P "INFO $*";       }; return ${RC}; }
function log_error() { local RC=$? P=; [ "${1}" == "-n" ] && { P=-n; shift; }; [ -n "${LOG_INTERNAL_LEVEL_ERROR}" ] && [ $# -eq 0 ] && log "ERROR" || { true; log $P "ERROR $*" 1>&2; }; return ${RC}; }


# log_exec_add_protected - function to extend the array of protected strings with argument strings

function log_exec_add_protected() {
	
	local ARG=
	
	for ARG in "$@"
	do
		LOG_PROTECTED+=("${ARG}")
	done

}


# log_internal_hide_protected - function that searches the input for protected strings and replaces them

function log_internal_hide_protected() {

	local ARG="$@"
	
	for PROT in "${LOG_PROTECTED[@]}"
	do
		ARG="${ARG//${PROT}/${LOG_PROTECT_WITH}}"
	done
	
	echo "${ARG}"

}


# log_exec - function to log the input and execute the input capturing+logging its stdout/stderr
# Returns the return code of the executed input

function log_exec() {

	local PROT="$(log_internal_hide_protected "$@")"
	log_info "${FUNCNAME[0]}() ${PROT}"
	{ eval $@; } |& log_debug "${FUNCNAME[0]}()"; EXEC_RC=${PIPESTATUS[${#PIPESTATUS[@]}-2]}
	[ ${EXEC_RC} != 0 ] && log_error "${FUNCNAME[0]}() command '${PROT}' exited with rc: ${EXEC_RC}"; return ${EXEC_RC}

}


# log_exec_var - function to log the input and execute the input WITHOUT stdout/stderr capturing
# Returns the return code of the executed input
# Useful for logged executions like: 
# 	exec_var "eval V=\$(echo sss; false)"
# or
# 	exec_var "pushd /path/to/your/dir"

function log_exec_var() {

	local PROT="$(log_internal_hide_protected "$@")"
	log_info "${FUNCNAME[0]}() ${PROT}"
	$@; EXEC_RC=$?
	[ ${EXEC_RC} != 0 ] && log_error "${FUNCNAME[0]}() command '${PROT}' exited with rc: ${EXEC_RC}"; return ${EXEC_RC}

}
