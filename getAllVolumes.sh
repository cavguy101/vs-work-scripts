################################################################################
# getAllVolumes.sh
# Get a list of all block volumes used in OCI instance
# 12-NOV-2024  vseeram  Created
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
function list_volumes() {
    print_header "$2"
    for compartment_id in $compartment_arr; do
        if [[ $compartment_id != "oci"* ]]; then
            echo "Listing $2 for compartment: $compartment_id"
        else
            oci bv $1 list --all --compartment-id $compartment_id --query "data[*].{Name:\"display-name\",ID:id,Size:\"size-in-gbs\",TimeCreated:\"time-created\"}" --output table
        fi
    done
}


get_compartments

list_volumes volume "block volumes"
list_volumes backup "block volume backups"
list_volumes block-volume-replica "boot volume replicas"
list_volumes boot-volume "boot volumes"
list_volumes boot-volume-backup "boot volume backups"
list_volumes boot-volume-replica "boot volume replicas"
list_volumes volume-backup-policy "block volume backup policies"
list_volumes volume-group "block volume groups"
list_volumes volume-group-backup "block volume group backups"
