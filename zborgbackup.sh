#!/bin/bash

# Usage: start-borgbackup.sh <path> <backup_repository> <backup_name> <rclone_destination>

# Prechecks

if [[ $(id -u) != 0 ]]; then
    printf "ERROR: Must be run as root\n\n"
    exit 1
fi

if [[ $# == 3 ]]; then
    rclone_destination=''
elif [[ $# == 4 ]]; then
    rclone_destination=$4
else
    #todo: usage
    exit 1
fi

path=$1
backup_repository=$2
backup_name=$3
export BORG_REPO=$backup_repository
export BORG_PASSPHRASE='CHANGE_ME'

printf "Backing up:\t\t%s\n" $path
printf "Using repository:\t%s\n" $backup_repository
printf "Backup name:\t\t%s\n" $backup_name
printf "Password from:\t\t%s\n" $password_path
[[ -n $rclone_destination ]] && printf "Cloud repository:\t%s\n" $rclone_destination

#todo: use backup name for pruning olg backups
#todo: check if the path to bakcup exist
#todo: check if repository exist
#todo: add cleanup if job failed (snapshot removal etc)

zfs_datasets_list=$(zfs list -pH -o name,mountpoint | awk '$2 != "legacy" {print $0}')

zfs_dataset=''
IFS=$'\n'
for ds in ${zfs_datasets_list}
do
    if [[ $path = $(awk ' {print $2} ' <<< $ds)* ]]; then
        zfs_dataset=$(awk ' {print $1} ' <<< $ds)
    fi
done

# create snapshot if the data is located on a ZFS dataset
if [[ -n $zfs_dataset ]]; then
    zfs_snapshot_name="borg_backup_$(uuidgen)"
    printf "ZFS dataset:\t\t%s\n" $zfs_dataset
    printf "ZFS snapshot name:\t%s\n" $zfs_snapshot_name
    printf "\n%s - Creating snapshot %s on dataset %s\n" "$(date)" $zfs_snapshot_name $zfs_dataset
    zfs snapshot "${zfs_dataset}@${zfs_snapshot_name}"
    # todo: stop on error
    # todo: use in the path to check a mountpoint from zfs list -o mountpoint $dataset_to_snapshot
    zfs_dataset_mountpoint=$(zfs list -o mountpoint -pH ${zfs_dataset})
    while [ ! -d "${zfs_dataset_mountpoint}/.zfs/snapshot/${zfs_snapshot_name}" ]; do sleep 5; done
    printf "\n%s - Snapshot created\n" "$(date)"
    # mounting snapshot
    path_mount="/run/borg_zfs_backup/${zfs_dataset}"
    mkdir -p $path_mount
    #todo: use path from zfs list
    mount --bind "${zfs_dataset_mountpoint}/.zfs/snapshot/${zfs_snapshot_name}" $path_mount
    sub_path=$(awk -F${zfs_dataset} '{print $2}'<<<$path)
    backup_path="${path_mount}${sub_path}"
    printf "\n%s - Backing up data from mounted ZFS snapshot %s\n" "$(date)" $backup_path
else
    backup_path=${path}
    printf "\n%s - Backing up data from %s\n" "$(date)" ${backup_path}
fi

# create a backup of the snapshot
printf "\n%s - Backing up %s to %s\n\n" "$(date)" $path $backup_repository
borg create --verbose --filter AME --list --stats --show-rc --compression lz4 --exclude-caches ::"{hostname}-{now}-${backup_name}" $backup_path
status_backup=$?

# unmounting the snapshot and destroing it
if [[ -n $zfs_dataset ]]; then
    umount $path_mount
    printf "\n%s - Removing snapshot %s@%s\n\n" "$(date)" "${zfs_dataset}" "${zfs_snapshot_name}"
    zfs destroy "${zfs_dataset}@${zfs_snapshot_name}"
fi

printf "\n%s - Pruning repository %s\n\n" "$(date)" $backup_repository
borg prune --list --glob-archives "{hostname}-*-${backup_name}" --show-rc --keep-hourly 4 --keep-daily 7 --keep-weekly 4 --keep-monthly 6
status_prune=$?

printf "\n%s - Compacting repository %s\n\n" "$(date)" $backup_repository
borg compact
status_compact=$?

#cloning repository to cloud
if [[ -n $rclone_destination ]]; then
    printf "\n%s - Replicating repository to cloud\n\n" "$(date)"
    rclone sync $backup_repository $rclone_destination -v
fi
