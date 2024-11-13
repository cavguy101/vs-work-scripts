################################################################################
# getAllInstances.sh
# Get a list of all compute instances used in OCI tenancy
# 13-NOV-2024  vseeram  Created
################################################################################
#!/bin/bash


################################################################################
# print header
################################################################################
function print_header() {
    echo ""
    echo "################################################################################"
    echo "# Listing all $1"
    echo "################################################################################"
}


################################################################################
# get all compartments into array
################################################################################
function get_compartments() {
    compartment_arr=$( oci iam compartment list --compartment-id-in-subtree true --all | jq -r '.[] | map(.) | .[] | .name, .id' )
}


################################################################################
# list volumes for all compartments
################################################################################
function list_instances() {
    print_header "$1"
    for compartment_id in $compartment_arr; do
        if [[ $compartment_id != "oci"* ]]; then
            echo "Listing $1 for compartment: $compartment_id"
        else
            oci compute instance list --compartment-id list --all --compartment-id $compartment_id --query "data[*].{Name:\"display-name\",ID:id,OCPUs:\"shape-config\".ocpus,Memory:\"shape-config\".\"memory-in-gbs\",CreatedBy:\"defined-tags\".\"Oracle-Tags\".CreatedBy,TimeCreated:\"time-created\"}"  --output table
        fi
    done
}


get_compartments
list_instances "compute instances"

