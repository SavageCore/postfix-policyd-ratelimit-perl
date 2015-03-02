# ratelimit-policyd

A Sender rate limit policy daemon for Postfix.

## Credits

This project was forked from [onlime/ratelimit-policyd](https://github.com/onlime/ratelimit-policyd) with the intention to create a fully automated install script targeted towards Fedora whilst adding features as we see fit. All credits go to [Simone Caruso](http://www.simonecaruso.com) for his original work ([bejelith/send_rate_policyd](https://github.com/bejelith/send_rate_policyd)).

## Purpose

This small Perl daemon **limits the number of emails** sent by users through your Postfix server, and stores message quota in a RDMS system (MySQL). It counts the number of recipients for each sent email. You can setup a send rate per user or sender domain (via SASL username) on **seconds-ly/hourly/daily/weekly/monthly** basis.

**The program uses the Postfix policy delegation protocol to control access to the mail system before a message has been accepted (please visit [SMTPD_POLICY_README.html](http://www.postfix.org/SMTPD_POLICY_README.html) for more information).**

ratelimit-policyd will never be as feature-rich as other policy daemons. Its main purpose is to limit the number of emails per account, nothing more and nothing less. We focus on performance and simplicity.

**This daemon caches the quota in memory, so you don't need to worry about I/O operations!**

## New Features

The original forked code from [onlime/ratelimit-policyd](https://github.com/onlime/ratelimit-policyd) was improved with the following new features:

- installer now creates RDMS user and tables
- added seconds option (see $secondscount in daemon.pl to control how frequently)
- systemd startup scripts for Fedora (and probably CentOS) compatibility
- daemon will start on boot

## Installation

Recommended installation:

```bash
$ cd /opt/
$ git clone https://github.com/SavageCore/ratelimit-policyd.git ratelimit-policyd
$ cd ratelimit-policyd
$ chmod +x install.sh
$ ./install.sh
```

Adjust configuration options in ```daemon.pl```:

```perl
### CONFIGURATION SECTION
my @allowedhosts    = ('127.0.0.1', '10.0.0.1');
my $LOGFILE         = "/var/log/ratelimit-policyd.log";
my $PIDFILE         = "/var/run/ratelimit-policyd.pid";
my $SYSLOG_IDENT    = "ratelimit-policyd";
my $SYSLOG_LOGOPT   = "ndelay,pid";
my $SYSLOG_FACILITY = LOG_MAIL;
chomp( my $vhost_dir = `pwd`);
my $port            = 10032;
my $listen_address  = '127.0.0.1'; # or '0.0.0.0'
my $s_key_type      = 'domain'; # domain or email
my $dsn             = "DBI:mysql:policyd:127.0.0.1";
my $db_user         = 'policyd';
my $db_passwd       = 'RDMS_PASS_REPLACE'; #DO NOT TOUCH
my $db_table        = 'ratelimit';
my $db_quotacol     = 'quota';
my $db_tallycol     = 'used';
my $db_updatedcol   = 'updated';
my $db_expirycol    = 'expiry';
my $db_wherecol     = 'sender';
my $db_persistcol   = 'persist';
my $deltaconf       = 'daily'; # seconds|hourly|daily|weekly|monthly
my $secondscount    = 15; # how often to check in seconds if set above
my $defaultquota    = 1000;
my $sql_getquota    = "SELECT $db_quotacol, $db_tallycol, $db_expirycol, $db_persistcol FROM $db_table WHERE $db_wherecol = ? AND $db_quotacol > 0";
my $sql_updatequota = "UPDATE $db_table SET $db_tallycol = $db_tallycol + ?, $db_updatedcol = NOW(), $db_expirycol = ? WHERE $db_wherecol = ?";
my $sql_updatereset = "UPDATE $db_table SET $db_quotacol = ?, $db_tallycol = ?, $db_updatedcol = NOW(), $db_expirycol = ? WHERE $db_wherecol = ?";
my $sql_insertquota = "INSERT INTO $db_table ($db_wherecol, $db_quotacol, $db_tallycol, $db_expirycol) VALUES (?, ?, ?, ?)";
### END OF CONFIGURATION SECTION
```

**Take care of using a port higher than 1024 to run the script as non-root (our service runs it as user "postfix").**

In most cases, the default configuration should be fine.

Now, restart the daemon (if you made any changes to configuration):

```bash
$ systemctl restart ratelimit-policyd
```

## Testing

Check if the daemon is really running:

```bash
$ netstat -tl | grep 10032
tcp        0      0 localhost:10032         0.0.0.0:*               LISTEN

$ ps aux | grep daemon.pl
postfix     15544  0.2  0.3 508360 24856 ?        Ssl  11:15   0:00 /opt/ratelimit-policyd/daemon.pl > /dev/null 2>&1 &

$ pstree -p | grep ratelimit
systemd(1)-+-/opt/ratelimit-(15544)-+-{/opt/ratelimit-}(15546)
           |                        |-{/opt/ratelimit-}(15547)
           |                        `-{/opt/ratelimit-}(15548)

```

Print the cache content (in shared memory) with update statistics:

```bash
$ /opt/ratelimit-policyd/daemon.pl printshm
Printing shm:
Domain          :       Quota   :       Used    :       Expire
Threads running: 3, Threads waiting: 0
```

## Postfix Configuration

Modify the postfix data restriction class ```smtpd_data_restrictions``` like the following, ```/etc/postfix/main.cf```:

```
smtpd_data_restrictions = check_policy_service inet:$IP:$PORT
```

sample configuration (using ratelimitpolicyd as alias as smtpd_data_restrictions does not allow any whitespace):

```
smtpd_restriction_classes = ratelimitpolicyd
ratelimitpolicyd = check_policy_service inet:127.0.0.1:10032

smtpd_data_restrictions =
        reject_unauth_pipelining,
        ratelimitpolicyd,
        permit
```

If you're sure that ratelimit-policyd is really running, restart Postfix:

```
$ systemctl restart postfix
```

## Logging

Detailed logging is written to ``/var/log/ratelimit-policyd.log``. In addition, the most important information including the counter status is written to syslog:

```
$ tail -f /var/log/ratelimit-policyd.log 
Sat Jan 10 12:08:37 2015 Looking for demo@example.com
Sat Jan 10 12:08:37 2015 07F452AC009F: client=4-3.2-1.cust.example.com[1.2.3.4], sasl_method=PLAIN, sasl_username=demo@example.com, recipient_count=1, curr_count=6/1000, status=UPDATE

$ grep ratelimit-policyd /var/log/syslog
Jan 10 12:08:37 mx1 ratelimit-policyd[2552]: 07F452AC009F: client=4-3.2-1.cust.example.com[1.2.3.4], sasl_method=PLAIN, sasl_username=demo@example.com, recipient_count=1, curr_count=6/1000, status=UPDATE
```