myxtrabackupex
==============

This is a extented shell script for mysql hot backup(full/increment) base on xtrabckup

MySQL热备操作指南
一、备份
 1) 设置配置文件 (myback.cfg)
    首先要创建基础目录
    /*
    * 全局环境变量: 备份工具路径
    */
    CMD_DIR="/data1/tools" # 工具基础目录
    BACKUP_CMD_DIR=${CMD_DIR}"/xtrabackup/bin" # 设置xtrabackup命令安装路径
    BACKUP_CMD=xtrabackup # Innodb热备命令
    BACKUP_SCRIPT=innobackupex # 官方备份脚本
    WORK_DIR="/data1/databak" # 数据基础目录
    BASE_DIR=${WORK_DIR}"/base" # 备份操作base目录, 备份和恢复都需要用到这个目录
    BACKUP_DIR=${WORK_DIR}"/data" # 备份数据目录, 备份和恢复都需要用到这个目录
    MySQL_USER=mysql # MySQL运行帐号
    MySQL_GROUP=mysql # MySQL运行属组

 2) 初始化操作
    a. 确定备份程序位置BACKUP_CMD_DIR和命令名
    b. 创建目录WORK_DIR/BASE_DIR/BACKUP_DIR
 3) 设置备份操作参数
    #/* # * 请注意这部分是用于备份操作的
    #*/
    MySQL_BASE=/data1/mysql5510_3307 # 进行备份的数据库base目录
    HOST=127.0.0.1 # MySQL服务器ip，注意这里是用于备份操作的
    PORT=3307 # MySQL服务器端口
    SOCKET=/tmp/mysql_${PORT}.sock # unix套接字
    DATABASE=cutedb # 数据库名
    USER=root # MySQL用户，要求有file权限
    PASSWD=ebo9@9pig # 密码
    DELTA_PREFIX= # 增量备份目录的前缀
    DELTA_SUFFIX="_delta" # 增量备份目录的后缀
    MySQL_CONF=$MySQL_BASE/my_${PORT}.cnf # 待恢复数据库配置文件my.cnf # 记得在[mysqld]小结要设置datadir这个参数，否则恢复操作无法正确执行
    KEEP=2 # 保留7天的数据库备份
    IOPS_LIMIT=200 # Xtraback 限制IOS

 4) 执行备份操作
    cd /data1/tools/xtrabackup/bin; 
    全量: sh ./myxtrabackupex.sh -f mybakcup.cfg -a backup
    增量: sh ./myxtrabackupex.sh -f mybakcup.cfg -a backup -t incre

 5) 检查备份执行结果
    a. 备份文件是否存在(/data1/databak/data)
    b. 查看操作日志(/data1/databak/data/${TimeStamp}.log)


二、恢复
 1) 准备工作
    a. 准备一个空的MySQL实例，并启动
    b. 将备份文件压缩包复制到数据备份目录(/data1/databak/data)下，如果是增量备份，要将全量和增量备份都复制过来，包括备份操作日志文件

 2) 设置基础目录配置参数
    如果不存在，要先创建WORK_DIR/BASE_DIR/BACKUP_DIR/RESTORE_BACKUP_DIR目录

 3) 设置恢复操作参数
    #/* # * 请注意这部分是用于恢复操作的 # */
    RESTORE_MySQL_BASE=/data1/mysql5510_3407 # 待恢复数据库base目录
    RESTORE_HOST=127.0.0.1 # 待恢复数据库ip
    RESTORE_PORT=3407 # 待恢复数据库的端口
    RESTORE_SOCKET=/tmp/mysql_${RESTORE_PORT}.sock # 待恢复数据库的unix套接字
    RESTORE_USER=root # MySQL用户，要求有file权限
    RESTORE_PASSWD=ebo9@9pig # 密码
    RESTORE_MySQL_CONF=$RESTORE_MySQL_BASE/my_${RESTORE_PORT}.cnf # 待恢复数据库配置文件my.cnf,记得在[mysqld]小结 # 设置datadir这个参数，否则恢复操作无法正确执行
    RESTORE_BACKUP_DIR=$WORK_DIR"/recover" # 备份数据目录

 4) 根据实际情况设置恢复操作要处理的备份文件
    如:20110405_0920_3307 / 20110406_0920_3307可以通过下面配置来
    RESTORE_DELTA_PREFIX="201104" # 备份数据文件名的前缀
    RESTORE_DELTA_SUFFIX="_3307" # 备份数据文件名的后缀,恢复增量备份时后缀名+DELTA_SUFFIX
    RESTORE_BACKUP_LIST=05_0920,06_0920 # 通过列表来指定备份数据文件名有变化的部分，中间用半角逗号,做分隔符

 5) 执行恢复操作
    全量: sh ./myxtrabackupex.sh -f mybakcup.cfg -a restore -t full
    增量: sh ./myxtrabackupex.sh -f mybakcup.cfg -a restore -t incre

 6) 检查输出和日志
    /data1/databak/data/recover/${TimeStamp}.log

 7) 如果日志先生恢复成功，则可以重启MySQL服务了
    重启后登录MySQL检查数据是否正确
