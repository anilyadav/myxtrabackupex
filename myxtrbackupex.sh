#!/bin/sh
#/************************************************************************
# * Copyright (c) 2011 doujinshuai (doujinshuai@gmail.com)
# * Create Time   : 02-24-2011
# * Last Modified : 01-11-2013
# *
# * Example: mysql_xtraback.sh -f mysql_xtraback.conf -a backup -t [incre|full]
# * mysql_traback.sh -f mysql_xtraback.conf -a recover -t [incre|full]
# *
# ************************************************************************/


################################################
######       Function Define start        ######
################################################

#/*
# *
# */
function func_check_file()
{
        type=$1
        filepath=$2
        if [ ! -$type "$filepath" ]; then
                echo "Error: $filepath dont existed; Please check this file path."
                exit 99
        fi
}

#/*
# *
# */
function func_check_backup_args()
{
        func_check_file d $MySQL_BASE
        func_check_file f $MySQL_CNF
        func_check_file S $SOCKET

        [ -f $MySQL_CNF ] && OPTIONS=" --defaults-file=$MySQL_CNF"
        [ -S $SOCKET ] && OPTIONS=$OPTIONS" --sock=$SOCKET"

        [ -n "$IOPS_LIMIT" ] && OPTIONS=$OPTIONS" --throttle=$IOPS_LIMIT"
        [ -n "$USER" -a -n "$PASSWD" ] && OPTIONS=$OPTIONS" --user=$USER --password=$PASSWD"

        if [ -n "$DATABASE" ]
        then
                OPTIONS=$OPTIONS" --databases=$DATABASE"
                BACKUP_FILE_SUFFIX="_${PORT}_${DATABASE}"
        else
                BACKUP_FILE_SUFFIX="_${PORT}"
        fi
        BACKUP_FILE_PREFIX=$($DATE "+%Y%m%d_%H%M")
}

#/*
# *
# */
function func_backup()
{
        # --------------------------------------------------
        DATE_START=$($DATE "+%s")
        echo ""
        echo "1.Start Xtrabackup operate on $($DATE "+%F %T")"
        #$INNOBACKUPEX --no-timestamp $OPTIONS --stream=tar $BACKUP_DIR 2>${BACKUP_DIR}.log | $GZIP >${BACKUP_DIR}.tar.gz
        if [ "incre" != "$BACKUP_TYPE" ]
        then
                BACKUP_FILE=${BACKUP_FILE_PREFIX}${BACKUP_FILE_SUFFIX}
                XTRABAK="$INNOBACKUPEX --no-timestamp $OPTIONS $BACKUP_DIR/$BACKUP_FILE"
                echo $XTRABAK
                $XTRABAK >>$BACKUP_DIR/${BACKUP_FILE}.log 2>&1
        else
                func_check_file f $TEMP_DIR/xtrabackup_checkpoints

                BACKUP_FILE=${DELTA_PREFIX}${BACKUP_FILE_PREFIX}${BACKUP_FILE_SUFFIX}${DELTA_SUFFIX}

                XTRABAK="$INNOBACKUPEX --no-timestamp $OPTIONS --incremental=$TEMP_DIR $BACKUP_DIR/$BACKUP_FILE"
                echo $XTRABAK
                $XTRABAK >>$BACKUP_DIR/${BACKUP_FILE}.log 2>&1
        fi
        RETVAL=$?
        DATE_END=$($DATE "+%s")
        echo "1.End Xtrabackup operate on $($DATE "+%F %T"). Spend time $((DATE_END-DATE_START)) Sec."
        echo ""

        if [ $RETVAL != 0 ]
        then
                echo "backup mysql database using xtrabackup failed."
                exit 99
        else
                DATE_START=$($DATE "+%s")
                echo "2.Start compress backup file on $($DATE "+%F %T")."
                $CP -af $BACKUP_DIR/$BACKUP_FILE/xtrabackup_checkpoints $TEMP_DIR/
                cd $BACKUP_DIR && $TAR cf - $BACKUP_FILE | $GZIP -qc > ${BACKUP_FILE}.tar.gz 
                RETVAL=$?
                if [ $RETVAL != 0 ];then
                        echo "Compress mysql database backup failed."
                        exit 99
                else
                        rm -fr $BACKUP_FILE                                        
                        DATE_END=$($DATE "+%s")
                        echo "Compress mysql database backup successful. Spend time $((DATE_END-DATE_START)) Sec."
                fi
                echo "2.End compress backup file on $($DATE "+%F %T")."
                echo ""
        fi

        #
        if [ 1 = "$RSYNC_OPTS" ]
        then
                [ -n "$RSYNC_USER" -a -n "$RSYNC_PWD_FILE" ] && RSYNC_AUTH="--password-file=$RSYNC_PWD_FILE ${RSYNC_USER}@"
                [ -n "$RSYNC_LIMIT" ] && RSYNC_OPTIONS=" --bwlimit=${RSYNC_LIMIT}"
                $SLEEP 5
                DATE_START=$($DATE "+%s")
                $RSYNC -vzrtopgl $RSYNC_OPTIONS ${BACKUP_FILE}.log ${BACKUP_FILE}.tar.gz ${RSYNC_AUTH}${RSYNC_HOST}::${RSYNC_PATH}/
                RETVAL=$?
                DATE_END=$($DATE "+%s")
                if [ $RETVAL != 0 ]
                then
                        echo "rsync $HOST:$PORT backup data dir failed"
                else
                        echo "$($DATE "+%Y-%m-%d %H:%M:%S"). rsync $HOST:$PORT backup data dir completed. Spend time $((DATE_END-DATE_START)) Sec."
                fi
                echo ""
        fi

        #
        echo "Deleting files older than $KEEP days ONLY in ${BACKUP_DIR}"
        $FIND ${BACKUP_DIR} -maxdepth 1 -mtime +$KEEP -type f -exec rm -r "{}" \;
        echo ""
}

#/*
# *
# */
function func_check_recover_args()
{
        func_check_file d $RECOVER_MySQL_BASE
        func_check_file f $RECOVER_MySQL_CNF
        func_check_file S $RECOVER_SOCKET
        func_check_file d $RECOVER_BACKUP_DIR

        #
        [ -f $RECOVER_MySQL_CNF ] && RECOVER_OPTIONS="--defaults-file=$RECOVER_MySQL_CNF"
        [ -S $RECOVER_SOCKET ] && RECOVER_OPTIONS=$RECOVER_OPTIONS" --sock=$RECOVER_SOCKET"

        #
        [ -n $IOPS_LIMIT ] && RECOVER_OPTIONS=$RECOVER_OPTIONS" --throttle=$IOPS_LIMIT"
        [ -n $RECOVER_USER -a -n $RECOVER_PASSWD ] && RECOVER_OPTIONS=$RECOVER_OPTIONS" --user=$RECOVER_USER --password=$RECOVER_PASSWD"

        #
    if [ -n "$RECOVER_PORT" ]
    then
                RECOVER_LOG=$($DATE "+%Y%m%d_%H%M_$RECOVER_PORT")
        fi
        [ -f $TEMP_DIR/xtrabackup_checkpoints ] && $RM $TEMP_DIR/xtrabackup_checkpoints
}


#/*
# *
# */
function func_apply_log()
{
        #
        COUNT=1

        #
        OLD_IFS=$IFS && IFS=:
        for backupfile in $RECOVER_BACKUP_LIST
        do
                DATE_START=$($DATE "+%s")
                #
                echo ""
                echo "1. Start UnCompress backup file to $RECOVER_BACKUP_DIR at $($DATE "+%F %T")" 
                if [ 1 -eq $COUNT ]
                then
                        # 
                        RECOVER_BACKUP_FILE=${RECOVER_DELTA_PREFIX}${backupfile}${RECOVER_DELTA_SUFFIX}
                        func_check_file f $BACKUP_DIR/${RECOVER_BACKUP_FILE}.tar.gz

                        #
                        cd $BACKUP_DIR && $GZIP -dc $RECOVER_BACKUP_FILE.tar.gz | $TAR ixf - -C $RECOVER_BACKUP_DIR
                        cd $RECOVER_BACKUP_DIR && $MV $RECOVER_BACKUP_FILE/* $TEMP_DIR
                        func_check_file f $TEMP_DIR/xtrabackup_checkpoints
                        cd $RECOVER_BACKUP_DIR && $RM -r $RECOVER_BACKUP_FILE
                elif [ "incre" = "$BACKUP_TYPE" ]
                then
                        #
                        RECOVER_BACKUP_FILE=${RECOVER_DELTA_PREFIX}${backupfile}${RECOVER_DELTA_SUFFIX}${DELTA_SUFFIX}
                        func_check_file f $BACKUP_DIR/$RECOVER_BACKUP_FILE.tar.gz

                        #
                        cd $BACKUP_DIR && $GZIP -dc $RECOVER_BACKUP_FILE.tar.gz | $TAR ixf - -C $RECOVER_BACKUP_DIR
                        #
                        func_check_file f $RECOVER_BACKUP_DIR/$RECOVER_BACKUP_FILE/xtrabackup_checkpoints

                        #
                        INCREMENTAL_OPTIONS="--incremental=$RECOVER_BACKUP_DIR/$RECOVER_BACKUP_FILE"
                else
                        break
                fi
                DATE_END=$($DATE "+%s")
                echo "1. End UnCompress backup file to $RECOVER_BACKUP_DIR at $($DATE "+%F %T"). Spend time $((DATE_END-DATE_START)) Sec."
                echo ""

                DATE_START=$($DATE "+%s")
                #
                echo "2. Start apply log from $BSEE_DIR at $($DATE "+%F %T")."
                IFS=$OLD_IFS
                APPLY_LOG_CMD="$INNOBACKUPEX --apply-log $RECOVER_OPTIONS $INCREMENTAL_OPTIONS $TEMP_DIR"
                echo $APPLY_LOG_CMD
                $APPLY_LOG_CMD >>$RECOVER_BACKUP_DIR/${RECOVER_LOG}.log 2>&1
                RETVAL=$?

                DATE_END=$($DATE "+%s")
                if [ $RETVAL != 0 ]; then
                        echo "apply log failed!"
                        $RM -fr $TEMP_DIR/*
                        exit 99
                else
                        $RM -fr $RECOVER_BACKUP_DIR/$RECOVER_BACKUP_FILE/
                        echo "apply log Success!. Spend time ($((DATE_END-DATE_START)) Sec)"
                fi
                echo "2. End apply log from $BSEE_DIR at $($DATE "+%F %T")."

                COUNT=$((COUNT+1))
                OLD_IFS=$IFS && IFS=:
        done
}

#/*
# *
# */
function func_copy_back()
{
        # 
        DATE_START=$($DATE "+%s")
        echo ""
        echo "3. Start copy back from $backup_directory at $($DATE "+%F %T")"
        IFS=$OLD_IFS
        COPY_BACK_CMD="$INNOBACKUPEX --copy-back $RECOVER_OPTIONS $TEMP_DIR"
        echo "$COPY_BACK_CMD"
        $COPY_BACK_CMD >>$RECOVER_BACKUP_DIR/${RECOVER_LOG}.log 2>&1
        RETVAL=$?
        DATE_END=$($DATE "+%s")
        if [ $RETVAL != 0 ]; then
                echo "Copy back Failed!"
                exit 99
        else
                [ -n "$MySQL_USER" -a -n "$MySQL_GROUP" ] && $CHOWN -R ${MySQL_USER}:${MySQL_GROUP} $RECOVER_MySQL_BASE
                echo "Copy back Success! Spend time ($((DATE_END-DATE_START)) Sec)"
        fi
        $RM -fr $TEMP_DIR/*
        echo "3. End copy back from $backup_directory at $($DATE "+%F %T")"
        echo ""
}


#/*
# *
# */
function usage ()
{
        echo "Usage: $0 -c cfg_file -a [OPTIONS] -t full"
        echo "  -c : configure file"
        echo "  -a : operation [ backup | recover ]"
        echo "  -t : type [ full | incre ]"
        echo "  -h : help"
        echo ""
        exit 0
}



################################################
######    Main program start execute      ######
################################################

#/*
# *
# */
while getopts "c:a:h:t:" OPT
do
        case $OPT in
                c)   CONF_FILE=$OPTARG ;;
                a)   ACTION=$OPTARG ;;
                t)   BACKUP_TYPE=$OPTARG ;;
                h)   usage exit 1 ;;
                [?]) usage exit 1;;
        esac
done

if [ $OPTIND -le 1 ];then
        usage
        exit 1
fi

#/*
# *
# */
#source $HOME/.bash_profile
source /etc/profile

#/*
# *
# */
func_check_file f $CONF_FILE && source $CONF_FILE

#/*
# * check system cmd
# */
CP=$(which cp)
MV=$(which mv)
RM=$(which rm)
DATE=$(which date)
CHOWN=$(which chown)
SLEEP=$(which sleep)
TAR=$(which tar)
GZIP=$(which gzip)
FIND=$(which find)
RSYNC=$(which rsync)
func_check_file f $CP
func_check_file f $MV
func_check_file f $DATE
func_check_file f $CHOWN
func_check_file f $SLEEP
func_check_file f $TAR
func_check_file f $GZIP
func_check_file f $FIND
func_check_file f $RSYNC

#/*
# * check work dir
# */
func_check_file d $TEMP_DIR
func_check_file d $BACKUP_DIR
func_check_file d $MySQL_CMD_DIR
func_check_file d $XTRABAK_DIR
func_check_file f $XTRABAK_DIR/$XTRABAK
func_check_file f $XTRABAK_DIR/$INNOBACKUPEX
export PATH=$PATH:$XTRABAK_DIR:$MySQL_CMD_DIR

#/*
# * main function
# */
if [ -n "$ACTION" ] ;then
        case $ACTION in
                backup )
                        echo -e "\n\n"
                        echo "*********   Start backup operate at $($DATE "+%F %T"). *********"
                        DATE_START_ALL=$($DATE "+%s")
                        func_check_backup_args
                        func_backup
                        DATE_END_ALL=$($DATE "+%s")
                        echo "*********   End backup operate at $($DATE "+%F %T"). Spend time $((DATE_END_ALL-DATE_START_ALL)) Sec.   *********"
                        echo ""
                        ;;
                recover )
                        echo -e "\n\n"
                        echo "*********   Start recover operate at $($DATE "+%F %T").   *********"
                        DATE_START_ALL=$($DATE "+%s")
                        func_check_recover_args
                        func_apply_log
                        func_copy_back
                        DATE_END_ALL=$($DATE "+%s")
                        echo "*********   End recover operate at $($DATE "+%F %T"). Spend time $((DATE_END_ALL-DATE_START_ALL)) Sec.   *********" 
                        echo ""
                        ;;
                *)
                echo "UNKNOW OPERATION"
                        usage
                        exit -1
                        ;;
        esac
fi

exit 0
