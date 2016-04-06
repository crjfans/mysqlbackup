#!/bin/bash
########################################################################
# script name: mysqlbackup.sh                                          #
# function: use this script to make mysql backups                      #
# useage: mysqlbackup.sh -a [-e -d -e ...]                             #
# version: v0.1                                                        #
# created date: 2016/1/6                                               #
# author: JayZhou                                                      #
########################################################################

#set -e: if the execution result of then instruction is not equle 0 ,then exit automatically
#set -e
#set -u: if the variable to be used is not be define,you will get an error message.
set -u
PREFIX_ERROR="ERROR"
PREFIX_WARNING="WARNING"
PREFIX_NOTICE="NOTICE"
EXIT_NORMAL=0
EXIT_ERROR=1
CONFIG_DIR=/etc
CONFIG_FILE=${CONFIG_DIR}/mysqlbackup.cfg
TEMP_FILE_FLAG=temp
CONFIG_FILE_TEMP=${CONFIG_FILE}.${TEMP_FILE_FLAG}
BACKUP_START_MSG='echo [`date +%Y%m%d-%H:%M:%S`]:START to backup...'
BACKUP_FINISH_MSG='echo [`date +%Y%m%d-%H:%M:%S`]:FINISH backup!'
TIME='date +%Y%m%d'

########################################################################
# routine name: usage_notes
# function: to show how to use the script
########################################################################
function usage_notes()
{
echo "  Usage: `basename $0` [OPTION] [DB1 DB2...] [TABLE1 TABLE2...] [...]"
echo "  Options:
    -a           Generate backups of all databases.
    -e           Generate backups of each database.
    -d value[s]  Generate backups of single/multi database[s].
                 Example: -d 'mydb1 mydb2'
    -t value[s]  Generate backups of single/multi table[s] of single database.
                 Example: -t 'mydb1 mytable1'
    -b           Generate backups of binlog for each database.
    -h           Generate backups of binlog use copy command.
    -c value     Clean up dump backups beyond n(n must be integer) days ago.
                 Example: -c 7
    -f value     Clean up binlog backups beyond n(n must be integer) days ago.
                 Example: -f 7
    -g           Flush binary logs
    -p           Create mysql password for dumping
  Options must be given as -option ['value1 [value2] ...'] or -option value, not -option=value.
"
exit 0
}

########################################################################
# routine name: exec_msg
# function: to judge whether the command called executed successfully
########################################################################
function exec_msg()
{
	EXEC_MSG_STATUS=$1
	EXEC_MSG_SUCCESS=`echo $2 | awk -F"@" '{print $1}'`
	EXEC_COMMAND_SUCCESS=`echo $2 | awk -F"@" '{print $2}'`
	EXEC_MSG_ERROR=`echo $3 | awk -F"@" '{print $1}'`
	EXEC_COMMAND_ERROR=`echo $3 | awk -F"@" '{print $2}'`
        if [ ${EXEC_MSG_STATUS} -eq 0 ]; then
        	if [ ! -z ${EXEC_MSG_SUCCESS:0:1} ]; then
                	echo "${PREFIX_NOTICE}:${EXEC_MSG_SUCCESS}"
			if [ ! -z ${EXEC_COMMAND_SUCCESS:0:1} ]; then
                		eval ${EXEC_COMMAND_SUCCESS}
			fi
		fi
        else
        	if [ ! -z ${EXEC_MSG_ERROR:0:1} ]; then
                	echo "${PREFIX_ERROR}:${EXEC_MSG_ERROR}"
			if [ ! -z ${EXEC_COMMAND_ERROR:0:1} ]; then
                		eval ${EXEC_COMMAND_ERROR}
			fi
		fi
                exit $EXIT_ERROR
        fi
}

########################################################################
# routine name: create_passwd
# function: create password file for dumping
########################################################################
function create_passwd()
{
	if [ ! -d $DIR_PASSWD ]; then
		mkdir -p $DIR_PASSWD
	fi
        echo -n "Please enter MySQL(user=root)'s password:"
        read -s -a MYSQL_PASSWD
	echo ""
	$CMD_MYSQL -uroot -p$MYSQL_PASSWD -N -s -e "select user()" >/dev/null 2>&1
	exec_msg "$?" "" "the password of root is wrong!"
	echo "root $MYSQL_PASSWD" |  $CMD_OPENSSL aes-128-cbc -k $HOSTNAME -base64 > $FILE_PASSWD && chmod 600 $FILE_PASSWD
	exec_msg "$?" "create the password file successfully!" ""
}

########################################################################
# routine name: create_config_file
# function: create a template config file
########################################################################
function create_config_file()
{
        #initialize config file
        if [ ! -w $CONFIG_DIR ]; then
                echo "$PREFIX_ERROR:create $CONFIG_FILE fail,no privilege to write $CONFIG_DIR!"
                exit $EXIT_ERROR
        fi
        echo "$PREFIX_ERROR:Not found ${CONFIG_FILE} ,create a template now..."
        echo '#mysql data directory
DIR_MYSQL="/var/lib/mysql"

#the directory where you want to save the mysql dumping files
DIR_BACKUP="/tmp/backupdb"

#the directory where you want to save the mysql binlog files
DIR_BACKUP_BINLOG="$DIR_BACKUP/binlog"

#the directory where you want to save the password of mysql
DIR_PASSWD="$DIR_MYSQL/etc"

#the file you want to save the password of mysql
FILE_PASSWD="$DIR_PASSWD/passwordfile"

#the file contain all the names of binlog files
FILE_BINLOG_INDEX="$DIR_MYSQL/mysql-bin.index"

#the location of the "mysqldump" command
CMD_MYSQLDUMP="/usr/bin/mysqldump"

#the location of the "mysqlbinlog" command
CMD_MYSQLBINLOG="/usr/bin/mysqlbinlog"

#the location of the "mysql" command
CMD_MYSQL="/usr/bin/mysql"

#the location of the "openssl" command used to encrypt password
CMD_OPENSSL="/usr/bin/openssl"

#the databases specified will be dumped
LIST_INCLUDE_DB_DUMP="(mydb1|mydb2|mydb3)"

#the binlog files backups of databases specified will be generated
LIST_INCLUDE_DB_BINLOG="(mydb1|mydb2|mydb3)"

#the socket file of mysql you want to connect
SOCKET="/var/lib/mysql/mysql.sock"' > $CONFIG_FILE_TEMP
        echo "$PREFIX_NOTICE:create $CONFIG_FILE_TEMP successfully!"
        echo "$PREFIX_WARNING:you need to [1]change the file name from $CONFIG_FILE_TEMP to $CONFIG_FILE [2]change the default values against your actual conditions!"
        exit $EXIT_NORMAL
}

########################################################################
# routine name: check_init_value
# function: check initial variables
########################################################################
function check_init_value()
{
	#check password file
	if [ ! -f $FILE_PASSWD ]; then
		echo "$PREFIX_ERROR:Not found the password file,please create it by: $0 -p"
		exit 0
	fi
	#check backup dir
	if [ ! -d $DIR_BACKUP ]; then
		echo "$PREFIX_WARNING:not found the backup directory,create it now..."
		mkdir -p $DIR_BACKUP
		exec_msg "$?" "create backup directory successfully!" ""
	fi
}

########################################################################
# routine name: init_var
# function: import variables in mysqlbackup.cnf
########################################################################
function init_var()
{
        if [ -r $CONFIG_FILE ]; then
                #import variables to current environment
                . $CONFIG_FILE 
		exec_msg "$?" "" "Initialize variables failed!"
        elif [ -r $CONFIG_FILE_TEMP ]; then
		echo "${PREFIX_ERROR}:you must ensure all variables in $CONFIG_FILE_TEMP are correct,and then change the name of $CONFIG_FILE_TEMP to $CONFIG_FILE"
		exit 1
        else
		if [ ! -f $CONFIG_FILE ]; then
			create_config_file
		else
                	echo "$PREFIX_ERROR:You have no permission to read $CONFIG_FILE !"
			exit 0
		fi
        fi
}

########################################################################
# routine name: flush_bin_log
# function: Initialize the CMD_DUMP command
########################################################################
function flush_bin_log()
{
        #get user and password from password file
        USER=`cat $FILE_PASSWD | $CMD_OPENSSL aes-128-cbc -d -k $HOSTNAME -base64 | awk '{print $1}'`
        PASSWD=`cat $FILE_PASSWD | $CMD_OPENSSL aes-128-cbc -d -k $HOSTNAME -base64 | awk '{print $2}'`
        #if turned on the log_bin,add a parameter:'--master-data=2' to CMD_DUMP
        `$CMD_MYSQL -u$USER -p$PASSWD -N -s -e "flush binary logs"`
        exec_msg "$?" "successfully flush binary logs!" "failed to flush binary logs! check your password!"
}

########################################################################
# routine name: init_dump
# function: Initialize the CMD_DUMP command
########################################################################
function init_dump()
{
	#get user and password from password file
	USER=`cat $FILE_PASSWD | $CMD_OPENSSL aes-128-cbc -d -k $HOSTNAME -base64 | awk '{print $1}'`
	PASSWD=`cat $FILE_PASSWD | $CMD_OPENSSL aes-128-cbc -d -k $HOSTNAME -base64 | awk '{print $2}'`
	#if turned on the log_bin,add a parameter:'--master-data=2' to CMD_DUMP
	LOGBIN_STATUS=`$CMD_MYSQL -u$USER -p$PASSWD -N -s -e "SHOW VARIABLES LIKE 'log_bin'" | awk '{print $2}'`
	exec_msg "$?" "" "failed to get the mysql variable:log_bin! check your password!"
	if [ $LOGBIN_STATUS = "ON" ]; then
		#flush logs and get binlog position
		MASTER='--master-data=2'
	else
		MASTER=' '
	fi
	#Initialize the CMD_DUMP command
	#--master-data=1 -F -d --skip-add-drop-table
	CMD_DUMP="$CMD_MYSQLDUMP -u$USER -p$PASSWD --skip-add-drop-table -x -R $MASTER --socket=$SOCKET --default-character-set=utf8"
	CMD_DUMP_FLUSH_BINLOG="$CMD_MYSQLDUMP -u$USER -p$PASSWD --skip-add-drop-table -F -x -R $MASTER --socket=$SOCKET --default-character-set=utf8"
}

########################################################################
# routine name: backup_all
# function: generate backup for all databases
########################################################################
function backup_all()
{
	init_dump
	DUMP_FILE=${DIR_BACKUP}/`${TIME}`.${HOSTNAME}.all.sql
	eval ${BACKUP_START_MSG}
	$CMD_DUMP_FLUSH_BINLOG -A  > $DUMP_FILE
	exec_msg "$?" "generate backup:$DUMP_FILE successfully!" "fail to generate backup!@rm -rf $DUMP_FILE"
	DUMP_FILE_NEW=${DIR_BACKUP}/`tail -n 1 $DUMP_FILE |awk '{print $5"."$6}'`.${HOSTNAME}.all.sql
	mv $DUMP_FILE $DUMP_FILE_NEW
	gzip -f $DUMP_FILE_NEW
	exec_msg "$?" "" "fail to compress backup!"
	eval ${BACKUP_FINISH_MSG}
}

########################################################################
# routine name: backup_each
# function: generate backup for each database
########################################################################
function backup_each()
{
	init_dump
	eval $BACKUP_START_MSG
	for db in $($CMD_MYSQL -u$USER -p$PASSWD -N -s -e "SHOW DATABASES"|egrep -w $LIST_INCLUDE_DB_DUMP)
	do
		DUMP_FILE=${DIR_BACKUP}/`${TIME}`.${HOSTNAME}.${db}.sql
		$CMD_DUMP $db --databases > $DUMP_FILE
		exec_msg "$?" "generate backup:$DUMP_FILE successfully!" "fail to generate backup!@rm -rf $DUMP_FILE"
		DUMP_FILE_NEW=${DIR_BACKUP}/`tail -n 1 $DUMP_FILE |awk '{print $5"."$6}'`.${HOSTNAME}.${db}.sql
		mv $DUMP_FILE $DUMP_FILE_NEW
		gzip -f $DUMP_FILE_NEW
		exec_msg "$?" "" "fail to compress backup!"
	done
	eval ${BACKUP_FINISH_MSG}
	flush_bin_log
}

########################################################################
# routine name: backup_db
# function: generate backup for database[s] selected
########################################################################
function backup_db()
{
	init_dump
	#use "grep" to remove head spaces and tail spaces,use "sed" to replace spaces between strings to one colon
	DUMP_FILE_POSTFIX=`echo "${OPTARG}" | grep -o "[^ ]\+\( \+[^ ]\+\)*" | sed 's/[ ][ ]*/:/g'`.sql
	DUMP_FILE=${DIR_BACKUP}/`${TIME}`.${DUMP_FILE_POSTFIX}
	eval $BACKUP_START_MSG
	$CMD_DUMP_FLUSH_BINLOG --databases $OPTARG > $DUMP_FILE
	exec_msg "$?" "generate backup:$DUMP_FILE successfully!" "fail to generate backup!@rm -rf $DUMP_FILE"
	DUMP_FILE_NEW=${DIR_BACKUP}/`tail -n 1 $DUMP_FILE | awk '{print $5"."$6}'`.${DUMP_FILE_POSTFIX}
	mv $DUMP_FILE $DUMP_FILE_NEW
	gzip -f $DUMP_FILE_NEW
	exec_msg "$?" "" "fail to compress backup!"
	eval ${BACKUP_FINISH_MSG}
}

########################################################################
# routine name: backup_dt
# function: generate backup for database table[s]
########################################################################
function backup_dt()
{
	init_dump
	#use "grep" to remove head spaces and tail spaces,use "sed" to replace spaces between strings to one colon
	DUMP_TB=`echo "${OPTARG}" | grep -o "[^ ]\+\( \+[^ ]\+\)*" | sed 's/[ ][ ]*/:/g'|awk -F":" '{$1="";print}'|grep -o "[^ ]\+\( \+[^ ]\+\)*" | sed 's/[ ][ ]*/:/g'`
	DUMP_DB=`echo "${OPTARG}" | grep -o "[^ ]\+\( \+[^ ]\+\)*" | sed 's/[ ][ ]*/:/g'|awk -F":" '{print $1}'`
	DUMP_FILE_POSTFIX=${HOSTNAME}.${DUMP_DB}.${DUMP_TB}.sql
	DUMP_FILE=${DIR_BACKUP}/`${TIME}`.${DUMP_FILE_POSTFIX}
	$CMD_DUMP $OPTARG > $DUMP_FILE
	exec_msg "$?" "generate backup:$DUMP_FILE successfully!" "fail to generate backup!@rm -rf $DUMP_FILE"
	DUMP_FILE_NEW=${DIR_BACKUP}/`tail -n 1 $DUMP_FILE |awk '{print $5"."$6}'`.${DUMP_FILE_POSTFIX}
	mv $DUMP_FILE $DUMP_FILE_NEW
	gzip -f $DUMP_FILE_NEW
	exec_msg "$?" "" "fail to compress backup!"
	eval ${BACKUP_FINISH_MSG}
}

########################################################################
# routine name: backup_binlog
# function: generate backup for binlog
########################################################################
function backup_binlog()
{
	USER=`cat $FILE_PASSWD | $CMD_OPENSSL aes-128-cbc -d -k $HOSTNAME -base64 | awk '{print $1}'`
	PASSWD=`cat $FILE_PASSWD | $CMD_OPENSSL aes-128-cbc -d -k $HOSTNAME -base64 | awk '{print $2}'`
	BACPUP_BINLOG_START_TIME=$(date -d "24 hour ago $(date +%Y%m%d)" +%Y-%m-%d\ %H:%M:%S)
	BACPUP_BINLOG_STOP_TIME=$(date -d "1 second ago $(date +%Y%m%d)" +%Y-%m-%d\ %H:%M:%S)
	#check whether the binlog backup dir exists,and create one
	if [ ! -d $DIR_BACKUP_BINLOG ]; then
                echo "$PREFIX_NOTICE:create the binlog backup directory [$DIR_BACKUP_BINLOG] now..."
                mkdir -p $DIR_BACKUP_BINLOG
                exec_msg "$?" "create binlog backup directory successfully!" ""
        fi
	#check whether the binlog index file exists
	if [ ! -r ${FILE_BINLOG_INDEX} ]; then
                exec_msg "1" "" "the file ${FILE_BINLOG_INDEX} is not found,please check ${CONFIG_FILE} or my.cnf file."
        fi
	eval $BACKUP_START_MSG
	for db in $($CMD_MYSQL -u$USER -p$PASSWD -N -s -e "SHOW DATABASES"|egrep -w $LIST_INCLUDE_DB_BINLOG)
	do
		BACKUP_BINLOG_FILE=${DIR_BACKUP_BINLOG}/$(date -d "24 hour ago" +%Y%m%d).${HOSTNAME}.${db}.binlog
		#clean the BACKUP_BINLOG_FILE
		> $BACKUP_BINLOG_FILE
		for BINLOG_FILE in $(awk -F'/' '{print $NF}' $FILE_BINLOG_INDEX)
		do
			BINLOG_FILE=$(dirname ${FILE_BINLOG_INDEX})/$BINLOG_FILE
			$CMD_MYSQLBINLOG -d $db --start-datetime="$BACPUP_BINLOG_START_TIME" --stop_datetime="$BACPUP_BINLOG_STOP_TIME" $BINLOG_FILE  >> $BACKUP_BINLOG_FILE
			exec_msg "$?" "" "fail to generate binlog backup,from ${BINLOG_FILE} to ${BACKUP_BINLOG_FILE}!@rm -rf $BACKUP_BINLOG_FILE"
			gzip -f $BACKUP_BINLOG_FILE
			exec_msg "$?" "" "fail to compress binlog backup!"
		done
		exec_msg "$?" "generate binlog backup:$BACKUP_BINLOG_FILE successfully!" ""
	done
	eval ${BACKUP_FINISH_MSG}
}

########################################################################
# routine name: backup_binlog_file
# function: copy binlog files
########################################################################
function backup_binlog_file()
{
        #check whether the binlog backup dir exists,and create one
        if [ ! -d $DIR_BACKUP_BINLOG ]; then
                echo "$PREFIX_NOTICE:create the binlog backup directory [$DIR_BACKUP_BINLOG] now..."
                mkdir -p $DIR_BACKUP_BINLOG
                exec_msg "$?" "create binlog backup directory successfully!" ""
        fi
        #check whether the binlog index file exists
        if [ ! -r ${FILE_BINLOG_INDEX} ]; then
                exec_msg "1" "" "the file ${FILE_BINLOG_INDEX} is not found,please check ${CONFIG_FILE} or my.cnf file."
        fi
	#find begin and end index of binlog file to backup
	BACK_BINLOG_INDEX=$DIR_BACKUP_BINLOG/mysql-bin-backup.index
	if [ -r $BACK_BINLOG_INDEX ];then
		BACKED_BINLOG_FILE=$(tail -n 1 $BACK_BINLOG_INDEX)
		BACK_BINLOG_INDEX_BEGIN_NUM=$(grep -n "$BACKED_BINLOG_FILE" $FILE_BINLOG_INDEX | awk -F':' '{print $1}')
		if [ -z $BACK_BINLOG_INDEX_BEGIN_NUM ];then
			BACK_BINLOG_INDEX_BEGIN_NUM=0
		fi
	else
		BACK_BINLOG_INDEX_BEGIN_NUM=0
	fi
	BACK_BINLOG_INDEX_END_NUM=$(wc -l ${FILE_BINLOG_INDEX} | awk '{print $1}')
	BINLOG_FILE=""
	BINLOG_LAST_CHANGE_TIME=""
	#begin backup binlog file
        eval $BACKUP_START_MSG
        for BINLOG_FILE in $(cat $FILE_BINLOG_INDEX | awk "NR > $BACK_BINLOG_INDEX_BEGIN_NUM && NR < $BACK_BINLOG_INDEX_END_NUM")
        do
        	BINLOG_FILE=$(dirname ${FILE_BINLOG_INDEX})/$BINLOG_FILE
		BINLOG_LAST_CHANGE_TIME=$(stat ${BINLOG_FILE}|grep "Modify"|cut -d " " -f 2,3|cut -d "." -f 1|sed 's/ /./g')
        	BACKUP_BINLOG_FILE=$DIR_BACKUP_BINLOG/${BINLOG_LAST_CHANGE_TIME}.${HOSTNAME}.`basename ${BINLOG_FILE}`
        	cp $BINLOG_FILE $BACKUP_BINLOG_FILE
        	exec_msg "$?" "" "fail to generate binlog backup:fail to copy $BINLOG_FILE to $DIR_BACKUP_BINLOG"
		echo `basename ${BINLOG_FILE}` >> $BACK_BINLOG_INDEX
		gzip -f $BACKUP_BINLOG_FILE
		exec_msg "$?" "" "fail to compress binlog backup!"
		exec_msg "$?" "generate binlog backup:${BACKUP_BINLOG_FILE} successfully!" ""
	done
	if [ -z $BINLOG_FILE ];then
		echo "$PREFIX_NOTICE:no binlog file need to be backup."
	fi
        eval ${BACKUP_FINISH_MSG}
}

########################################################################
# routine name: backup_dump_clean
# function: clean up dumping backups beyond n days
########################################################################
function backup_dump_clean()
{
	DELETE_CNT=`find ${DIR_BACKUP} -mtime +$OPTARG -type f  | wc -l`
	if [ ${DELETE_CNT} -gt 0 ]; then
		echo "$PREFIX_NOTICE:find ${DELETE_CNT} dumping-backups $OPTARG days ago from ${DIR_BACKUP}, need to delete."
		find ${DIR_BACKUP} -mtime +$OPTARG -type f |xargs -i rm {} -f
		exec_msg "$?" "clean up ${DELETE_CNT} dumping backup files successfully!" "fail to clean up the dumping backup files!"
	else
		echo "$PREFIX_NOTICE:dumping-backups $OPTARG days ago are not found in ${DIR_BACKUP}, need not to delete."
	fi
}


########################################################################
# routine name: backup_binlog_clean
# function: clean up binlog backups beyond n days
########################################################################
function backup_binlog_clean()
{
        DELETE_CNT=`find ${DIR_BACKUP_BINLOG} -mtime +$OPTARG -type f  | wc -l`
	if [ ${DELETE_CNT} -gt 0 ]; then
		echo "$PREFIX_NOTICE:find ${DELETE_CNT} binlog-backups $OPTARG days ago from ${DIR_BACKUP_BINLOG}, need to delete."
	        find ${DIR_BACKUP_BINLOG} -mtime +$OPTARG -type f |xargs -i rm {} -f
	        exec_msg "$?" "clean ${DELETE_CNT} binlog backup files successfully!" "fail to clean the binlog backup files!"
	else
		echo "$PREFIX_NOTICE:binlog-backups $OPTARG days ago are not found in ${DIR_BACKUP_BINLOG,} need not to delete."
	fi
}

########################################################################
# script entry
########################################################################
if [ $# -eq 0 ]; then
        usage_notes
else
        init_var
        while getopts :aed:t:bhc:f:pg varname
        do
		case $varname in
                	a)  check_init_value; backup_all; ;;
                	e)  check_init_value; backup_each; ;;
                	d)  check_init_value; backup_db; ;;
                	t)  check_init_value; backup_dt; ;;
                	b)  check_init_value; backup_binlog; ;;
                	h)  check_init_value; backup_binlog_file; ;;
                	c)  check_init_value; backup_dump_clean; ;;
                	f)  check_init_value; backup_binlog_clean; ;;
                	g)  check_init_value; flush_bin_log; ;;
                	p)  create_passwd; ;;
                	*)  echo "$PREFIX_ERROR:wrong parameters"; usage_notes;
		esac
	done
fi
