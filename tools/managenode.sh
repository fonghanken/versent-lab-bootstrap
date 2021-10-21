#!/usr/bin/env bash
process=$1
clusterName=$2
if [ "$process" == "start" ]; then
    ec2Process="start"
    asgProcess="resume"
    filterVal="stopped"
else
    ec2Process="stop"
    asgProcess="suspend"
    filterVal="running"
fi

#Obtain ASG names based on tags
declare -a ASG_NAMES=$(aws autoscaling describe-auto-scaling-groups \
        --query "AutoScalingGroups[?Tags[?contains(Key, 'kubernetes.io/cluster/eks-$clusterName') && contains(Value, 'owned')]].[AutoScalingGroupName]" \
        --region ap-southeast-1 --output text) &&
echo "List ASG:"
echo "$ASG_NAMES"
ASG_NAMES_ARRAY=( $ASG_NAMES ) &&
for i in "${ASG_NAMES_ARRAY[@]}"
do
    #Start/Stop suspend-process
    aws autoscaling $asgProcess-processes --auto-scaling-group-name $i --scaling-processes Launch --region ap-southeast-1;
    aws autoscaling $asgProcess-processes --auto-scaling-group-name $i --scaling-processes Terminate --region ap-southeast-1;
done 

if [ ! -z "$ASG_NAMES" ]; then
    #Obtain EC2 instances-id based on tags
    declare -a EC2_IDS=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].{Instance:InstanceId}' \
            --region ap-southeast-1 --filters Name=tag:Name,Values=*$clusterName* Name=instance-state-name,Values=$filterVal  \
            --instance-ids --output text) &&
    echo "List EC2:"
    echo "$EC2_IDS"
    EC2_IDS_ARRAY=( $EC2_IDS ) &&
    for i in "${EC2_IDS_ARRAY[@]}"
    do
        #Start/Stop Ec2 instances
        aws ec2 $ec2Process-instances --instance-ids $i --region ap-southeast-1;
    done
fi