# extroot-scripts
scripts to help creating extroot on lede and openwrt devices

Install packages to access storage device:     
kmod-usb-core kmod-usb2 kmod-usb-ohci kmod-ata-core kmod-scsi-core kmod-usb-storage kmod-usb-storage-extras 


Install these tool packages:   
swap-utils wipefs mount-utils kmod-nls-utf8 kmod-nls-base kmod-fs-btrfs kmod-fs-ext4 fdisk hdparm btrfs-progs block-mount

take a look at: https://lede-project.org/docs/user-guide/drives


Copy bash scripts to /root folder


execute script:     
./autoprovision-stage1.sh


reboot
