#!/bin/sh
#/************************************************************************
# * Copyright (c) 2011-2013 doujinshuai (doujinshuai@gmail.com)
# * Create Time   : 02-24-2011
# * Last Modified : 01-13-2013
# *
# * Usage: myxtrabackupex [OPTIONS]
# *        myxtrbackupex.sh -c cfg_file -o backup -t full
# *   -c : configure file
# *   -o : operation [ backup | recover ]
# *   -t : type [ full | incre ], default is full.
# *   -h : help
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
                exit 2
        fi
}

#/*
# *
# */
function func_check_backup_args()
{
        func_check_file d $MySQL_BASE
        func_check_file f $MySQL_CNF
        #[ -n "$RETAIN_DAYS" ] && RETAIN_DAYS

        OPTIONS=" --stream=xbstream --no-timestamp --no-lock --slave-info --safe-slave-backup --defaults-file=$MySQL_CNF"
        [ -n "$USER" -a -n "$PASSWD" ] && OPTIONS=$OPTIONS" --user=$USER --password=$PASSWD"
        { [ -S "$SOCKET" ] && OPTIONS=$OPTIONS" --sock=$SOCKET"; } || \
                { [ -n "$HOST" -a -n "$PORT" ] && OPTIONS=$OPTIONS" --host=$HOST --port=$PORT"; }
        [ -n "$DATABASE" ] && OPTIONS=$OPTIONS" --databases=$DATABASE"
        [ -n "$COMPRESS" ] && [ $COMPRESS -ge 1 ] && OPTIONS=$OPTIONS" --compress --compress-threads=$COMPRESS"
        [ -n "$THROTTLE" ] && [ $THROTTLE -ge 1 ] && OPTIONS=$OPTIONS" --throttle=$THROTTLE"
        [ -n "$PARALLEL" ] && [ $PARALLEL -ge 1 ] && OPTIONS=$OPTIONS" --parallel=$PARALLEL"
        [ -n "$USE_MEMORY" ] && OPTIONS=$OPTIONS" --use-memory=$USE_MEMORY"
        OPTIONS=$OPTIONS" --extra-lsndir=$TEMP_DIR"

        [ "incre" = "$BACKUP_TYPE" ] && INCREMENTAL_OPTIONS=" --incremental-basedir=$TEMP_DIR --incremental"
}

#/*
# *
# */
function func_backup()
{
        #------------ simple separator line ------------
        echo ""
        echo "1.$($DATE "+%F_%T"): innobackupex work Start."

        DATE_START=$($DATE "+%s")
        DATE_TIME=$(date "+%Y%m%d_%H%M%S")
        BACKUP_FILE_DIR=$BACKUP_DIR/${BACKUP_FILE_PREFIX}${DATE_TIME}${BACKUP_FILE_SUFFIX}
        if [ "incre" = "$BACKUP_TYPE" ]; then
                func_check_file f $TEMP_DIR/xtrabackup_checkpoints
                BACKUP_FILE_DIR=${BACKUP_FILE_DIR}_incre
        fi
        MYXTRABACKUPEX="$INNOBACKUPEX $OPTIONS $INCREMENTAL_OPTIONS $BACKUP_DIR"
        echo $MYXTRABACKUPEX" > "${BACKUP_FILE_DIR}.xbstream
        { $MYXTRABACKUPEX > ${BACKUP_FILE_DIR}.xbstream ; } >> ${BACKUP_FILE_DIR}.log 2>&1
        RETVAL=$?

        DATE_END=$($DATE "+%s")
        if [ $RETVAL = 0 ]; then
                echo "1.$($DATE "+%F_%T"): innobackupex completed OK! Spend time $((DATE_END-DATE_START)) Sec."
                echo ""
        else
                echo "1.$($DATE "+%F_%T"): innobackupex operation failed! Spend time $((DATE_END-DATE_START)) Sec."
                exit 1
        fi
        echo ""
        #------------ simple separator line ------------

        #------------ simple separator line ------------
        $SLEEP 2
        if [ 1 = "$RSYNC_OPTS" ]; then
                echo ""
                echo "2.$($DATE "+%F_%T"): rsync work start."
                func_check_file f $RSYNC
                func_check_file n $RSYNC_HOST

                SYNC_OPTIONS=" -vzrtopgl"
                [ -n "$RSYNC_LIMIT" ] && RSYNC_OPTIONS=" --bwlimit=${RSYNC_LIMIT}"
                [ -n "$RSYNC_PORT" ] && RSYNC_OPTIONS=$RSYNC_OPTIONS" --port=$RSYNC_PORT"
                [ -n "$RSYNC_USER" ] && RSYNC_AUTH=" ${RSYNC_USER}@"
                if [ 1 = "$SSH_OPTS" ]; then
                        func_check_file n $RSYNC_USER
                        RSYNC_OPTIONS=$RSYNC_OPTIONS" -e ssh"
                        [ -n "$RSYNC_PATH" ] && RSYNC_PATH="/"$RSYNC_PATH
                        RSYNC_SEND_CMD="$RSYNC_OPTIONS ${BACKUP_FILE_DIR}.* ${RSYNC_AUTH}${RSYNC_HOST}:${RSYNC_PATH}/"
                else
                        [ -f "$RSYNC_PWD_FILE" ] && RSYNC_OPTIONS=$RSYNC_OPTIONS" --password-file=$RSYNC_PWD_FILE"
                        [ -n "$RSYNC_PATH" ] && RSYNC_PATH=":"$RSYNC_PATH
                        RSYNC_SEND_CMD="$RSYNC $RSYNC_OPTIONS ${BACKUP_FILE_DIR}.* ${RSYNC_AUTH}${RSYNC_HOST}:${RSYNC_PATH}/"
                fi

                DATE_START=$($DATE "+%s")
                echo "  $RSYNC_SEND_CMD"
                $RSYNC_SEND_CMD
                RETVAL=$?
                DATE_END=$($DATE "+%s")

                if [ $RETVAL = 0 ]; then
                        echo "2. $($DATE "+%F %T"). rsync $HOST:$PORT backup data dir completed. Spend time $((DATE_END-DATE_START)) Sec."
                else
                        echo "2. $($DATE "+%F %T"). rsync $HOST:$PORT backup data dir failed. Spend time $((DATE_END-DATE_START)) Sec."
                fi
                echo ""
        fi
        #------------ simple separator line ------------

        #------------ simple separator line ------------
        #/*
        # * Risk: Will delete the file in directory BACKUP_DIR
        # */
        echo "3.$($DATE "+%F_%T"): Clear old backup file work start."
        echo "  Deleting files older than $RETAIN_DAYS days ONLY in ${BACKUP_DIR}"
        $FIND ${BACKUP_DIR} -maxdepth 1 -mtime +$RETAIN_DAYS -type f -exec rm -r "{}" \;
        echo "3.$($DATE "+%F_%T"): Clear old backup file work end."
        echo ""
        #------------ simple separator line ------------
}

#/*
# *
# */
function func_check_recover_args()
{
        func_check_file d $RECOVER_MySQL_BASE
        func_check_file d $RECOVER_MySQL_BASE/data
        func_check_file d $RECOVER_DIR
        func_check_file f $RECOVER_MySQL_CNF
        INCREMENTAL_OPTIONS=""
        RECOVER_OPTIONS=" --defaults-file=$RECOVER_MySQL_CNF"
}


#/*
# *
# */
function func_prepare()
{
        COUNT=1
        OLD_IFS=$IFS && IFS=:
        for backupfile in $RECOVER_BACKUP_LIST
        do
                #------------ simple separator line ------------
                echo -e "\n\n"
                echo "1.$($DATE "+%F %T") xbstream unpack file to $RECOVER_DIR work start."
                BACKUP_FILE_DIR=$BACKUP_DIR/$backupfile
                RECOVER_FILE_DIR=$RECOVER_DIR/$backupfile
                func_check_file f $BACKUP_FILE_DIR

                DATE_START=$($DATE "+%s")
                [ $COUNT -gt 1 -a "full" = "$BACKUP_TYPE" ] && break
                { [ ! -d $RECOVER_FILE_DIR ] && $MKDIR $RECOVER_FILE_DIR; } || exit 1
                cd $BACKUP_DIR && $XBSTREAM -x < $BACKUP_FILE_DIR -C $RECOVER_FILE_DIR/
                DATE_END=$($DATE "+%s")

                echo "1.$($DATE "+%F %T") xbstream unpack file to $RECOVER_FILE_DIR work end. Spend time $((DATE_END-DATE_START)) Sec."
                #------------ simple separator line ------------

                #------------ simple separator line ------------
                IFS=$OLD_IFS
                echo ""
                echo "2. $($DATE "+%F %T") qpress all backup file work start."
                DATE_START=$($DATE "+%s")
                for tmp_bf in $( $FIND $RECOVER_FILE_DIR -iname "*\.qp" );
                do
                        $QPRESS -d $tmp_bf $(dirname $tmp_bf) && $RM $tmp_bf;
                done
                DATE_END=$($DATE "+%s")
                echo "2. $($DATE "+%F %T") qpress all backup file work start. Spend time $((DATE_END-DATE_START)) Sec."
                echo ""
                #------------ simple separator line ------------

                #------------ simple separator line ------------
                echo "3. $($DATE "+%F %T") innobackupex apply log work start."
                DATE_START=$($DATE "+%s")

                if [ $COUNT -eq 1 ]; then
                        $MV $RECOVER_FILE_DIR/* $TEMP_DIR/ && $RM -fr $RECOVER_FILE_DIR
                elif [ "incre" = "$BACKUP_TYPE" ]; then
                        INCREMENTAL_OPTIONS=" --incremental-dir=$RECOVER_FILE_DIR"
                fi
                APPLY_LOG_CMD="$INNOBACKUPEX --apply-log --redo-only $RECOVER_OPTIONS $TEMP_DIR $INCREMENTAL_OPTIONS"
                echo $APPLY_LOG_CMD
                $APPLY_LOG_CMD >> ${RECOVER_FILE_DIR}.log 2>&1
                RETVAL=$?

                $RM -fr $RECOVER_FILE_DIR
                DATE_END=$($DATE "+%s")
                if [ $RETVAL != 0 ]; then
                        echo "3.$($DATE "+%F %T") apply log faild!. Spend time ($((DATE_END-DATE_START)) Sec)"
                        exit 3
                else
                        echo "3.$($DATE "+%F %T") apply log success!. Spend time ($((DATE_END-DATE_START)) Sec)"
                fi
                #------------ simple separator line ------------

                COUNT=$((COUNT+1))
                OLD_IFS=$IFS && IFS=:
        done
        IFS=$OLD_IFS
}

#/*
# *
# */
function func_recover()
{
        #------------ simple separator line ------------
        echo ""
        echo "4.$($DATE "+%F %T") innobackupex move-back start"
        DATE_START=$($DATE "+%s")
        MOVE_BACK_CMD="$INNOBACKUPEX --move-back $RECOVER_OPTIONS $TEMP_DIR"
        echo "$MOVE_BACK_CMD"
        $MOVE_BACK_CMD >> ${RECOVER_FILE_DIR}.log 2>&1
        RETVAL=$?
        #------------ simple separator line ------------

        DATE_END=$($DATE "+%s")
        if [ $RETVAL != 0 ]; then
                echo "4.$($DATE "+%F %T") innobackupex move-back failed! Spend time ($((DATE_END-DATE_START)) Sec)"
                exit 4
        else
                [ -n "$MySQL_USER" -a -n "$MySQL_GROUP" ] && $CHOWN -R ${MySQL_USER}:${MySQL_GROUP} $RECOVER_MySQL_BASE
                echo "4.$($DATE "+%F %T") innobackupex move-back success! Spend time ($((DATE_END-DATE_START)) Sec)"
        fi
        $RM -fr $TEMP_DIR/*
        echo ""
}


#/*
# * main function
# */
function main()
{
    BACKUP_TYPE=${BACKUP_TYPE:="full"}
    if [ "$BACKUP_TYPE" != "full" -a "$BACKUP_TYPE" != "incre" ]; then
         echo "Fatal error: UNKNOW BACKUP TYPE!"
         echo "Try 'myxtrabackupex -h' for more information."
         exit 99;
    fi

    if [ -n "$OPERATION" ] ;then
        case $OPERATION in
                backup )
                        echo -e "\n"
                        echo "*********   Start backup operate at $($DATE "+%F %T"). *********"
                        DATE_START_ALL=$($DATE "+%s")
                        func_check_backup_args
                        func_backup
                        DATE_END_ALL=$($DATE "+%s")
                        echo "*********   End backup operate at $($DATE "+%F %T"). Spend time $((DATE_END_ALL-DATE_START_ALL)) Sec.   *********"
                        echo ""
                        ;;
                recover )
                        echo -e "\n"
                        echo "*********   Start recover operate at $($DATE "+%F %T").   *********"
                        DATE_START_ALL=$($DATE "+%s")
                        func_check_recover_args
                        func_prepare
                        func_recover $TEMP_DIR
                        DATE_END_ALL=$($DATE "+%s")
                        echo "*********   End recover operate at $($DATE "+%F %T"). Spend time $((DATE_END_ALL-DATE_START_ALL)) Sec.   *********" 
                        echo ""
                        ;;
                *)
                        echo "Fatal error: UNKNOW OPERATION"
                        echo "Try 'myxtrabackupex -h' for more information."
                        exit 99
                        ;;
        esac
    fi
}

#/*
# *
# */
function usage ()
{
        echo "Usage: myxtrabackupex [OPTIONS]"
        echo "       $0 -c cfg_file -o backup -t full"
        echo "  -c : configure file"
        echo "  -o : operation [ backup | recover ]"
        echo "  -t : type [ full | incre ], default is full."
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
while getopts "c:h:o:t:" OPT
do
        case $OPT in
                c)   CONF_FILE=$OPTARG ;;
                o)   OPERATION=$OPTARG ;;
                t)   BACKUP_TYPE=$OPTARG ;;
                h)   usage
                     exit 1 ;;
                [?]) usage
                     exit 1 ;;
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
#source /etc/profile

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
MKDIR=$(which mkdir)
DATE=$(which date)
CHOWN=$(which chown)
SLEEP=$(which sleep)
FIND=$(which find)
RSYNC=$(which rsync)
func_check_file f $CP
func_check_file f $MV
func_check_file f $DATE
func_check_file f $CHOWN
func_check_file f $SLEEP
func_check_file f $FIND

#/*
# * check work dir
# */
func_check_file d $TEMP_DIR
func_check_file d $BACKUP_DIR
func_check_file d $MySQL_CMD_DIR
func_check_file d $XTRABAK_DIR
func_check_file f $XTRABAK_DIR/$XTRABAK
func_check_file f $XTRABAK_DIR/$XBSTREAM
func_check_file f $XTRABAK_DIR/$QPRESS
func_check_file f $XTRABAK_DIR/$INNOBACKUPEX
export PATH=$PATH:$XTRABAK_DIR:$MySQL_CMD_DIR

#/*
# * main function
# */

main

exit 0
