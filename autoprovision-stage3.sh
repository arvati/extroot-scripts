#!/bin/sh

# autoprovision stage 3: this script will be executed upon boot if the extroot was successfully mounted  (i.e. rc.local is run from the extroot overlay) and stage 2 completed
# also executed on a crontab basis
## */10 * * * * /root/autoprovision-stage3.sh

. /root/autoprovision-functions.sh


autoprovisionStage3()
{
    log "Autoprovisioning stage3 speaking"

}

autoprovisionStage3
