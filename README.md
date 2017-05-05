# zabbix-to-jira

Creating JIRA tickets for PROBLEM triggers in Zabbix automatically.<br>
**My environment setup:** Script is executed every 10 minutes and searches for PROBLEM triggers older than 1 hour in Zabbix. 

## Prerequisites

The only prerequisite is to have `jq (version 1.5)` installed; `curl` + `python` should already been available on your system (if not, install them)

## How to make the script running?

1. Clone this repo: `git clone https://github.com/zkovac-devops/zabbix-to-jira.git`
2. Modify *config.json* file, so that script can load variables correctly
3. Update *jira_data_file.out* file to fit your needs
4. Update the value (3600) in TRIGGERS variable to fit your needs 
5. Replace *{your_jira_ip}* with the real IP of your JIRA instance in get_jira_urls function. Search for this line:
```
JIRA_URLS+=("https://{your_jira_ip}/browse/${ISSUE_KEYS[i]}")
```
6. On my environment, I have added entry in crontab (*/etc/crontab*), so script is executed every 10 minutes
```
*/10 *	* * *	root	/root/zabbix_to_jira/zabbix_to_jira.sh
```

**Note:** Default path to logfile (useful for debugging): */var/log/zabbix_to_jira.log*

## Log output

```
2017-05-03 18:50:01 [zabbix_to_jira.sh] [INFO] Login to Zabbix API successfull.
2017-05-03 18:50:01 [zabbix_to_jira.sh] [INFO] Searching for PROBLEM triggers in Zabbix ...
2017-05-03 18:50:01 [zabbix_to_jira.sh] [INFO] Active PROBLEM triggers found in Zabbix. Processing ...
2017-05-03 18:50:01 [zabbix_to_jira.sh] [INFO] Creating JIRA issue(s) for 1 active trigger(s) ...
2017-05-03 18:50:04 [zabbix_to_jira.sh] [INFO] JIRA issue for trigger "Disk I/O is overloaded on Zabbix server" created.
2017-05-03 18:50:04 [zabbix_to_jira.sh] [INFO] Getting JIRA URL(s) for created issue(s) ...
2017-05-03 18:50:04 [zabbix_to_jira.sh] [INFO] JIRA URL for TEST-3001 issue created: https://{JIRA_IP}/browse/TEST-3001
2017-05-03 18:50:04 [zabbix_to_jira.sh] [INFO] Login to Zabbix API successfull.
2017-05-03 18:50:04 [zabbix_to_jira.sh] [INFO] Acknowledging events for triggers with JIRA ticket created ...
2017-05-03 18:50:04 [zabbix_to_jira.sh] [INFO] Event (ID: 72844) acknowledged in Zabbix.

```
