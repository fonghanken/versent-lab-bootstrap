#!/bin/bash
function f_randomString() {
     cat /dev/urandom | env LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1
}

function f_setupEnvProps() {
    awk -F= '$2' $1 | grep -v ^'#'| sed -E -n 's/[^#]+/export &/ p' > /tmp/varProps &&
    source /tmp/varProps &&
    rm -rf /tmp/varProps
}

function f_wait() {
    delayInSeconds=$1
    for (( i=delayInSeconds;i>=0;i-- )) ; do
        sleep 1
        printf "\rPlease wait... Ready in $i seconds "
    done
    printf "\rWait completed - $delayInSeconds seconds              "
    printf "\n"
}

function f_checkEnvironment() {
    if ! terraform --help &> /dev/null; then
        echo "Please install Terraform first before running the bootstrap scripts"
        exit
    else
        echo "Terraform Installed"
    fi

    if ! git --help &> /dev/null; then
        echo "Please install Git first before running the bootstrap scripts"
        exit
    else
        echo "Git Installed"
    fi

    if ! command -v aws &> /dev/null; then
        echo "Please install aws CLI - https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html"
        exit
    else
        echo "AWS CLI Installed"
    fi

    if ! command -v stax2aws &> /dev/null; then
        echo "Please install stax CLI - https://www.stax.io/developer/aws-access-cli/getting-started-with-stax2aws/"
        exit
    else
        echo "STAX CLI Installed"
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        echo "Please sign-in to AWS first before running the bootstrap scripts"
        exit
    else
        echo "AWS Signed-in"
    fi
}

function f_cloneRepo() {
     
    echo "=================================="
    echo "========== CLONING FLUX =========="
    echo "=================================="
    if [ -d $LAB_DIR ]; then
        cd $LAB_DIR
        git stash && git pull
    else
        mkdir -p $LAB_DIR
        cd $LAB_DIR && git clone $REPO_LAB_ADD .
    fi
    find flux-deployment.yaml     | xargs sed -i '' -e     's#${versent-lab-exercise}#versent-lab-'$EXERID'#g'
    if [ -d $FLUX_DIR ]; then
        f_resetCluster
        f_wait 60
        rm -R $FLUX_DIR/*
    else
        mkdir -p $FLUX_DIR
    fi
    cp -Rf $LAB_DIR/* $FLUX_DIR/

    echo "================================"
    echo "========== CLONING TF =========="
    echo "================================"
    if [ -d $TF_DIR ]; then
        cd $TF_DIR
        git stash && git pull
    else
        mkdir -p $TF_DIR
        cd $TF_DIR && git clone $REPO_TF_ADD .
    fi
    find variables.tf       | xargs sed -i '' -e     's#${random_string.suffix.result}#'$USER'-lab#g'
    find versions.tf        | xargs sed -i '' -e     's#${variable.cluster_name.toreplace}#'$USER'-lab#g'
    ### Possible to use TF env var to replace backend config instead
    #export TF_CLI_ARGS_init='-backend-config="bucket=s3-bucket-name"'
    f_wait 3
}

function f_scaleDeployment() {
    kubectl scale deployment/flux -ncicd --replicas=$1
}

function f_resetCluster() {
    kubectl config use-context "$USER-lab"
    kubectl delete -f $FLUX_DIR
    declare -a NS_NAMES=$(kubectl get namespaces -A | egrep -Ev "kube-|cert-manager|calico-|tigera-" | awk 'NR!=1 { print $1 }')
    echo -n "List NS: "
    echo "$NS_NAMES" | wc -l | xargs
    NS_NAMES_ARRAY=( $NS_NAMES ) &&
    for i in "${NS_NAMES_ARRAY[@]}"
    do
        kubectl delete all --all -n $i
    done 
}

function f_executeTerraform() {
    echo "================================"
    echo "========== EXECUTE TF =========="
    echo "================================"
    if [ -d $TF_DIR ]; then
        cd $TF_DIR
        terraform init &&
        if [ "$TF_OPT" == "plan" ]; then
            terraform plan
        elif [ "$TF_OPT" == "destroy" ]; then
            terraform destroy --auto-approve
        else
            terraform apply --auto-approve &&
            aws eks --region $(terraform output -raw region) update-kubeconfig --name $(terraform output -raw cluster_name) --alias $USER'-lab'
        fi
    fi
}

function f_modifyASG() {
    #Obtain ASG names based on tags
    declare -a ASG_NAMES=$(aws autoscaling describe-auto-scaling-groups \
            --query "AutoScalingGroups[?Tags[?contains(Key, 'kubernetes.io/cluster/eks-$clusterName') && contains(Value, 'owned')]].[AutoScalingGroupName]" \
            --region ap-southeast-1 --output text) &&
    echo -n "List ASG: "
    echo "$ASG_NAMES" | wc -l | xargs
    ASG_NAMES_ARRAY=( $ASG_NAMES ) &&
    for i in "${ASG_NAMES_ARRAY[@]}"
    do
        #Start/Stop suspend-process
        aws autoscaling $asgProcess-processes --auto-scaling-group-name $i --scaling-processes Launch --region ap-southeast-1;
        aws autoscaling $asgProcess-processes --auto-scaling-group-name $i --scaling-processes Terminate --region ap-southeast-1;
    done 
}

function f_modifyEC2() {
    #Obtain EC2 instances-id based on tags
    declare -a EC2_IDS=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].{Instance:InstanceId}' \
            --region ap-southeast-1 --filters Name=tag:Name,Values=*$clusterName* Name=instance-state-name,Values=$filterVal  \
            --instance-ids --output text) &&
    echo -n "List EC2: "
    echo "$EC2_IDS" | wc -l | xargs
    EC2_IDS_ARRAY=( $EC2_IDS ) &&
    for i in "${EC2_IDS_ARRAY[@]}"
    do
        #Start/Stop Ec2 instances
        aws ec2 $ec2Process-instances --instance-ids $i --region ap-southeast-1;
    done
}

function f_configLab() {
    if [ "$EXERID" == "5" ]; then
        ### Stop nodes as part of exercise
        ec2Process="stop"
        asgProcess="suspend"
        filterVal="running"

        ### Suspend Launch & Terminate on ASG
        f_modifyASG
        ### Stop EC2 instances
        f_modifyEC2
    elif [ "$EXERID" == "4" ]; then
        NODENAME1=$(kubectl get nodes --show-labels | grep role=worker | awk 'NR==1 { print $1 }') &&
        NODENAME2=$(kubectl get nodes --show-labels | grep role=worker | awk 'NR==1 { print $1 }')
        kubectl taint nodes $NODENAME1 special=true:NoSchedule
        kubectl taint nodes $NODENAME2 isolation=true:NoSchedule
    fi
}