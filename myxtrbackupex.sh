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
# * # add crontab schedule backup plan
# * 10 3 * * 1 sh myxtrbackupex.sh -c backup.cfg -o backup >> ../logs/schedule.log 2>&1 &
# * 10 3 * * 2,3,4,5,6,7 sh myxtrbackupex.sh -c backup.cfg -o backup -t incre >> ../logs/schedule.log 2>&1 &
# *
# ************************************************************************/


################################################
######       Function Define start        ######
################################################

#/*
# * test args
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

    OPTIONS=""
    [ -n "$USER" -a -n "$PASSWD" ] && OPTIONS=$OPTIONS" --user=$USER --password=$PASSWD"
    { [ -S "$SOCKET" ] && OPTIONS=$OPTIONS" --sock=$SOCKET"; } || \
        { [ -n "$HOST" -a -n "$PORT" ] && OPTIONS=$OPTIONS" --host=$HOST --port=$PORT"; }
    if [ -n "$DATABASES" ]; then
        OLD_IFS=$IFS && IFS=,
        for dbname in $DATABASES; do db_list=$db_list"$dbname "; done
        IFS=$OLD_IFS
        db_list=$(echo $db_list)
#        OPTIONS=$OPTIONS" --databases='$db_list'"
    fi
#    if [ -n "$STREAM" ]; then
#        [ $STREAM = "xbstream" ] && OPTIONS=$OPTIONS" --stream=xbstream" || \
#           { [ $STREAM = "tar" ] && OPTIONS=$OPTIONS" --stream=tar" ; }
#    fi
    if [[ "$COMPRESS" =~ ^[1-9][0-9]*$ ]]; then
        if [ $COMPRESS -eq 1 ]; then
            OPTIONS=$OPTIONS" --compress"
        else [ $COMPRESS -gt 1 ]
            OPTIONS=$OPTIONS" --compress --compress-threads=$COMPRESS"
        fi
    fi
    [[ "$THROTTLE" =~ ^[1-9][0-9]*$ ]] && [ $THROTTLE -ge 1 ] && OPTIONS=$OPTIONS" --throttle=$THROTTLE"
    [[ "$USE_MEMORY" =~ ^[1-9][0-9kKmMgG]*$ ]] && OPTIONS=$OPTIONS" --use-memory=$USE_MEMORY"

    OPTIONS=" --defaults-file=$MySQL_CNF --no-timestamp --no-lock --slave-info --safe-slave-backup --extra-lsndir=$TEMP_DIR --tmpdir=$TEMP_DIR "$OPTIONS

    [ "incre" = "$BACKUP_TYPE" ] && INCRE_OPTIONS=" --incremental-basedir=$TEMP_DIR --incremental"
}

#/*
# * backup operation
# */
function func_backup()
{
    #------------ simple separator line ------------
    echo ""
    echo "1.$($DATE "+%F_%T"): innobackupex work Start."

    DATE_TIME=$(date "+%Y%m%d_%H%M%S")
    BACKUP_FILE_DIR=$BACKUP_DIR/${BACKUP_FILE_PREFIX}${DATE_TIME}${BACKUP_FILE_SUFFIX}
    if [ "incre" = "$BACKUP_TYPE" ]; then
        func_check_file f $TEMP_DIR/xtrabackup_checkpoints
        BACKUP_FILE_DIR=${BACKUP_FILE_DIR}_incre
    fi

    DATE_START=$($DATE "+%s")
    if [ -z "$STREAM" ]; then
        echo "$INNOBACKUPEX --databases="$db_list" $OPTIONS $INCRE_OPTIONS $BACKUP_FILE_DIR"
        $INNOBACKUPEX --databases="$db_list" $OPTIONS $INCRE_OPTIONS $BACKUP_FILE_DIR >> ${BACKUP_FILE_DIR}.log 2>&1;
    else
        BACKUP_FILE_NAME=${BACKUP_FILE_DIR}.${STREAM}
        if [ "$GZIP_OPTS" = "1" ]; then
            echo "$INNOBACKUPEX --databases="$db_list" --stream=$STREAM $OPTIONS $INCRE_OPTIONS ${BACKUP_DIR} | $GZIP - > ${BACKUP_FILE_NAME}.gz"
            ( $INNOBACKUPEX --databases="$db_list" --stream=$STREAM $OPTIONS $INCRE_OPTIONS ${BACKUP_DIR} | $GZIP - > ${BACKUP_FILE_NAME}.gz; ) \
                >> ${BACKUP_FILE_NAME}.log 2>&1;
        else
            echo "$INNOBACKUPEX --databases="$db_list" --stream=$STREAM $OPTIONS $INCRE_OPTIONS ${BACKUP_DIR} > ${BACKUP_FILE_NAME}"
            ( $INNOBACKUPEX --databases="$db_list" --stream=$STREAM $OPTIONS $INCRE_OPTIONS ${BACKUP_DIR} > ${BACKUP_FILE_NAME}; ) \
                >> ${BACKUP_FILE_NAME}.log 2>&1;
        fi
    fi
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
                [[ "$RSYNC_LIMIT" =~ ^[1-9][0-9]*$ ]] && RSYNC_OPTIONS=" --bwlimit=${RSYNC_LIMIT}"
                [[ "$RSYNC_PORT" =~ ^[1-9][0-9]*$ ]] && RSYNC_OPTIONS=$RSYNC_OPTIONS" --port=$RSYNC_PORT"
                [ -n "$RSYNC_USER" ] && RSYNC_AUTH=" ${RSYNC_USER}@"
                if [ 1 = "$SSH_OPTS" ]; then
                        func_check_file n $RSYNC_USER
                        RSYNC_OPTIONS=$RSYNC_OPTIONS" -e ssh"
                        [ -n "$RSYNC_PATH" ] && RSYNC_PATH="/"$RSYNC_PATH
                        RSYNC_SEND_CMD="$RSYNC_OPTIONS ${backup_file}* ${RSYNC_AUTH}${RSYNC_HOST}:${RSYNC_PATH}/"
                else
                        [ -f "$RSYNC_PWD_FILE" ] && RSYNC_OPTIONS=$RSYNC_OPTIONS" --password-file=$RSYNC_PWD_FILE"
                        [ -n "$RSYNC_PATH" ] && RSYNC_PATH=":"$RSYNC_PATH
                        RSYNC_SEND_CMD="$RSYNC $RSYNC_OPTIONS ${backup_file}* ${RSYNC_AUTH}${RSYNC_HOST}:${RSYNC_PATH}/"
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
    if [[ "$RETAIN_DAYS" =~ ^[1-9][0-9]*$ ]]; then
            echo "3.$($DATE "+%F_%T"): Clear old backup file work start."
            echo "    Deleting files older than $RETAIN_DAYS days ONLY in ${BACKUP_DIR}"
            $FIND ${BACKUP_DIR} -maxdepth 1 -mtime +$RETAIN_DAYS -type f -exec rm -r "{}" \;
            echo "3.$($DATE "+%F_%T"): Clear old backup file work end."
            echo "";
    fi
    #------------ simple separator line ------------
}

#/*
# *
# */
function func_check_recover_args()
{
        func_check_file d $RECOVER_MySQL_BASE
        func_check_file d $RECOVER_MySQL_BASE/data
        func_check_file d $TEMP_DIR
        func_check_file d $RECOVER_DIR
        func_check_file f $RECOVER_MySQL_CNF
        INCRE_OPTIONS=""
        RECOVER_OPTIONS=" --defaults-file=$RECOVER_MySQL_CNF"
}


#/*
# *
# */
function func_prepare()
{
    COUNT=1
    OLD_IFS=$IFS && IFS=,
    for backupfile in $RECOVER_BACKUP_LIST
    do
        IFS=$OLD_IFS
        BACKUP_FILE_DIR=$BACKUP_DIR/$backupfile
        func_check_file f $BACKUP_FILE_DIR
        [ $COUNT -gt 1 -a "full" = "$BACKUP_TYPE" ] && break

        #------------ simple separator line ------------
        if [ -n "$STREAM" ]; then 
            echo "1.$($DATE "+%F %T") myxtrabackupex unpack file work start."
            DATE_START=$($DATE "+%s")
            if [ $STREAM = "tar" ]; then
                [ "$GZIP_OPTS" = "1" ] && { file_suffix=".tar.gz"; tar_args="zxif"; } || { file_suffix=".tar"; tar_args="xif"; }
                recover_file=$(echo $backupfile | $AWK -F"$file_suffix" '{ print $1}' )
                [ -n "$recover_file" ] && \
                    UNPACK_CMD="$TAR $tar_args $BACKUP_FILE_DIR"
            elif [ $STREAM = "xbstream" ]; then
                if [ "$GZIP_OPTS" = "1" ]; then
                    file_suffix=".xbstream.gz";
                    UNPACK_CMD="$GZIP -d $BACKUP_FILE_DIR && ";
                else
                    file_suffix=".xbstream";
                fi
                recover_file=$(echo $backupfile | $AWK -F"$file_suffix" '{ print $1}' )
                UNPACK_CMD=$UNPACK_CMD"$XBSTREAM -x < $RECOVER_DIR/${recover_file}.xbstream"
            fi

            RECOVER_FILE_DIR=$RECOVER_DIR/$recover_file
            UNPACK_CMD=$UNPACK_CMD" -C $RECOVER_FILE_DIR"
            [ ! -d "$RECOVER_FILE_DIR" ] && $MKDIR $RECOVER_FILE_DIR || exit 1
            echo -e "\t$UNPACK_CMD" && $UNPACK_CMD
            DATE_END=$($DATE "+%s")

            echo "1.$($DATE "+%F %T") myxtrabackupex unpack file work end. Spend time $((DATE_END-DATE_START)) Sec."
        else
            if [ -d $BACKUP_FILE_DIR ]; then 
                RECOVER_FILE_DIR=$RECOVER_DIR/$backupfile
                $MKDIR $RECOVER_FILE_DIR && $MV $BACKUP_FILE_DIR/* $RECOVER_FILE_DIR/
            else
                echo -e "\t$BACKUP_FILE_DIR is not directory! ";
                exit 1;
            fi 
        fi # end unpack backup file
        #------------ simple separator line ------------

        #------------ simple separator line ------------
        if [[ "$COMPRESS" =~ ^[1-9][0-9]*$ ]]; then 
            echo ""
            echo "2. $($DATE "+%F %T") qpress all backup file work start."
            DATE_START=$($DATE "+%s")
            for tmp_bf in $( $FIND $RECOVER_FILE_DIR $ -iname "*\.qp" ); do
                $QPRESS -d $tmp_bf $(dirname $tmp_bf) && $RM $tmp_bf;
            done
            DATE_END=$($DATE "+%s")
            echo "2. $($DATE "+%F %T") qpress all backup file work start. Spend time $((DATE_END-DATE_START)) Sec."
            echo ""
        fi # end qpress uncompress
        #------------ simple separator line ------------

        #------------ simple separator line ------------
        echo "3. $($DATE "+%F %T") innobackupex apply log work start."
        if [ $COUNT -eq 1 ]; then
            $MV $RECOVER_FILE_DIR/* $TEMP_DIR/ && $TOUCH $TEMP_DIR/working_flag
        elif [ "incre" = "$BACKUP_TYPE" ]; then
            INCRE_OPTIONS=" --incremental-dir=$RECOVER_FILE_DIR"
        fi

        DATE_START=$($DATE "+%s")
        APPLY_LOG_CMD="$INNOBACKUPEX --apply-log --redo-only $RECOVER_OPTIONS $TEMP_DIR $INCRE_OPTIONS"
        echo $APPLY_LOG_CMD
        $APPLY_LOG_CMD >> ${RECOVER_FILE_DIR}.log 2>&1
        RETVAL=$?
        DATE_END=$($DATE "+%s")

        if [ $RETVAL != 0 ]; then
            echo "3.$($DATE "+%F %T") apply log faild!. Spend time ($((DATE_END-DATE_START)) Sec)"
            exit 3
        else
            echo "3.$($DATE "+%F %T") apply log success!. Spend time ($((DATE_END-DATE_START)) Sec)"
        fi # end apply-log
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
        #$RM -fr $TEMP_DIR/*
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
                echo -e "\n\n"
                echo "*********   Start backup operate at $($DATE "+%F %T"). *********"
                DATE_START_ALL=$($DATE "+%s")
                [ -f "$TEMP_DIR/working_flag" ] && { echo "innobackupex backup working ."; exit 99; }
                func_check_backup_args
                func_backup
                $RM -f $TEMP_DIR/working_flag
                DATE_END_ALL=$($DATE "+%s")
                echo "*********   End backup operate at $($DATE "+%F %T"). Spend time $((DATE_END_ALL-DATE_START_ALL)) Sec.   *********"
                echo -e "\n\n"
                ;;
            recover )
                echo -e "\n\n"
                echo "*********   Start recover operate at $($DATE "+%F %T").   *********"
                DATE_START_ALL=$($DATE "+%s")
                [ -f "$TEMP_DIR/working_flag" ] && { echo "innobackupex recover working."; exit 99; }
                func_check_recover_args
                func_prepare
                func_recover $TEMP_DIR
                $RM -f $TEMP_DIR/working_flag
                DATE_END_ALL=$($DATE "+%s")
                echo "*********   End recover operate at $($DATE "+%F %T"). Spend time $((DATE_END_ALL-DATE_START_ALL)) Sec.   *********" 
                echo -e "\n\n"
                ;;
            *)
                echo -e "\n\n"
                echo "Fatal error: UNKNOW OPERATION"
                echo "Try 'myxtrabackupex -h' for more information."
                exit 99
                echo -e "\n\n"
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
CP=$(which cp) && func_check_file f $CP
MV=$(which mv) && func_check_file f $MV
RM=$(which rm) && func_check_file f $RM
MKDIR=$(which mkdir) && func_check_file f $MKDIR
DATE=$(which date) && func_check_file f $DATE
CHOWN=$(which chown) && func_check_file f $CHOWN
SLEEP=$(which sleep) && func_check_file f $SLEEP
FIND=$(which find)  && func_check_file f $FIND
TOUCH=$(which touch) &&  func_check_file f $TOUCH
TAR=$(which tar) && func_check_file f $TAR
GZIP=$(which gzip) && func_check_file f $GZIP
AWK=$(which awk) && func_check_file f $AWK
RSYNC=$(which rsync)&& func_check_file f $RSYNC

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
# * Usage: myxtrabackupex [OPTIONS]
# *        myxtrbackupex.sh -c cfg_file -o backup -t full
# *   -c : configure file
# *   -o : operation [ backup | recover ]
# *   -t : type [ full | incre ], default is full.
# *   -h : help
# */

main

exit 0
