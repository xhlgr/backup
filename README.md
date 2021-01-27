# backup.sh
* 原始代码地址：https://github.com/teddysun/across/blob/master/backup.sh
* 由于fastuser只有dropbox备份，在国内操作不便，故找到此脚本备份到其他网盘，我也不懂语法，根据需要暴改少少内容，但结果貌似没问题。此处仅作记录，慎用。
* 修改：
  * 改用7z压缩和加密文件，需要已安装7z.
  * 增加删除服务器的备份文件(可选)。随后根据远程网盘的文件的文件名的时间删除超过n天的文件(原来是根据本地)。
  * 删除FTP相关内容。
  * 不懂：`if [ "${MYSQL_DATABASE_NAME[@]}" == "" ];`的@暴改成0算了，否则报错参数过多不会处理。此时必须CONFIG有`MYSQL_DATABASE_NAME[0]=""`才会备份所有数据库。
* rclone：安装rclone到vps，然后配置一个远程网盘，例如onedrive：https://rclone.org/opendrive/ ，把名称写到RCLONE_NAME即可。我把log提示的google改成onedrive(并不影响，改了好看)，rclone支持的网盘应该都可以用来备份。
