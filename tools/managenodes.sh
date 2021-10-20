#!/usr/bin/env bash
ec2Process=$1
ec2Tag=$2
#Obtain Ec2 instances-id based on tags

if [ "$ec2Process" == "start" ]; then
    filterVal="stopped"
else
    ec2Process="stop"
    filterVal="running"
fi
declare -a EC2_IDS=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].{Instance:InstanceId}' \
        --region ap-southeast-1 --filters Name=tag:Name,Values=*$ec2Tag* Name=instance-state-name,Values=$filterVal  \
        --instance-ids --output text) &&
echo "List EC2: $EC2_IDS"
EC2_IDS_ARRAY=( $EC2_IDS ) &&
for i in "${EC2_IDS_ARRAY[@]}"
do
    #Start/Stop Ec2 instances
    aws ec2 $ec2Process-instances --instance-ids $i --region ap-southeast-1;
done 