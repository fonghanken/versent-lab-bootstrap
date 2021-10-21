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
    mkdir -p $LAB_DIR
    echo "=================================="
    echo "========== CLONING FLUX =========="
    echo "=================================="
    cd $LAB_DIR
    ### Rename Flux directory - from old to new naming convention
    if [ -d $LAB_DIR/flux ] && [ ! -d $FLUX_DIR ]; then
        echo "Renaming $LAB_DIR/flux to $FLUX_DIR"
        f_wait 2
        mv $LAB_DIR/flux $FLUX_DIR
    fi

    if [ -d $FLUX_DIR ]; then
        cd $FLUX_DIR
        git stash && git pull
    else
        git clone $REPO_LAB_ADD
    fi
    cd $FLUX_DIR
    find flux-deployment.yaml     | xargs sed -i '' -e     's#${versent-lab-exercise}#versent-lab-'$EXERID'#g'
    
    echo "================================"
    echo "========== CLONING TF =========="
    echo "================================"
    cd $LAB_DIR
    ### Rename Terraform directory - from old to new naming convention
    if [ -d $LAB_DIR/terraform ] && [ ! -d $TF_DIR ]; then
        echo "Renaming $LAB_DIR/flux to $TF_DIR"
        f_wait 2
        mv $LAB_DIR/terraform $TF_DIR
    fi

    if [ -d $TF_DIR ]; then
        cd $TF_DIR
        git stash && git pull
    else
        git clone $REPO_TF_ADD
    fi
    cd $TF_DIR
    find variables.tf       | xargs sed -i '' -e     's#${random_string.suffix.result}#'$USER'-lab-'$EXERID'#g'
    find versions.tf       | xargs sed -i '' -e     's#${variable.cluster_name.toreplace}#'$USER'-lab-'$EXERID'#g'
    ### Possible to use TF env var to replace backend config instead
    #export TF_CLI_ARGS_init='-backend-config="bucket=s3-bucket-name"'
    f_wait 3
}

function f_scaleDeployment() {
    kubectl scale deployment/flux -ncicd --replicas=0
}

function f_executeTerraform() {
    echo "================================"
    echo "========== EXECUTE TF =========="
    echo "================================"
    if [ -d $TF_DIR ]; then
        cd $TF_DIR
        terraform init &&
        if [ "$TF_OPT" == "plan" ]; then
            terraform plan -lock=false
        elif [ "$TF_OPT" == "destroy" ]; then
            terraform destroy --auto-approve
        else
            terraform apply --auto-approve -lock=false &&
            aws eks --region $(terraform output -raw region) update-kubeconfig --name $(terraform output -raw cluster_name) --alias $USER'-exercise'$EXERID
        fi
    fi
}