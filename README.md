# Borg Backup Helper
Bash script to create ZFS aware backups

If the backup object is located in a zfs filesystem the script will create a zfs snapshot, mount it, and backup the snapshot. This will guarantee consistency of the backed up files.

Usage
```
zborgbackup.sh {path_to_backup} {path_to_borg_repo} {backup_name} {rclone_remote_path}
```
`{path_to_backup}` - path that will be backed up

`{path_to_borg_repo}` - borg backup repository

`{backup_name}` - backup name

`{rclone_remote_path}` - optional, path in rclone remote where the borg backup repository will be replicated

# Example
```
/opt/scripts/zborgbackup.sh /share/docker /backup/0_backup_repository/borg_local docker yandex:/0_backup_repository/borg_local  
/opt/scripts/zborgbackup.sh /share/docker/0_traefik ssh://example.com:8090/opt/1_backup_repository/borg_docker traefik
```
# ToDo
- Store the password of the borg backup repo in an encrypted file

