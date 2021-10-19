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
    ECHO
    ECHO !!!!!!!!!!!!!!!!!!
    ECHO !! CLONING FLUX !!
    ECHO !!!!!!!!!!!!!!!!!!
    mkdir -p $LAB_DIR/flux
    cd $LAB_DIR/flux
    git clone $REPO_LAB_ADD .
    find flux-deployment.yaml     | xargs sed -i '' -e     's#${versent-lab-exercise}#versent-lab-exercise'$EXERID'#g'

    ECHO
    ECHO !!!!!!!!!!!!!!!!
    ECHO !! CLONING TF !!
    ECHO !!!!!!!!!!!!!!!!
    mkdir -p $LAB_DIR/terraform
    cd $LAB_DIR/terraform
    git clone $REPO_TF_ADD .
    find variables.tf       | xargs sed -i '' -e     's#${random_string.suffix.result}#'$USER'-exercise'$EXERID'#g'

    f_wait 3
}

function f_scaleDeployment() {
    kubectl scale deployment/flux -ncicd --replicas=0
}

function f_executeTerraform() {
    ECHO
    ECHO !!!!!!!!!!!!!!!!
    ECHO !! EXECUTE TF !!
    ECHO !!!!!!!!!!!!!!!!
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
}