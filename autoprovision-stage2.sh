#!/bin/sh

# autoprovision stage 2: this script will be executed upon boot if the extroot was successfully mounted (i.e. rc.local is run from the extroot overlay)

. /root/autoprovision-functions.sh


autoprovisionStage2()
{
    log "Autoprovisioning stage2 speaking"
	#Disable the write cache on each drive by running hdparm -W0 /dev/sda against each drive on every boot.
	hdparm -W0 /dev/sda
	
    # TODO this is a rather sloppy way to test whether stage2 has been done already, but this is a shell script...
    if [ $(uci get system.@system[0].log_type) == "file" ]; then
        log "Seems like autoprovisioning stage2 has been done already. Running stage3."
        /root/autoprovision-stage3.sh
        #log "Seems like autoprovisioning stage2 has been done already."
    else
        # CUSTOMIZE: with an empty argument it will set a random password and only ssh key based login will work.
        # please note that stage2 requires internet connection to install packages and you most probably want to log in
        # on the GUI to set up a WAN connection. but on the other hand you don't want to end up using a publically
        # available default password anywhere, therefore the random here...
        #setRootPassword "kimax"
        crontab - <<EOF
# */10 * * * * /root/autoprovision-stage3.sh
0 0 * * * /usr/sbin/logrotate /etc/logrotate.conf
EOF
	# Fix default route
	route add default gw 192.168.1.1
        # logrotate is complaining without this directory
        mkdir -p /var/log/archive
        mkdir -p /var/lib
        uci set system.@system[0].log_type=file
        uci set system.@system[0].log_file=/var/log/syslog
        uci set system.@system[0].log_size=0
        uci commit
        sync
        reboot
    fi
}

autoprovisionStage2
