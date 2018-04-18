#!/bin/sh

# utility functions for the various stages of autoprovisioning

# make sure that installed packages take precedence over busybox. see https://dev.openwrt.org/ticket/18523
PATH="/usr/bin:/usr/sbin:/bin:/sbin"


log()
{
    /usr/bin/logger -t autoprov -s $*
}

setRootPassword()
{
    local password=$1
    if [ "$password" == "" ]; then
        # set and forget a random password merely to disable telnet. login will go through ssh keys.
        password=$(</dev/urandom sed 's/[^A-Za-z0-9+_]//g' | head -c 22)
    fi
    #echo "Setting root password to '"$password"'"
    log "Setting root password"
    echo -e "$password\n$password\n" | passwd root
}

step() {
    echo -n "$@"
    STEP_OK=0
    [[ -w /tmp ]] && echo $STEP_OK > /tmp/step.$$
}

try() {
    # Check for `-b' argument to run command in the background.
    local BG=
    [[ $1 == -b ]] && { BG=1; shift; }
    [[ $1 == -- ]] && {       shift; }
    # Run the command.
    if [[ -z $BG ]]; then
        "$@"
    else
        "$@" &
    fi
    # Check if command failed and update $STEP_OK if so.
    local EXIT_CODE=$?
    if [[ $EXIT_CODE -ne 0 ]]; then
        STEP_OK=$EXIT_CODE
        [[ -w /tmp ]] && echo $STEP_OK > /tmp/step.$$
    fi
    return $EXIT_CODE
}

next() {
    [[ -f /tmp/step.$$ ]] && { STEP_OK=$(< /tmp/step.$$); rm -f /tmp/step.$$; }
    [[ $STEP_OK -eq 0 ]]  && echo_success || echo_failure
    echo
    return $STEP_OK
}

getPendriveSize()
{
    # this is needed for the mmc card in some (all?) Huawei 3G dongle.
    # details: https://dev.openwrt.org/ticket/10716#comment:4
    if [ -e /dev/sdb ]; then
        # force re-read of the partition table
        head -c 1024 /dev/sdb >/dev/null
    fi

    if (grep -q sdb /proc/partitions) then
        cat /sys/block/sdb/size
    else
        echo 0
    fi
}

createPartitions()
{
local device=$1
# sda1 is 'rootfs'
# sda2 is 'swap'
# sda3 is 'data'
    fdisk "${device}" <<EOF
o
n
p
1

+4096M
n
p
2

+64M
n
p
3


t
2
82
w
q
EOF
    until [ -e "${device}1" ]
    do
        echo "Waiting for partitions to show up in ${device}"
        sleep 1
    done
}

setupExtroot()
{
	local type=$1
	local device=$2
	local filesystem=$3
	#dd if=/dev/zero of="${device}" bs=1M count=1
	wipefs --all "${device}"
	mkdir -p /mnt/extroot/
    	uci set fstab.@global[0].delay_root='15'
	uci set fstab.@global[0].anon_swap='0'
	uci set fstab.@global[0].anon_mount='0'
	uci set fstab.@global[0].auto_swap='0'
	uci set fstab.@global[0].auto_mount='0'
	uci set fstab.@global[0].check_fs='0'
	# Make jffs2 boot acessible
	log "Configuring /overlay-boot folder"
	mkdir /overlay-boot
	uci get fstab.jffs2 && uci delete fstab.jffs2
	uci set fstab.jffs2=mount
	uci set fstab.jffs2.target='/overlay-boot'
	uci set fstab.jffs2.fstype='jffs2'
	uci set fstab.jffs2.device='/dev/mtdblock6'
	uci set fstab.jffs2.options='rw,sync'
	uci set fstab.jffs2.enabled='1'
	uci commit fstab
	if [ "${filesystem}" == "btrfs" ]; then
		mkfs.btrfs -f -d dup -m dup -L extroot "${device}"
	        #mount -t btrfs LABEL=extroot /mnt/extroot
	        log "Finished setting up filesystem"
	        mount -t btrfs "${device}" /mnt/extroot
		if [ "${type}" == "overlay" ]; then
			btrfs subvolume create /mnt/extroot/overlay
			mkdir -p /mnt/extroot/overlay/upper/
			btrfs subvolume create /mnt/extroot/overlay/upper/home
			btrfs subvolume create /mnt/extroot/overlay/upper/srv		
			uci get fstab.overlay && uci delete fstab.overlay
			uci set fstab.overlay=mount
			uci set fstab.overlay.target='/overlay'
			uci set fstab.overlay.fstype='btrfs'
			uci set fstab.overlay.device="${device}"
			#local subvolid=$(btrfs subvolume list -t /mnt/extroot | grep overlay | cut -c1-3)
			uci set fstab.overlay.options='subvol=/overlay'
			uci set fstab.overlay.enabled='1'
			uci get fstab.rootfs && uci set fstab.rootfs.enabled='0'
	    		uci commit fstab 
			mkdir -p /mnt/extroot/overlay/upper/etc/
	    		cat >/mnt/extroot/overlay/upper/etc/rc.local <<EOF
/root/autoprovision-stage2.sh
exit 0
EOF
	    	else
			btrfs subvolume create /mnt/extroot/rootfs
			btrfs subvolume create /mnt/extroot/rootfs/home
			btrfs subvolume create /mnt/extroot/rootfs/srv
			uci get fstab.rootfs && uci delete fstab.rootfs
			uci set fstab.rootfs=mount
			uci set fstab.rootfs.target='/'
			uci set fstab.rootfs.fstype='btrfs'
			uci set fstab.rootfs.device="${device}"
			#local subvolid=$(btrfs subvolume list -t /mnt/extroot | grep rootfs | cut -c1-3)
			uci set fstab.rootfs.options='subvol=/rootfs'
			uci set fstab.rootfs.enabled='1'
			uci get fstab.overlay && uci set fstab.overlay.enabled='0'
	    		uci commit fstab 
			mkdir -p /tmp/introot
			mount --bind / /tmp/introot
			tar -C /tmp/introot -cvf - . | tar -C /mnt/extroot/rootfs -xf -
			umount /tmp/introot
			#rsync -avxH / /mnt/extroot/rootfs/
			mkdir -p /mnt/extroot/rootfs/etc/
	    		cat >/mnt/extroot/rootfs/etc/rc.local <<EOF
/root/autoprovision-stage2.sh
exit 0
EOF
	    	fi        
	else
		umount "${device}3"
		umount "${device}1"
		swapoff "${device}2"
		createPartitions "${device}"
		mkswap -L swap "${device}2"
		mkfs.ext4  -F -L root "${device}1"
		mkfs.btrfs -f -d dup -m dup -L data "${device}3"
		log "Finished setting up filesystem"
	        mount -t ext4 "${device}1" /mnt/extroot
	        uci get fstab.diskswap && uci delete fstab.diskswap
		uci set fstab.diskswap=swap
		uci set fstab.diskswap.device="${device}2"
		uci set fstab.diskswap.enabled='1'
		mkdir -p /mnt/data
		uci get fstab.data && uci delete fstab.data
		uci set fstab.data=mount
		uci set fstab.data.target='/mnt/data'
		uci set fstab.data.fstype='btrfs'
		uci set fstab.data.device="${device}3"
		uci set fstab.data.enabled='1'
		if [ "${type}" == "overlay" ]; then
			mkdir -p /mnt/extroot/upper/		
			uci get fstab.overlay && uci delete fstab.overlay
			uci set fstab.overlay=mount
			uci set fstab.overlay.target='/overlay'
			uci set fstab.overlay.fstype='ext4'
			uci set fstab.overlay.device="${device}1"
			uci set fstab.overlay.options='rw,relatime,data=ordered'
			uci set fstab.overlay.enabled='1'
			uci get fstab.rootfs && uci set fstab.rootfs.enabled='0'
	    		uci commit fstab 
			mkdir -p /mnt/extroot/upper/etc/
	    		cat >/mnt/extroot/upper/etc/rc.local <<EOF
/root/autoprovision-stage2.sh
exit 0
EOF
		else
			uci get fstab.rootfs && uci delete fstab.rootfs
			uci set fstab.rootfs=mount
			uci set fstab.rootfs.target='/'
			uci set fstab.rootfs.fstype='ext4'
			uci set fstab.rootfs.device="${device}1"
			uci set fstab.rootfs.options='rw,relatime,data=ordered'
			uci set fstab.rootfs.enabled='1'
			uci get fstab.overlay && uci set fstab.overlay.enabled='0'
	    		uci commit fstab 
			mkdir -p /tmp/introot
			mount --bind / /tmp/introot
			tar -C /tmp/introot -cvf - . | tar -C /mnt/extroot -xf -
			umount /tmp/introot
			#rsync -avxH / /mnt/extroot/rootfs/
			mkdir -p /mnt/extroot/etc/
	    		cat >/mnt/extroot/etc/rc.local <<EOF
/root/autoprovision-stage2.sh
exit 0
EOF
		fi
	fi
    	#uci show fstab	
	umount /mnt/extroot
	log "Finished setting up extroot"
}
