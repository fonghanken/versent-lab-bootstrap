#! /bin/bash
### Input Parameters to select which automation scripts to process #####
## 1. User Name
## 2. Exercise Number
########################################################################
### Import Functions & Variables ###
USER=$1
EXERID=$2
TF_OPT=$3
EXER_TYPE=$4

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

if [ ${#4} -ge 1 ]; then
    if [[ ! "$4" == "question" ]] && [[ ! "$4" == "answer" ]]; then
        echo "WARNING: Input a valid Exercise Type (question/answer)!"
        exit
    fi
else
    EXER_TYPE="question"
fi

### Initializing Directory
mkdir -p $WORK_DIR
cd $WORK_DIR
echo "*************************************"
echo "*** Prepare Lab $EXERID for $USER ***"
echo "*************************************"
f_wait 2 #- Wait for Directory && Variable creation
f_cloneRepo
f_executeCreation

cd $TF_DIR
TF_RESULTS=$(terraform output eks_nodegroup | grep node_group_name)

if [[ "$TF_RESULTS" == *"eks-$USER-lab-worker"* ]]; then
    echo "================================"
    echo "========== START NODE =========="
    echo "================================"
    ec2Process="start"
    asgProcess="resume"
    filterVal="stopped"
    clusterName="$USER-lab"

    ### Start EC2 instances
    f_modifyEC2
    echo "*** Please wait for 1min for Nodes to startup ***"
    f_wait 60
    echo "================================"
    echo "========== APPLY FLUX =========="
    echo "================================"
    if [ -d $FLUX_DIR ]; then
        kubectl apply -f $FLUX_DIR
        echo "*** Please wait for 4mins for Flux to complete deployment ***"
        if [[ "$4" == "question" ]]; then
            f_wait 240
            f_configLab
            f_scaleDeployment 0
        fi
    fi

    echo "***********************************"
    echo "*** Lab $EXERID READY for $USER ***"
    echo "***********************************"
fi