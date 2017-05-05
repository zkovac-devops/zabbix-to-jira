#!/bin/bash

set -o pipefail



######################################### === PURPOSE OF THE SCRIPT === #########################################
#                                                                                                               #
# The purpose is to scan for active (PROBLEM) triggers in Zabbix, create a JIRA ticket for each trigger found   #
# and acknowledge the last trigger's event with the message containing reference to JIRA ticket.                #
#                                                                                                               #
# This way, in the next run of script, PROBLEM triggers will not be included, so the scripr will always grab    #
# new PROBLEM triggers only and create a JIRA ticket for them.                                                  #
#                                                                                                               #
#                                                                                                               #
# AUTHOR: zkovac-devops (zdenko.kovac@outlook.com)                                                              #
#                                                                                                               #
#################################################################################################################



#########################
### === VARIABLES === ###
#########################

SCRIPT_PATH=$( dirname $0 )
RESPONSE_BODY=${SCRIPT_PATH}/jira_response.json
CONFIG_FILE=${SCRIPT_PATH}/config.json

BASH_HELPER_LOG=${SCRIPT_PATH}/bash_helpers/log.sh
BASH_HELPER_PID=${SCRIPT_PATH}/bash_helpers/pid.sh


# Enable/initialize logging

source ${BASH_HELPER_LOG}

LOG_TIMESTAMP_FORMAT="%Y-%m-%d %H:%M:%S"
LOG_PREFIX=$( basename $0 )
LOG_FILE=/var/log/$( basename $0 .sh ).log	# Uncomment this line for production
LOG_OUTPUT=file					# if LOG_OUTPUT= then output to stdout; if LOG_OUTPUT=tee then output to stdout & file; if LOG_OUTPUT=file then output to file
LOG_LEVEL_DEBUG=y
LOG_LEVEL_INFO=y

log_setup


### Variables used for interaction with Zabbix API

ZBX_API_USER=$( eval cat ${CONFIG_FILE} | python -c 'import json,sys;obj=json.load(sys.stdin);print(obj["zbx_api_user"])' )
ZBX_API_PASSWD=$( eval cat ${CONFIG_FILE} | python -c 'import json,sys;obj=json.load(sys.stdin);print(obj["zbx_api_passwd"])' )
ZBX_API_URL=$( eval cat ${CONFIG_FILE} | python -c 'import json,sys;obj=json.load(sys.stdin);print(obj["zbx_api_url"])' )

### Variables used for interaction with JIRA REST API

JIRA_USER=$( eval cat ${CONFIG_FILE} | python -c 'import json,sys;obj=json.load(sys.stdin);print(obj["jira_user"])' )
JIRA_PASSWD=$( eval cat ${CONFIG_FILE} | python -c 'import json,sys;obj=json.load(sys.stdin);print(obj["jira_passwd"])' )
JIRA_API_URL=$( eval cat ${CONFIG_FILE} | python -c 'import json,sys;obj=json.load(sys.stdin);print(obj["jira_api_url"])' )
JIRA_PROJECT_KEY=$( eval cat ${CONFIG_FILE} | python -c 'import json,sys;obj=json.load(sys.stdin);print(obj["jira_project_key"])' )
JIRA_ISSUE_TYPE=$( eval cat ${CONFIG_FILE} | python -c 'import json,sys;obj=json.load(sys.stdin);print(obj["jira_issue_type"])' )



#########################
### === FUNCTIONS === ###
#########################

########## === FUNCTION === ##########
#                                    #
# 	 NAME: login_to_zabbix       #
# DESCRIPTION: Log in to Zabbix API  #
#                                    #
######################################

function login_to_zabbix() {

AUTH_TOKEN=$( curl --silent --noproxy 127.0.0.1 --header "Content-Type: application/json-rpc" --data "{ \"jsonrpc\": \"2.0\", \"method\": \"user.login\", \"params\": { \"user\": \"${ZBX_API_USER}\", \"password\": \"${ZBX_API_PASSWD}\" }, \"id\": 1 }" ${ZBX_API_URL} | jq -r ".result" )

if [ "${AUTH_TOKEN}" != "null" ]
then
        log_info -n "Login to Zabbix API successfull."
else
	log_error -n "Can't login to Zabbix API! Script exited."
	exit
fi

}


########### === FUNCTION === ###########
#                                      #
# 	 NAME: logout_from_zabbix      #
# DESCRIPTION: Log out from Zabbix API #
#                                      #
########################################

function logout_from_zabbix() {

curl --silent --noproxy 127.0.0.1 --header "Content-Type: application/json-rpc" --data "{ \"jsonrpc\": \"2.0\", \"method\": \"user.logout\", \"params\": [], \"auth\": \"${AUTH_TOKEN}\", \"id\": 3 }" ${ZBX_API_URL} >/dev/null 2>&1

}


####################################### === FUNCTION === ######################################
#                                                                                             #
# 	 NAME: get_zabbix_alerts                                                              #
# DESCRIPTION: Get PROBLEM triggers older than 1h with last event unacknowledged from Zabbix  #
#                                                                                             #
###############################################################################################

function get_zabbix_alerts() {

login_to_zabbix

log_info -n "Searching for PROBLEM triggers in Zabbix ..."

TRIGGERS=$( curl --silent --noproxy 127.0.0.1 --header "Content-Type: application/json-rpc" --data "{ \"jsonrpc\": \"2.0\", \"method\": \"trigger.get\", \"params\": { \"output\": \"extend\", \"skipDependent\": \"1\", \"selectTriggers\": \"extend\", \"withLastEventUnacknowledged\": 1, \"expandDescription\": 1, \"filter\": { \"value\": 1, \"status\": 0 }, \"sortfield\": \"lastchange\", \"sortorder\": \"DESC\"}, \"id\": 2, \"auth\": \"${AUTH_TOKEN}\" }" ${ZBX_API_URL} | jq -r ".result[] | select( (.lastchange|tonumber) < (now - 3600) ) | { \"description\": .description, \"triggerid\": .triggerid, \"comments\": .comments }" )

NUMBER_OF_TRIGGERS=$( echo ${TRIGGERS} | jq -r ".description" | wc -l )

if [ ${NUMBER_OF_TRIGGERS} -eq 0 ]
then
	log_info -n "No active PROBLEM triggers found in Zabbix. Script exited."
	exit

elif [ ${NUMBER_OF_TRIGGERS} -gt 0 ]
then
	log_info -n "Active PROBLEM triggers found in Zabbix. Processing ..."
fi

logout_from_zabbix

}


############################### === FUNCTION === ################################
#                                                                               #
# 	 NAME: create_jira_issues                                               #
# DESCRIPTION: This function creates JIRA issues for PROBLEM triggers in Zabbix #
#                                                                               #
#################################################################################

function create_jira_issues() {

if [ ${NUMBER_OF_TRIGGERS} -ge 1 ]
then
	log_info -n "Creating JIRA issue(s) for ${NUMBER_OF_TRIGGERS} active trigger(s) ..."
fi

> ${RESPONSE_BODY}

echo ${TRIGGERS} | jq -c '{ "description": .description, "comments": .comments }' | while read -r line
do
	DESCRIPTION=$( echo "${line}" | jq -r ".description" )
	JIRA_DATA_TEMPLATE=${SCRIPT_PATH}/jira_data_file.out
	JIRA_DATA=$( eval "echo \"$( cat ${JIRA_DATA_TEMPLATE} )\"" )

	HTTP_CODE=$( curl --insecure --silent --user "${JIRA_USER}:${JIRA_PASSWD}" --request POST --data "${JIRA_DATA}" --header "Content-Type: application/json" ${JIRA_API_URL}/issue/ --output ${RESPONSE_BODY} --write-out "%{http_code}" )

	if [ "${HTTP_CODE}" == "201" ]
	then
		log_info -n "JIRA issue for trigger \"${DESCRIPTION}\" created." < /dev/null
	else
		log_error -n "Could not create JIRA issue for trigger \"${DESCRIPTION}\". Response code: ${HTTP_CODE}. Check ${RESPONSE_BODY}."
	fi
done

}


############################################ === FUNCTION === ############################################
#                                                                                                        #
# 	 NAME: get_jira_urls                                                                             #
# DESCRIPTION: This function helps to get JIRA URLs for issues created with create_jira_issues function  #
#              These URLs will be used in message when event.acknowledge Zabbix API call is used         #
#                                                                                                        #
##########################################################################################################

function get_jira_urls() {

log_info -n "Getting JIRA URL(s) for created issue(s) ..."

ISSUE_KEYS=($( cat ${RESPONSE_BODY} | jq -r ".key" ))
JIRA_URLS=()

for (( i=0; i< ${#ISSUE_KEYS[@]}; i++ ))
do
	JIRA_URLS+=("https://{your_jira_ip}/browse/${ISSUE_KEYS[i]}")
	
	if [ ${#ISSUE_KEYS[@]} -eq ${#JIRA_URLS[@]} ]
	then
		log_info -n "JIRA URL for ${ISSUE_KEYS[i]} issue created: ${JIRA_URLS[i]}"
	else
		log_error -n "Number of JIRA issues does not correspond with the number of JIRA URLs created!"
	fi
done

}


################################################################### === FUNCTION === #######################################################################
#                                                                                                                                                          #
# 	 NAME: acknowledge_trigger_events                                                                                                                  #
# DESCRIPTION: Acknowledge PROBLEM triggers in Zabbix                                                                                                      #
#              Acknowledgement means that users were notified about the PROBLEM trigger (in this case JIRA ticket was created, or email was sent, etc ...) #
#                                                                                                                                                          #
############################################################################################################################################################

function acknowledge_trigger_events() {

get_jira_urls
login_to_zabbix

log_info -n "Acknowledging events for triggers with JIRA ticket created ..."

EVENT_IDS=($( for triggerid in $( echo ${TRIGGERS} | jq -r ".triggerid" ); do curl --silent --noproxy 127.0.0.1 --header "content-type: application/json-rpc" --data "{ \"jsonrpc\": \"2.0\", \"method\": \"event.get\", \"params\": { \"output\": \"extend\", \"select_acknowledges\": \"extend\", \"objectids\": \"${triggerid}\", \"value\": \"1\",\"sortfield\": \"clock\", \"sortorder\": \"DESC\", \"limit\": \"1\"}, \"id\": 4, \"auth\": \"${AUTH_TOKEN}\" }" ${ZBX_API_URL} | jq -r ".result[].eventid"; done ))

for (( i=0; i< ${#EVENT_IDS[@]}; i++ ))
do
	curl --silent --noproxy 127.0.0.1 --header "content-type: application/json-rpc" --data "{ \"jsonrpc\": \"2.0\", \"method\": \"event.acknowledge\", \"params\": { \"eventids\": \"${EVENT_IDS[i]}\", \"message\": \"JIRA ticket created (${JIRA_URLS[i]})\", \"action\": 1}, \"id\": 5, \"auth\": \"${AUTH_TOKEN}\" }" ${ZBX_API_URL} >/dev/null 2>&1
	
	if [ $? -eq 0 ]
	then
		log_info -n "Event (ID: ${EVENT_IDS[i]}) acknowledged in Zabbix."
	else
		log_error -n "Event (ID: ${EVENT_IDS[i]}) could not be acknowledged!"
	fi
done

logout_from_zabbix

}



############################
### === MAIN ROUTINE === ###
############################

# 1. Search Zabbix for active (PROBLEM) triggers
get_zabbix_alerts

# 2. Create JIRA ticket for every PROBLEM trigger older than 1 hour
create_jira_issues

# 3. Acknowledge every PROBLEM trigger with the link to JIRA ticket
acknowledge_trigger_events
