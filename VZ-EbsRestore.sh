#!/bin/bash
##
trap '' 2
region=$(wget -q -O- http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -e 's/\([1-9]\).$/\1/g')
#INSTANCE_ID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
#INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
#AZ=$(aws ec2 describe-volumes --query 'Volumes[*].AvailabilityZone' --filters  Name=attachment.instance-id,Values=$INSTANCE_ID --output text | awk '{print $1;}')
HOSTNAME=$(hostname)
export http_proxy=http://proxy.ebiz.verizon.com:80
export https_proxy=http://proxy.ebiz.verizon.com:80
export NO_PROXY=169.254.169.254
#
## # Set Logging Options
logfile="/vzwhome/z776665/EBS-Restore.log"
logfile_max_lines="5000"
##
##
# Safety feature: exit script if error is returned, or if variables not set.
# Exit if a pipeline results in an error.
set -ue
set -o pipefail
##
###
### *****************  FUNCTIONS  **************
##
# Function: Setup logfile and redirect stdout/stderr.
log_setup() {
    # Check if logfile exists and is writable.
    ( [ -e "$logfile" ] || touch "$logfile" ) && [ ! -w "$logfile" ] && echo "ERROR: Cannot write to $logfile. Check permissions or sudo access." && exit 1

    tmplog=$(tail -n $logfile_max_lines $logfile 2>/dev/null) && echo "${tmplog}" > $logfile
    exec > >(tee -a $logfile)
    exec 2>&1
}

# Function: Log an event.
log() {
    echo "[$(date +"%Y-%m-%d"+"%T")]: $*"
}
##
### Find AZ (Availability Zone)
function findAZ () {
AZ=$(aws ec2 describe-instances --instance-ids $1 --query  'Reservations[*].Instances[*].Placement.AvailabilityZone' --output text)
        echo $AZ
}
##
### To verify if Device Name is in use
function verifyDN () {
#echo  "$(lsblk  -d -e 11,1 |grep $1 |awk '{print $1}')"
if [[ "$(aws ec2 describe-instances --instance-ids $userInstanceID --query 'Reservations[*].Instances[].[BlockDeviceMappings[*].{DeviceName:DeviceName,VolumeName:Ebs.VolumeId}]' --output text |awk '{print $1}' |cut -d'/' -f3 |grep $1)" ]];then 2>&1|tee -a $logfile
return "1"
else
return "0"
fi
}
##
###
function getDN () {
for var in xvdx xvdw xvdv xvdu xvdt xvds xvdr
do
verifyDN $var
if [ $? = "0" ] ; then
#echo $var
DN=$var
break
fi
done
}
##
### Attaching the newely created EBS Volume
function attachVol () {
getDN
echo
aws ec2 attach-volume --volume-id $1 --instance-id $userInstanceID --device /dev/$DN 2>&1|tee -a $logfile
echo
log "The EBS Volume $1 has been attached to /dev/$DN on the Instance ID $userInstanceID" 2>&1 | tee -a $logfile
echo
}
##
### EBS Volume restore on the current instance
function restore_ebs () {
userInstanceID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
echo
log "===================================================================" >> $logfile
log >> $logfile
log "The EBS Restore process is initiated for $userInstanceID" 2>&1 | tee -a $logfile
echo
echo
echo Please wait while the EBS Volumes attached to this instance are listed ...
echo "=========================================================================="
echo
echo
queryEBSVol $userInstanceID
echo
echo Please enter the EBSVolId from the table which you would like to restore
echo
read EBSVolID
echo
log "You have Selected to restore the EBS Volume $EBSVolID" 2>&1 | tee -a $logfile
echo
echo Please wait while we pull the available snapshot list for $EBSVolID
echo "==================================================================="
querySnapshots $EBSVolID
echo
echo
echo Please enter the "SNAPSHOT ID" which you would like to restore
echo
read userSnapshot
echo
log "You have selected the SnapshotID as $userSnapshot" 2>&1 | tee -a $logfile
echo
echo "Creating the new Volume from the Snapshot volume $userSnapshot, Please wait ... "
echo
optionForVol
echo
#newEBSVol
echo done
}
#
## Query for volumes on the local instance
function queryEBSVol () {
aws ec2 describe-volumes --query 'Volumes[*].{InstanceId:Attachments[0].InstanceId,EBSVolId:VolumeId,LinuxVolID:Attachments[0].Device,AZ:AvailabilityZone,Size:Size,Key:Tags[0].Key}' \
--filters  Name=attachment.instance-id,Values=$1 --output table
}
##
### ******  Query for Snapshots ******
function querySnapshots () {
aws ec2 describe-snapshots --query 'Snapshots[*].{EBSVolId:VolumeId,SnapshotDate:StartTime,SnapshotID:SnapshotId,Tag:Tags[0].Value}' --filters Name=volume-id,Values=$1 --output table
if [ $? = "1" ] ; then
echo -e "There are no Snapshots available for this EBS Volume, Please Enter to go back"
read input
continue
fi
}
##
### Type of new EBSVolume to be created from Snapshot
function optionForVol() {
echo
echo By default the new ebs volume will be created with standard type and the size will be same as snapshot volume size.
echo If you would like to create the new volume with different Size, Volume type such as gp2, io1 with specific IO input
echo then Please select "N/n" otherwise "Y/y"
echo
read -p "Do you wish to continue with defaults?: Y/N"  CONDITION;
if [[ "$CONDITION" == "Y" || "$CONDITION" == "y" ]]; then
   # do something here!
   createStdVol $userSnapshot
elif [[ "$CONDITION" == "N" || "$CONDITION" == "n" ]]; then
echo
   collectVolInfo
fi
}
##
### Create standard Volume : Need the first argument as SnapshotID
function createStdVol () {
findAZ $userInstanceID
echo Creating new EBS volume ..
NewEBSVol=$(aws ec2 create-volume --availability-zone $AZ --snapshot-id $1 --output text |awk '{ print $7}')
echo
#echo "The New EBS Volume# $NewEBSVol has been created"
echo
log " The New EBS Volume $NewEBSVol has been created from SnapshotID $userSnapshot" 2>&1 | tee -a $logfile
echo
echo "Pleaese Wait... The New EBS Volume# $NewEBSVol is being attached to $HOSTNAME"
sleep 30
echo
attachVol $NewEBSVol
echo
#getDN
#echo $DN
#echo
#aws ec2 attach-volume --volume-id $NewEBSVol --instance-id $userInstanceID --device /dev/$DN 2>&1|tee -a $logfile
echo
#log "The EBS Volume $NewEBSVol has been attached to /dev/$DN on the Instance ID $userInstanceID" 2>&1 | tee -a $logfile
echo
echo
}
##
## Create custome volume using user input
function createCustomeVol () {
findAZ $userInstanceID
echo
if [ $1 = gp2 ]; then
NewEBSVolTypeGp2=$(aws ec2 create-volume --availability-zone $AZ --snapshot-id $userSnapshot --size $2 --volume-type $1 --output text |awk '{ print $8}')
echo
log "The New General Purpose (SSD) EBS Volume# $NewEBSVolTypeGp2 has been created" 2>&1 | tee -a $logfile
echo
echo "Pleaese Wait... The New EBS Volume# $NewEBSVolTypeGp2 is being attached to $HOSTNAME"
sleep 30
echo
attachVol $NewEBSVolTypeGp2
echo
elif [ $1 = st1 ]; then
NewEBSVolTypest1=$(aws ec2 create-volume --availability-zone $AZ --snapshot-id $userSnapshot --size $2 --volume-type $1 --output text |awk '{ print $8}')
echo
log "The New General Purpose (SSD) EBS Volume# $NewEBSVolTypest1 has been created" 2>&1 | tee -a $logfile
echo
echo "Pleaese Wait... The New EBS Volume# $NewEBSVolTypest1 is being attached to $HOSTNAME"
sleep 30
echo
attachVol $NewEBSVolTypest1
echo
else
NewEBSVolTypeIo1=$(aws ec2 create-volume --availability-zone $AZ --snapshot-id $userSnapshot --size $2 --volume-type $1 --iops $3 --output text |awk '{ print $8}')
echo
log "The New Provisioned IOPS (SSD) EBS Volume# $NewEBSVolTypeIo1 has been created" 2>&1 | tee -a $logfile
echo
echo "Pleaese Wait... The New EBS Volume# $NewEBSVolTypeIo1 is being attached to $HOSTNAME"
sleep 30
echo
attachVol $NewEBSVolTypeIo1
echo
fi
}
##
### Collect the new volume info from user
#
function collectVolInfo () {
echo Please enter the size of the volume:
read volSize
log "You have entered The volume size as $volSize GB" 2>&1 | tee -a $logfile
echo
echo
echo Please read below to select one of the Volume Types such io1 or gp2
echo
echo ==================================================================================================================================
echo "Amazon EBS provides the following volume types, which differ in performance characteristics and price."
echo "So that you can tailor your storage performance and cost to the needs of your applications."
echo " The volumes types fall into two categories:"
echo
echo The requested number of I/O operations per second that the volume can support.
echo " io1 -- For Provisioned IOPS (SSD) volumes, you can provision up to 50 IOPS per GiB."
echo " gp2 -- For General Purpose (SSD) volumes, baseline performance is 3 IOPS per GiB, with a minimum of 100 IOPS and a maximum of 10000 IOPS.
              General Purpose (SSD) volumes under 1000 GiB can burst up to 3000 IOPS."
#echo "st1 -- for Throughput Optimized HDD"
echo ==================================================================================================================================
echo
echo Please enter the three digit volume type above that you would like to provision
echo
read volType
echo
log "You have entered Volume Type as $volType" 2>&1 | tee -a $logfile
echo
        if [ "$volType" == "gp2" ]; then
        createCustomeVol gp2 $volSize
#       elif [ "$volType" == "st1" ]; then
#       createCustomeVol st1 $volSize
        elif [ "$volType" == "io1" ]; then
          echo please enter IOPs
echo
read IOPs
echo
log "You have entered the number of IOPS as $IOPs" 2>&1 | tee -a $logfile
echo
createCustomeVol $volType $volSize $IOPs
echo
fi
}
##
###
function userInstance () {
log "===========================================================" >> $logfile
log >> $logfile
echo Please enter your instance ID:
echo
read userInstanceID
echo
log "You have entered the Instance ID as $userInstanceID" 2>&1 | tee -a $logfile
echo
echo "Reading volumes from $userInstanceID, please wait ..... "
echo "======================================================="
echo
queryEBSVol $userInstanceID
echo
echo "Please enter the EBSVolID that you would like to restore"
echo
read userVolume
echo
log "You have requested to restore the EBS Volume $userVolume" 2>&1 | tee -a $logfile
echo
echo "Fetching snapshot list for the volume $userVolume "
echo
querySnapshots $userVolume
echo
echo "Please select the SnapshotID from above table which you would like to restore"
echo
read userSnapshot
echo
log "You have selected the Snapshot ID $userSnapshot" 2>&1 | tee -a $logfile
echo
echo Creating the new Volume from the Snapshot volume $userSnapshot
echo
optionForVol
echo
#newEBSVol
echo done
echo -e "Enter return to continue \c"
read input
}
####
##
### ****  Submenu function  ******
submenu1(){
# clear the screen
#tput clear

# Move cursor to screen location X,Y (top left is 0,0)
tput cup 3 15
while :
do
clear
tput cup 5 17
# Set reverse video mode
tput rev
echo    "Please Provide Instance Details"
tput sgr0

tput cup 7 15
echo -e "\t(1) Please enter '1' to Provide New instance ID "

tput cup 8 15
echo -e "\t(2) Please enter '2' to Create NEW instance"

tput cup 9 15
echo -e "\t(X) Please enter 'X' to go back to Main Menu"

# Set bold mode
tput bold
tput cup 12 15
echo -n "Please enter your choice:"
read Choice
case $Choice in
    "1")
    # Options x and its commands
    userInstance
    ;;
    "2")
    # Options y and its commands
    echo "This option is not available at this point of time" #newInstance
    ;;
    "x"|"X")
    break
    ;;
        *)
        echo "invalid answer, please try again"
        ;;
esac
done
}
####
while :
do
clear
#tput clear

# Move cursor to screen location X,Y (top left is 0,0)
tput cup 3 15
# Set a foreground colour using ANSI escape
tput setaf 3
echo "                       Amazon Web Services             "
tput sgr0

tput cup 5 17
tput rev
#echo "==============================================="
echo "                  EBS Volume Restore  Menu            "
#echo "==============================================="
tput sgr0

tput cup 7 15
echo -e "\t(A) Enter 'A' to Restore EBS Volume on the Current Instance "

tput cup 8 15
echo -e "\t(B) Enter 'B' to Restore EBS Volume on the diffenret Instance "

tput cup 9 15
echo -e "\t(X) Enter 'X' to 'Exit"

echo -e "\n"

# Set bold mode
tput bold
tput cup 12 15
echo -n "Please enter your choice: "
read choice
case $choice in
    "a"|"A")
    restore_ebs
    ;;
    "b"|"B")
    submenu1
    ;;
    "x"|"X")
    exit
    ;;
        *)
        echo "invalid answer, please try again"
        ;;
esac
#echo -e "Enter return to continue \c"
#read input
done
