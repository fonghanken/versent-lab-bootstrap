#! /bin/bash
### Input Parameters to select which automation scripts to process #####
## 1. User Name
## 2. Exercise ID
########################################################################
### Import Functions & Variables ###
USER=$1
EXERID=$2
TF_OPT=$3
CLEAR_OPT=$4
source functions.sh
source vars.properties
f_checkEnvironment

if [ $# -le 1 ]; then
    echo 'Please input user and exercise ID as arguments!'
    exit
fi

### Initializing Directory
if [ "$CLEAR_OPT" == "delete" ]; then
    rm -rf $WORK_DIR
fi
mkdir -p $WORK_DIR
cd $WORK_DIR
if [ -d $LAB_NAME ]; then
    echo "An existing cluster or directory for $USER-$EXERID already exist, please ensure to destroy it before continuing"
    exit
fi

ECHO
ECHO !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
ECHO !!! Preparing Exercise $EXERID for $USER !!!
ECHO !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
f_wait 2 #- Wait for Directory && Variable creation
f_cloneRepo

if [ -d $TF_DIR ]; then
    
    cd $TF_DIR
    terraform init &&
    if [ "$TF_OPT" == "apply" ]; then
        terraform apply && #--auto-approve -lock=false 
        aws eks --region $(terraform output -raw region) update-kubeconfig --name $(terraform output -raw cluster_name) --alias $USER'-exercise'$EXERID
    else
        terraform plan
    fi
fi

ECHO
ECHO !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
ECHO !!! Waiting for flux to deploy resources !!!
ECHO !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
if [ -d $FLUX_DIR ]; then
    kubectl apply -f $FLUX_DIR
    f_wait 60
    f_scaleDeployment
fi

ECHO
ECHO "************************************"
ECHO "*** Exercise $EXERID READY for $USER ***"
ECHO "************************************"