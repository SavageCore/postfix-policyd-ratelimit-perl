#!/bin/bash
RDMS_USER=$1
RDMS_PASS=$2

genpasswd() {
	local l=$1
       	[ "$l" == "" ] && l=16
      	tr -dc A-Za-z0-9_ < /dev/urandom | head -c ${l} | xargs
}

# get current directory
DIR="$( cd "$( dirname "$0" )" && pwd )"
cd "$DIR"

# assure our logfile belongs to user postfix
touch /var/log/ratelimit-policyd.log
chown postfix:postfix /var/log/ratelimit-policyd.log

# install init script
chmod 755 $DIR/daemon.pl
cp "$DIR/systemd/ratelimit-policyd" /etc/systemd/system/ratelimit-policyd.service

# install logrotation configuration
ln -sf "$DIR/logrotate.d/ratelimit-policyd" /etc/logrotate.d/

# setup RDMS schema
mysql -u$RDMS_USER -p$RDMS_PASS < $DIR/mysql-schema.sql

# create RDMS user
PASSWORD=`genpasswd 16`
mysql -u$RDMS_USER -p$RDMS_PASS -e "GRANT USAGE ON *.* TO policyd@'localhost' IDENTIFIED BY '$PASSWORD'";
mysql -u$RDMS_USER -p$RDMS_PASS -e "GRANT SELECT, INSERT, UPDATE, DELETE ON policyd.* TO policyd@'localhost'";
sed -i "s/RDMS_PASS_REPLACE/$PASSWORD/g" $DIR/daemon.pl

# install required Perl modules
sudo yum install perl-Switch

# enable startup on boot and start now
systemctl start ratelimit-policyd.service
systemctl enable ratelimit-policyd.service