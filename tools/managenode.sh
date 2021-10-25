#!/usr/bin/env bash
process=$1
clusterName=$2
source functions.sh

if [ "$process" == "start" ]; then
    ec2Process="start"
    asgProcess="resume"
    filterVal="stopped"

    ### Start EC2 instances
    f_modifyEC2
    ### Resume EC2 instances
    #f_modifyASG
elif [ "$process" == "stop" ]; then
    ec2Process="stop"
    asgProcess="suspend"
    filterVal="running"

    ### Suspend Launch & Terminate on ASG
    f_modifyASG
    ### Stop EC2 instances
    f_modifyEC2
else
    echo "WARNING: Input a valid process (stop/start)!"
fi