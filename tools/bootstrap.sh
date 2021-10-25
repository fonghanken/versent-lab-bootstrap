#! /bin/bash
### Input Parameters to select which automation scripts to process #####
## 1. User Name
## 2. Exercise Number
########################################################################
### Import Functions & Variables ###
USER=$1
EXERID=$2
TF_OPT=$3

if [ ${#1} -gt 0 ] && [ ${#1} -ge 11 ]; then
    echo "WARNING: Input a username that is no more than 10 characters!"
    exit
fi
if [[ $(($2)) -ge 1 && $(($2)) -le 6 ]]; then
    echo
else
    echo "WARNING: Input valid Exercise (1 - 6)!"
    exit
fi

echo "This will reset all resources in cluster: $USER-lab"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) echo "*** Yes selected, proceeding with program! ***"; break;;
        No ) echo "*** Exiting program ***"; exit;;
    esac
done

source functions.sh
source vars.properties
f_checkEnvironment

if [ $# -le 1 ]; then
    echo 'WARNING: Please input user and lab number as arguments!'
    exit
fi

### Initializing Directory
mkdir -p $WORK_DIR
cd $WORK_DIR
echo "*************************************"
echo "*** Prepare Lab $EXERID for $USER ***"
echo "*************************************"
f_wait 2 #- Wait for Directory && Variable creation
f_cloneRepo
f_executeTerraform

cd $TF_DIR
TF_RESULTS=$(terraform output eks_nodegroup | grep node_group_name)

if [[ "$TF_RESULTS" == *"eks-$USER-lab-worker"* ]]; then
    echo "================================"
    echo "========== APPLY FLUX =========="
    echo "================================"
    if [ -d $FLUX_DIR ]; then
        kubectl apply -f $FLUX_DIR
        f_wait 180

        if [ "$EXERID" == "4" ]; then
            ### Stop nodes as part of exercise
            source managenode.sh
            ec2Process="stop"
            asgProcess="suspend"
            filterVal="running"

            ### Suspend Launch & Terminate on ASG
            f_modifyASG
            ### Stop EC2 instances
            f_modifyEC2
        fi
        f_scaleDeployment 0
    fi

    echo "***********************************"
    echo "*** Lab $EXERID READY for $USER ***"
    echo "***********************************"
fi