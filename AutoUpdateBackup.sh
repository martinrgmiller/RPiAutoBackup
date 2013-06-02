    #!/bin/bash

    # This script is designed to run on a RaspberryPi and is intened to automatically up and backup the operational SD card.
    # Further information can be found at http://wiki.raspberrytorte.com/index.php?title=Auto_Update_Backup

    # EXTDIR must be external i.e. not on the SD card for example a usb stick or network share
    # BACKUPDIR is the location to write the backup on EXTDIR
    # PURGE determines if old backups are deleted before zipping the latest sucessful backup, PURGE=false
    # CIFSHOST is the optional network share host name or address, comment out to disable mounting a CIFSSHARE
    # CIFSSHARE is the share on the CIFSHOST, required if CIFSHOST is enabled
    # CIFSCRED is the local path to the CIFS credentials, required if CIFSHOST is enabled
    # CIFSUID is the users who has write permissions to CIFSSHARE, required if CIFSHOST is enabled
    EXTDIR=/media/cifsshares/Public
    BACKUPDIR=$EXTDIR/RPi_autobuild_backup
    PURGE=false
    CIFSHOST=//192.168.0.8
    CIFSSHARE=Public
    CIFSCRED=/home/raspberrypi/cifs.cred
    CIFSUID=raspberrypi

    echo "Updating System"
    apt-get update
    apt-get -y upgrade

    echo "Checking CIFSSHARE"
    if [ -z ${CIFSHOST+x} ];
       then
            echo "CIFSHOST is unset, bypassing CIFS mounting"
            CIFSSHAREENABLE=0
       else
            echo "temporarily mounting $CIFSHOST/$CIFSSHARE"
            CIFSSHAREENABLE=1
            # Check is mount point available
            if [ ! -d "$EXTDIR" ];
               then
               echo "Mount point doesn't exist, creating it now"
               mkdir -p $EXTDIR
            fi
            echo "Mounting Backup location"
            mount -t cifs $CIFSHOST/$CIFSSHARE -o credentials=$CIFSCRED,uid=$CIFSUID $EXTDIR
    fi

    echo "Starting RaspberryPI backup process!"
    # First check if pv package is installed, if not, install it first
    PACKAGESTATUS=`dpkg -s pv | grep Status`;

    if dpkg -s pv | grep -q Status;
       then
          echo "Package 'pv' is installed."
       else
          echo "Package 'pv' is NOT installed."
          echo "Installing package 'pv'. Please wait..."
          apt-get -y install pv
    fi

    # Check if backup directory exists
    if [ ! -d "$BACKUPDIR" ];
       then
          echo "Backup directory $BACKUPDIR doesn't exist, creating it now!"
          mkdir $BACKUPDIR
    fi

    # Create a filename with datestamp for our current backup (without .img suffix)
    OFILE="$BACKUPDIR/backup_$(date +%Y%m%d_%H%M%S)"

    # Create final filename, with suffix
    OFILEFINAL=$OFILE.img

    # First sync disks
    sync; sync

    # Shut down some services before starting backup process
    echo "Stopping some services before backup."
    service apache2 stop
    service mysql stop
    service cron stop

    # Begin the backup process, should take about 1 hour from 8Gb SD card to HDD
    echo "Backing up SD card to USB HDD."
    echo "This will take some time depending on your SD card size and read performance. Please wait..."
    SDSIZE=`blockdev --getsize64 /dev/mmcblk0`;
    pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd of=$OFILE bs=1M conv=sync,noerror iflag=fullblock

    # Wait for DD to finish and catch result
    RESULT=$?

    # Start services again that where shutdown before backup process
    echo "Start the stopped services again."
    service apache2 start
    service mysql start
    service cron start

    # If command has completed successfully, delete previous backups and exit
    if [ $RESULT = 0 ];
       then
          echo "Successful backup"
          if [ $PURGE = true ];
             then
                echo "Purging Old Backups before zipping"
                exit 0
                rm -f $BACKUPDIR/backup_*.tar.gz
          fi
          mv $OFILE $OFILEFINAL
          echo "Latest Backup is being tarred. Please wait..."
          tar zcf $OFILEFINAL.tar.gz $OFILEFINAL
          rm -rf $OFILEFINAL
          echo "RaspberryPI backup process completed! FILE: $OFILEFINAL.tar.gz"
          # Clean up mountpoint
          if [ $CIFSSHAREENABLE = 1 ];
             then
                echo "unmounting temporary CIFSSHARE"
                umount $EXTDIR
                #rmdir  -p $EXTDIR
          fi
          exit 0

    # Else remove attempted backup file
       else
          echo "Backup failed! Previous backup files untouched."
          echo "Please check there is sufficient space on the HDD."
          rm -f $OFILE
          echo "RaspberryPI backup process failed!"
          exit 1
    fi
