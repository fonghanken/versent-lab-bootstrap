#! /bin/bash
### Input Parameters to select which automation scripts to process #####
## 1. User Name
## 2. Exercise Number
########################################################################
### Import Functions & Variables ###
USER=$1
EXERID=$2
TF_OPT=$3

if [ ${#1} -ge 11 ]; then
    echo "WARNING: Input a username that is no more than 10 characters!"
    exit
fi
if [[ $(($2)) -ge 1 && $(($2)) -le 6 ]]; then
    echo
else
    echo "WARNING: Input valid Exercise (1 - 6)!"
    exit
fi

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
TF_RESULTS=$(terraform output | grep cluster_name)

if [[ "$TF_RESULTS" == *"$LAB_NAME"* ]]; then
    ECHO
    ECHO !!!!!!!!!!!!!!!!
    ECHO !! Apply Flux !!
    ECHO !!!!!!!!!!!!!!!!
    if [ -d $FLUX_DIR ]; then
        kubectl apply -f $FLUX_DIR
        f_wait 120
        f_scaleDeployment
    fi

    echo "***********************************"
    echo "*** Lab $EXERID READY for $USER ***"
    echo "***********************************"
fi