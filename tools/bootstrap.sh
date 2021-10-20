#! /bin/bash
### Input Parameters to select which automation scripts to process #####
## 1. User Name
## 2. Exercise Number
########################################################################
### Import Functions & Variables ###
USER=$1
EXERID=$2
TF_OPT=$3
CLEAR_OPT=$4
if [ ${#1} -ge 11 ]; then
    echo "WARNING: Input a username that is no more than 10 characters!"
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
if [ "$CLEAR_OPT" == "delete" ]; then
    rm -rf $LAB_NAME
fi
if [ -d $LAB_NAME ] && ![ "$CLEAR_OPT" == "continue" ]; then
    echo "WARNING:  An existing cluster or directory for $USER-$EXERID already exist, please ensure to destroy it before continuing!"
    exit
fi

ECHO
ECHO !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
ECHO !! Prepare Exercise $EXERID for $USER !!
ECHO !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
f_wait 2 #- Wait for Directory && Variable creation
f_cloneRepo
f_executeTerraform

ECHO
ECHO !!!!!!!!!!!!!!!!
ECHO !! Apply Flux !!
ECHO !!!!!!!!!!!!!!!!
if [ -d $FLUX_DIR ]; then
    kubectl apply -f $FLUX_DIR
    f_wait 120
    f_scaleDeployment
fi

ECHO
ECHO "************************************"
ECHO "*** Exercise $EXERID READY for $USER ***"
ECHO "************************************"