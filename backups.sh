#!/usr/bin/env bash
#
#Copyright (C) 2021 xhlgr
#Change to use 7z, should be download it before use.Encrypt by 7z.
#Change put zip file to dir:backup_date, and copy to Remote Drive
#Add delete local dir function.
#Delete FTP function.
#
# Copyright (C) 2013 - 2020 Teddysun
# Description:      Auto backup shell script
# You must to modify the config before run it!!!
# Backup MySQL/MariaDB datebases, files and directories
# Auto transfer backup file to Remote Drive (need install rclone command) (option)
# Auto delete Remote Drive's server's remote file (option)

[[ $EUID -ne 0 ]] && echo "Error: This script must be run as root!" && exit 1

########## START OF CONFIG ##########

# Encrypt flag (true: encrypt, false: not encrypt)
ENCRYPTFLG=false

# WARNING: KEEP THE PASSWORD SAFE!!!
# The password used to encrypt the backup
# To decrypt backups made by this script, run the following command: 
# 7z a -r -p${BACKUPPASS} ${TARFILE} ${BACKUP[@]}
BACKUPPASS="888"

# Directory to store backups (NO USE in this)
LOCALDIR="/var/www/fastuser/data/www/zbackup/backups/"

# Temporary directory used during backup creation
TEMPDIR="/var/www/fastuser/data/www/zbackup/temp/"

# File to log the outcome of backups
LOGFILE="/var/www/fastuser/data/www/zbackup/log/backups.log"

# OPTIONAL:
# If you want to backup the MySQL database, enter the MySQL root password below, otherwise leave it blank
MYSQL_ROOT_PASSWORD="888"

# Below is a list of MySQL database name that will be backed up
# If you want backup ALL databases, leave it blank.
MYSQL_DATABASE_NAME[0]="wybustop_test"

# Below is a list of files and directories that will be backed up in the tar backup
# For example:
# File: /data/www/default/test.tgz
# Directory: /data/www/default/test
BACKUP[0]="/var/www/fastuser/data/www/test.wybus.top"

# Number of days to store daily local backups (default 7 days)
LOCALAGEDAILIES="7"

# Delete remote file from Remote Drive or FTP server flag (true: delete, false: not delete)
DELETE_REMOTE_FILE_FLG=true

# Delete local dir flag(true: delete, false: not delete)(local dir in TEMPDIR not LOCALDIR)
DELETE_LOCAL_FILE_FLG=true

# Rclone remote name
RCLONE_NAME="wybus"

# Rclone remote folder name (default "")
RCLONE_FOLDER="vpsbackups"

########## END OF CONFIG ##########

# Date & Time
DAY=$(date +%d)
MONTH=$(date +%m)
YEAR=$(date +%C%y)
BACKUPDATE=$(date +%Y%m%d%H%M%S)
# Backup file name
TARFILE="${LOCALDIR}""$(hostname)"_"${BACKUPDATE}".zip
# Backup dir
ZIPDIR=${TEMPDIR}backup_${BACKUPDATE}/
# Backup MySQL dump file name
SQLFILE="${ZIPDIR}mysql_${BACKUPDATE}.sql.gz"

log() {
    echo "$(date "+%Y-%m-%d %H:%M:%S")" "$1"
    echo -e "$(date "+%Y-%m-%d %H:%M:%S")" "$1" >> ${LOGFILE}
}

# Check for list of mandatory binaries
check_commands() {
    # This section checks for all of the binaries used in the backup
    # Do not check mysql command if you do not want to backup the MySQL database
    if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
        BINARIES=( cat cd du date dirname echo openssl pwd rm tar )
    else
        BINARIES=( cat cd du date dirname echo openssl mysql mysqldump pwd rm tar )
    fi

    # Iterate over the list of binaries, and if one isn't found, abort
    for BINARY in "${BINARIES[@]}"; do
        if [ ! "$(command -v "$BINARY")" ]; then
            log "$BINARY is not installed. Install it and try again"
            exit 1
        fi
    done

    # check rclone command
    RCLONE_COMMAND=false
    if [ "$(command -v "rclone")" ]; then
        RCLONE_COMMAND=true
    fi
    #create a dir to save zip files
    mkdir ${ZIPDIR}
    #set the dir permission to fastuser, in order to delete files in the fastpanel after.
    chown -R fastuser ${ZIPDIR}
}

calculate_size() {
    local file_name=$1
    local file_size=$(du -h $file_name 2>/dev/null | awk '{print $1}')
    if [ "x${file_size}" = "x" ]; then
        echo "unknown"
    else
        echo "${file_size}"
    fi
}

# Backup MySQL databases
mysql_backup() {
    if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
        log "MySQL root password not set, MySQL backup skipped"
    else
        log "MySQL dump start"
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" 2>/dev/null <<EOF
exit
EOF
        if [ $? -ne 0 ]; then
            log "MySQL root password is incorrect. Please check it and try again"
            exit 1
        fi
        if [ "${MYSQL_DATABASE_NAME[0]}" == "" ]; then
            mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" --all-databases | gzip > "${SQLFILE}" 2>/dev/null
            if [ $? -ne 0 ]; then
                log "MySQL all databases backup failed"
                exit 1
            fi
            log "MySQL all databases dump file name: ${SQLFILE}"
            #Add MySQL backup dump file to BACKUP list
            #BACKUP=(${BACKUP[@]} ${SQLFILE})
        else
            for db in ${MYSQL_DATABASE_NAME[@]}; do
                unset DBFILE
                DBFILE="${ZIPDIR}${db}_${BACKUPDATE}.sql.gz"
                mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" ${db} | gzip > "${DBFILE}" 2>/dev/null
                if [ $? -ne 0 ]; then
                    log "MySQL database name [${db}] backup failed, please check database name is correct and try again"
                    exit 1
                fi
                log "MySQL database name [${db}] dump file name: ${DBFILE}"
                #Add MySQL backup dump file to BACKUP list
                #BACKUP=(${BACKUP[@]} ${DBFILE})
            done
        fi
        log "MySQL dump completed"
    fi
}

start_backup() {
    [ "${#BACKUP[@]}" -eq 0 ] && echo "Error: You must to modify the [$(basename $0)] config before run it!" && exit 1

    log "Zip backup file start"
    for web in ${BACKUP[@]}; do
        unset WEBFILE
        WEBFILE="${ZIPDIR}${web##*/}_${BACKUPDATE}.zip"
        if ${ENCRYPTFLG}; then
            7z a -r -tzip -p${BACKUPPASS} ${WEBFILE} ${web} >/dev/null 2>&1
        else
            7z a -r -tzip ${WEBFILE} ${web} >/dev/null 2>&1
        fi
        if [ $? -gt 1 ]; then
            log "dir ${web##*/} backup file failed"
            exit 1
        fi
    done
    
    log "Zip backup file completed"

    # Delete MySQL temporary dump file
    #for sql in $(ls ${TEMPDIR}*.sql.gz); do
    #    log "Delete MySQL temporary dump file: ${sql}"
    #    rm -f ${sql}
    #done

    OUT_FILE="${ZIPDIR}"
    log "dir name: ${OUT_FILE}, dir size: $(calculate_size ${OUT_FILE})"
}

# Transfer backup file to Remote Drive
# If you want to install rclone command, please visit website:
# https://rclone.org/downloads/
rclone_upload() {
    if ${RCLONE_FLG} && ${RCLONE_COMMAND}; then
        [ -z "${RCLONE_NAME}" ] && log "Error: RCLONE_NAME can not be empty!" && return 1
        if [ -n "${RCLONE_FOLDER}" ]; then
            rclone ls ${RCLONE_NAME}:${RCLONE_FOLDER} 2>&1 > /dev/null
            if [ $? -ne 0 ]; then
                log "Create the path ${RCLONE_NAME}:${RCLONE_FOLDER}"
                rclone mkdir ${RCLONE_NAME}:${RCLONE_FOLDER}
            fi
        fi
        log "Tranferring backup dir: ${OUT_FILE} to Remote Drive"
        rclone copy ${OUT_FILE} ${RCLONE_NAME}:${RCLONE_FOLDER}/backup_${BACKUPDATE} >> ${LOGFILE}
        if [ $? -ne 0 ]; then
            log "Error: Tranferring backup dir: ${OUT_FILE} to Remote Drive failed"
            return 1
        fi
        log "Tranferring backup dir: ${OUT_FILE} to Remote Drive completed"
    fi
}

# Get file date
get_file_date() {
    #Approximate a 30-day month and 365-day year
    DAYS=$(( $((10#${YEAR}*365)) + $((10#${MONTH}*30)) + $((10#${DAY})) ))
    unset FILEYEAR FILEMONTH FILEDAY FILEDAYS FILEAGE
    FILEYEAR=$(echo "$1" | cut -d_ -f2 | cut -c 1-4)
    FILEMONTH=$(echo "$1" | cut -d_ -f2 | cut -c 5-6)
    FILEDAY=$(echo "$1" | cut -d_ -f2 | cut -c 7-8)
    if [[ "${FILEYEAR}" && "${FILEMONTH}" && "${FILEDAY}" ]]; then
        #Approximate a 30-day month and 365-day year
        FILEDAYS=$(( $((10#${FILEYEAR}*365)) + $((10#${FILEMONTH}*30)) + $((10#${FILEDAY})) ))
        FILEAGE=$(( 10#${DAYS} - 10#${FILEDAYS} ))
        return 0
    fi
    return 1
}

# Delete Remote Drive's old backup dir
delete_gdrive_file() {
    local FILENAME=$1
    if ${DELETE_REMOTE_FILE_FLG} && ${RCLONE_COMMAND}; then
        rclone ls ${RCLONE_NAME}:${RCLONE_FOLDER}/${FILENAME} 2>&1 > /dev/null
        if [ $? -eq 0 ]; then
            rclone purge ${RCLONE_NAME}:${RCLONE_FOLDER}/${FILENAME} >> ${LOGFILE}
            if [ $? -eq 0 ]; then
                log "Remote Drive's old backup dir: ${FILENAME} has been deleted"
            else
                log "Failed to delete Remote Drive's old backup dir: ${FILENAME}"
            fi
        else
            log "Remote Drive's old backup dir: ${FILENAME} is not exist"
        fi
    fi
}

# Clean up old dir
clean_up_files() {
    #cd ${LOCALDIR} || exit
    #LS=($(ls *.zip))
    LS=($(rclone lsf ${RCLONE_NAME}:${RCLONE_FOLDER}))
    for f in ${LS[@]}; do
        get_file_date ${f}
        if [ $? -eq 0 ]; then
            if [[ ${FILEAGE} -gt ${LOCALAGEDAILIES} ]]; then
                #rm -f ${f}
                #log "Old backup file name: ${f} has been deleted"
                delete_gdrive_file ${f}
            fi
        fi
    done
}

# Delete local dir
delete_local_files() {
    if ${DELETE_LOCAL_FILE_FLG} && [ -n ${OUT_FILE} ]; then
        rm -rf ${OUT_FILE}
        log "Local dir: ${OUT_FILE} has been deleted"
    fi
}

# Main progress
STARTTIME=$(date +%s)

# Check if the backup folders exist and are writeable
[ ! -d "${LOCALDIR}" ] && mkdir -p ${LOCALDIR}
[ ! -d "${TEMPDIR}" ] && mkdir -p ${TEMPDIR}

log "======Backup progress start======"
check_commands
mysql_backup
start_backup
#log "Backup progress complete"

#log "Upload progress start"
rclone_upload
#log "Upload progress complete"

#log "Cleaning up"
clean_up_files
delete_local_files
ENDTIME=$(date +%s)
DURATION=$((ENDTIME - STARTTIME))
log "All done"
log "Backup and transfer completed in ${DURATION} seconds"
