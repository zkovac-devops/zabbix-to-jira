# bash_helpers

- log.sh - simple log framework for bash scripts.<br>

Usage:
```
# Source the implemenation first
$ source log.sh

# Initialize the framework by log_setup() - for more details, see function comments
$ log_setup

# Use the log() function
$ log hello world
2017-02-08T10:54:54+01:00 hello world

$ echo hello world | log
2017-02-08T10:55:45+01:00 hello world

# Functions log_{debug|info|error}() do the level setup
# By default only the log_error() outputs to stderr
$ log_debug hello world
$ log_info hello world
$ log_error hello world
2017-02-08T11:08:33+01:00 ERROR hello world

# Log functions do pass through last exit code
$ ( exit 200; ); log hello world ; echo $?
2017-02-08T11:19:51+01:00 hello world
200
```

- pid.sh - pid file management.

Used for cases when a script is executed on scheduled basis (cron) but the script needs to check if previous instance is still running.<br>

Usage:
```
# Source the implemenation first
$ source pid.sh

# Initialize it by pid_setup() - for more details, see function comments
$ pid_setup

# Store the pid with error checking (again, see function comments for more details)
$ if ! pid_store; then echo "failed to store the pid"; exit 1; fi

# ... do stuff ...

# Clean up at the end
$ pid_cleanup
```
