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
    if ! command -v terraform &> /dev/null; then
        echo "Please install Terraform first before running the bootstrap scripts"
        exit
    else
        echo "Terraform Installed"
    fi

    if ! command -v git &> /dev/null; then
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
    find flux-deployment.yaml     | xargs sed -i '' -e     's#${versent-lab-exercise}#'$EXER_TYPE'/lab-'$EXERID'#g'

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
}

function f_scaleDeployment() {
    kubectl scale deployment/flux -ncicd --replicas=$1
    kubectl scale deployment/memcached -ncicd --replicas=$1
}

function f_resetCluster() {
    echo "==================="
    echo "=== DISARM FLUX ==="
    echo "==================="
    kubectl config use-context "eks-$USER-lab"
    kubectl delete -f $FLUX_DIR
    f_wait 3
    echo "=================="
    echo "=== DELETE RSS ==="
    echo "=================="
    kubectl delete networkpolicy --all
    # kubectl delete ns tigera-operator
    # kubectl delete ns calico-system
    kubectl delete ns cert-manager
    declare -a NS_NAMES=$(kubectl get namespaces -A | egrep -Ev "kube-|tigera-|calico-|cert-manager" | awk 'NR!=1 { print $1 }') &&
    echo -n "List NS: "
    NS_ARRAY=( $NS_NAMES )
    echo "${#NS_ARRAY[@]}"
    for i in "${NS_ARRAY[@]}"
    do
        if [ "$i" == "default" ]; then
            kubectl delete all --all -n $i
        else
            kubectl delete ns $i
        fi
    done

    ### Delete all namespaced resources
    f_deleteK8sRss "true"

    ### Delete non namespaced resources
    f_deleteK8sRss "false"
}

function f_deleteK8sRss() {
    nsFlag=$1
    declare -a apiRss=$(kubectl api-resources --namespaced=$nsFlag --verbs=delete -o name)
    API_ARRAY=( "$apiRss" )
    if [ "$nsFlag" == "false" ]; then
        API_ARRAY=$(echo "$API_ARRAY" | egrep -E "persistentvolumes|podsecuritypolicies|clusterrolebindings|clusterroles|volumeattachments")
    fi

    for i in "${API_ARRAY[@]}"
    do
        RSS=$i
        if [ "$1" == "true" ]; then
            declare -a RSS_NAMES=$(kubectl get $RSS -A | egrep -Ev "kube|aws|tigera-|calico-|cert-manager" | awk 'NR!=1 { print $2 }')
        else
            declare -a RSS_NAMES=$(kubectl get $RSS -A | egrep -Ev "kube|aws|system:|eks:|admin|vpc|edit|view|tigera-|calico-|cert-manager" \
                | awk 'NR!=1 { print $1 }')
        fi
        echo -n "List $RSS: "
        RSS_ARRAY=( $RSS_NAMES )
        echo "${#RSS_ARRAY[@]}"
        for j in "${RSS_ARRAY[@]}"
        do
            kubectl delete $RSS $j
        done
    done;

   
}

function f_executeCreation() {
    echo "================================"
    echo "========== EXECUTE TF =========="
    echo "================================"
    if [ -d $TF_DIR ]; then
        cd $TF_DIR
        terraform init &&
        if [ "$TF_OPT" == "plan" ]; then
            terraform plan
        elif [ "$TF_OPT" == "destroy" ]; then
            asgProcess="resume"
            f_modifyASG
            terraform destroy --auto-approve
        else
            terraform apply --auto-approve &&
            aws eks --region $(terraform output -raw region) update-kubeconfig --name $(terraform output -raw cluster_name) --alias 'eks-'$USER'-lab'
        fi
    fi

    echo "================================"
    echo "========== CONFIGFLUX =========="
    echo "================================"
    if [ -d $FLUX_DIR ]; then
        f_resetCluster
        f_wait 60
        rm -R $FLUX_DIR/*
    else
        mkdir -p $FLUX_DIR
    fi
    cp -Rf $LAB_DIR/* $FLUX_DIR/
}

function f_modifyASG() {
    #Obtain ASG names based on tags
    declare -a ASG_NAMES=$(aws autoscaling describe-auto-scaling-groups \
            --query "AutoScalingGroups[?Tags[?contains(Key, '$clusterName') && contains(Value, 'owned')]].[AutoScalingGroupName]" \
            --region ap-southeast-1 --output text) &&
    echo -n "List ASG: "
    ASG_NAMES_ARRAY=( $ASG_NAMES )
    echo "${#ASG_NAMES_ARRAY[@]}"
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
    EC2_IDS_ARRAY=( $EC2_IDS )
    echo "${#EC2_IDS_ARRAY[@]}"
    for i in "${EC2_IDS_ARRAY[@]}"
    do
        #Start/Stop Ec2 instances
        aws ec2 $ec2Process-instances --instance-ids $i --region ap-southeast-1;
    done
}

function f_configLab() {
    echo "================================"
    echo "========== CONFIG LAB =========="
    echo "================================"
    if [ "$EXERID" == "5" ]; then
        NODEINFRA1=$(kubectl get nodes --show-labels | grep role=infra | awk 'NR==1 { print $1 }')
        kubectl drain $NODEINFRA1 --ignore-daemonsets --delete-emptydir-data

        ### Stop nodes as part of exercise
        ec2Process="stop"
        asgProcess="suspend"
        filterVal="running"
        clusterName="$USER-lab"
        ### Suspend Launch & Terminate on ASG
        f_modifyASG
        ### Stop EC2 instances
        f_modifyEC2
    elif [ "$EXERID" == "4" ]; then
        NODEWORK1=$(kubectl get nodes --show-labels | grep role=worker | awk 'NR==1 { print $1 }')
        NODEWORK2=$(kubectl get nodes --show-labels | grep role=worker | awk 'NR==2 { print $1 }')
        NODEINFRA1=$(kubectl get nodes --show-labels | grep role=infra | awk 'NR==1 { print $1 }')
        kubectl taint node $NODEWORK1 special=true:NoSchedule
        kubectl taint node $NODEWORK2 special=true:NoExecute
        kubectl taint node $NODEINFRA1 isolation=true:NoExecute
        kubectl drain $NODEINFRA1 --ignore-daemonsets --delete-emptydir-data
        kubectl drain $NODEWORK1 --ignore-daemonsets --delete-emptydir-data
    fi
}