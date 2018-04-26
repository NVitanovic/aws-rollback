#!/bin/bash

# MIT License
#
# Copyright (c) 2018 Nikola Vitanović
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# stop_instance(instance_id)
function stop_instance()
{
        INSTANCE_ID=$1
        # Stopping instance
        echo -e "INFO: Stopping instance $INSTANCE_ID"
        DATA=`aws ec2 stop-instances --instance-id $INSTANCE_ID`
        RES=$?
        if [ $RES != 0 ]
        then
                echo "ERROR: Could not stop instance $INSTANCE_ID"
                exit 1
        fi
        return 0
}
# wait_for_instance_state(instance_id, state, timeout)
function wait_for_instance_state()
{
        INSTANCE_ID=$1
        STATE=$2
        TIMEOUT=$3
        #Wait for INSTANCE to go to STATE
        TIMER=0
        while : ; do
                DATA=`aws ec2 describe-instances --instance-ids $INSTANCE_ID | grep -m1 STATE | awk '{print $3}'`
                if [ "$DATA" == "$STATE" ]
                then
                        break
                fi
                if [ $TIMER -ge $TIMEOUT ]
                then
                        echo "ERROR: Timed out while waiting for instance $INSTANCE_ID to transition to state $STATE"
                        exit 1
                fi
                sleep 1
                TIMER=$((TIMER+1))
                #echo "Waiting... $TIMER"
        done
        return 0
}
# wait_for_volume_state(instance_id, state, timeout)
function wait_for_volume_state()
{
        VOLUME_ID=$1
        STATE=$2
        TIMEOUT=$3
        #Wait for VOLUME to go to STATE
        TIMER=0
        while : ; do
                DATA=`aws ec2 describe-volumes --volume-ids $VOLUME_ID | awk '{print $7}'`
                #Sometimes it's in 8th position
                DATA2=`aws ec2 describe-volumes --volume-ids $VOLUME_ID | awk '{print $8}'`
                if [ "$DATA" == "$STATE" ] || [ "$DATA2" == "$STATE" ]
                then
                        break
                fi
                if [ $TIMER -ge $TIMEOUT ]
                then
                        echo "ERROR: Timed out while waiting for volume $VOLUME_ID to be in state $STATE"
                        exit 1
                fi
                sleep 1
                TIMER=$((TIMER+1))
                #echo "Waiting... $TIMER"
        done
        return 0
}
# create_new_volume(snapshot_id, availability_zone) : NEW_VOLUME_ID
function create_new_volume()
{
        SNAPSHOT_ID=$1
        AVAILABILITY_ZONE=$2
        # Create a new volume from snapshot
        echo "INFO: Creating new volume from snapshot $SNAPSHOT_ID in $AVAILABILITY_ZONE"
        DATA=`aws ec2 create-volume --snapshot-id $SNAPSHOT_ID --availability-zone $AVAILABILITY_ZONE`
        RES=$?
        if [ $RES != 0 ]
        then
                echo "ERROR: Could not create new volume from $SNAPSHOT_ID in $AVAILABILITY_ZONE"
                exit 2
        fi

        NEW_VOLUME_ID=`echo $DATA | awk '{print $7'}`
        return 0
}
# detach_volume(instance_id, old_volume_id)
function detach_volume()
{
        INSTANCE_ID=$1
        OLD_VOLUME_ID=$2
        if [ -z "$OLD_VOLUME_ID" ]
        then
                echo "WARNING: Old volume empty or not specified on detach_volume() skiping detach"
                return 3
        fi
        # Detach old volume from instance
        echo "INFO: Detaching old volume $OLD_VOLUME_ID from instance $INSTANCE_ID"
        DATA=`aws ec2 detach-volume --volume-id $OLD_VOLUME_ID`
        RES=$?
        if [ $RES != 0 ]
        then
                echo "ERROR: Could not detach volume $OLD_VOLUME_ID from instance $INSTANCE_ID"
                exit 3
        fi
        return 0
}
# attach_new_volume(instance_id,new_volume_id,device)
function attach_new_volume()
{
        INSTANCE_ID=$1
        NEW_VOLUME_ID=$2
        OLD_MOUNT_DEVICE=$3
        # Attach a new volume on instance
        echo "INFO: Attaching new volume $NEW_VOLUME_ID to instance $INSTANCE_ID"
        DATA=`aws ec2 attach-volume --device $OLD_MOUNT_DEVICE --instance-id $INSTANCE_ID --volume-id $NEW_VOLUME_ID`
        RES=$?
        if [ $RES != 0 ]
        then
                echo "ERROR: Could not attach volume $NEW_VOLUME_ID to instance $INSTANCE_ID"
                exit 4
        fi
        return 0
}

# start_instance(instance_id)
function start_instance()
{
        INSTANCE_ID=$1
        # Start instance
        echo "INFO: Starting instance $INSTANCE_ID"
        DATA=`aws ec2 start-instances --instance-id $INSTANCE_ID`
        RES=$?
        if [ $RES != 0 ]
        then
                echo "ERROR: Could not start instance $INSTANCE_ID"
                exit 5
        fi
        return 0
}
# delete_old_volume(old_volume_id)
function delete_old_volume()
{
        OLD_VOLUME_ID=$1
        # Delete old volume
        echo "INFO: Deleting old volume $OLD_VOLUME_ID"
        DATA=`aws ec2 delete-volume --volume-id $OLD_VOLUME_ID`
        RES=$?
        if [ $RES != 0 ]
        then
                echo "ERROR: Could not delete old volume $OLD_VOLUME_ID"
                exit 6
        fi
        return 0
}

# Not enough parameters show usage and exit
if [ $# -lt 3 ]
then
        echo
        echo "Usage:"
        echo "aws-rollback.sh <server_list_file> <region_id> <availability_zone> [timeout]"
        echo
        echo "server_list_file"
        echo "  Should containt list of EC2 instances with their devices and snapshots"
        echo "      Example:"
        echo "              i-1234 /dev/sda1 snap-hsbab12hg3"
        echo "              i-3456 /dev/sda  snap-snaphostforSDA"
        echo "              i-3456 /dev/sdb  snap-snapshotforSDB"
        echo "  As you can see from the example you can have multiple disks for same instance,"
        echo "  you just specify the same instance id and then snapshot."
        echo
        echo "Example:"
        echo "       aws-rollback.sh servers.txt sa-east-1 sa-east-1a"
        echo
        exit 1
fi

# main()
_FILE="$1"
_REGION_ID="$2"
_AVAILABILITY_ZONE="$3"

if [ -z "$4" ]
then
        _TIMEOUT=120
else
        _TIMEOUT="$4"
fi

# Stop all instances first
while read line
do
        _INSTANCE_ID=`echo $line | awk '{print $1}'`
        stop_instance $_INSTANCE_ID
        wait_for_instance_state $_INSTANCE_ID "stopped" $_TIMEOUT
done < $_FILE

while read line
do
        _INSTANCE_ID=`echo $line | awk '{print $1}'`
        _DEVICE_ID=`echo $line | awk '{print $2}'`
        _SNAPSHOT_ID=`echo $line | awk '{print $3}'`
        
        #echo "File: $_INSTANCE_ID $_DEVICE_ID $_SNAPSHOT_ID"
        
        INSTANCE_INFO=`aws ec2 describe-volumes | grep $_INSTANCE_ID | grep $_DEVICE_ID`
        _OLD_MOUNT_DEVICE=`echo $INSTANCE_INFO | awk '{print $4'}`
        _OLD_VOLUME_ID=`echo $INSTANCE_INFO | awk '{print $7'}`
        
        #echo "Old: $_OLD_MOUNT_DEVICE $_OLD_VOLUME_ID"

        # Detach and delete will only happen if volume id is not empty so we 
        # need to check if there was an error while detaching the volume 
        # before waiting for status.

        detach_volume $_INSTANCE_ID $_OLD_VOLUME_ID
        if [ $? == 0 ]
        then
                wait_for_volume_state $_OLD_VOLUME_ID "available" $_TIMEOUT
                delete_old_volume $_OLD_VOLUME_ID
        fi

        create_new_volume $_SNAPSHOT_ID $_AVAILABILITY_ZONE
        wait_for_volume_state $NEW_VOLUME_ID "available" $_TIMEOUT

        attach_new_volume $_INSTANCE_ID $NEW_VOLUME_ID $_DEVICE_ID
done < $_FILE

# Start all instances now one by one
while read line
do
        _INSTANCE_ID=`echo $line | awk '{print $1}'`
        start_instance $_INSTANCE_ID
        wait_for_instance_state $_INSTANCE_ID "running" $_TIMEOUT
        echo "INFO: Instance $_INSTANCE_ID restored to snapshot $_SNAPSHOT_ID"
done < $_FILE