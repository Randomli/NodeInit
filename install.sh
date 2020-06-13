#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# Created by henry on 2020/6/5
# email 17607168727@163.com


clear_passwd(){
    suffix=`date  +"_%Y%m%d%H%M%S.bak"`
    # 清空hosts文件中的密码信息
    cp node/hosts ./hosts$suffix
    echo "hosts$suffix" >./.install_temp
    awk '{print $1 " " $2 }' node/hosts > tmp
    cat tmp >node/hosts
    rm -rf tmp
}

ssh_trust(){
    if [ -f "./.install_temp" ];then
      cat `cat .install_temp` >node/hosts
    fi
    yum install -y expect
    # 判断id_rsa密钥文件是否存在
    if [ ! -f ~/.ssh/id_rsa ];then
        ssh-keygen -t rsa -P "" -f ~/.ssh/id_rsa
    else
        echo "id_rsa has created ..."
    fi
    #分发到各个节点,这里分发到host文件中的主机中.
    while read line;do
        if [ -n "$line" ];then
            hostname=`echo $line | cut -d " " -f 2`
            ip=`echo $line | cut -d " " -f 1`
            passwd=`echo $line | cut -d " " -f 3`

            expect << EOF
                set timeout 10
                spawn ssh-copy-id root@$ip
                expect {
                "yes/no" { send "yes\n";exp_continue }
                "password" { send "$passwd\n" }
                }
                expect "password" { send "$passwd\n" }
EOF
        fi
    done <  node/hosts
    clear_passwd

}



init_cluster(){
  # shellcheck disable=SC2095
  while read line; do
    if [ -n "$line" ];then
      hostname=`echo $line | cut -d " " -f 2`
      ip=`echo $line | cut -d " " -f 1`
      echo $hostname $ip
      scp -r node/  root@$ip:/tmp
      ssh root@$ip << remotessh
hostnamectl set-hostname $hostname
cd  /tmp/node/ && sh ./node_init.sh
exit
remotessh
    fi
  done  < node/hosts
}

init_node(){
  # shellcheck disable=SC2095
  # 跳过salt主机
  while read line; do
    if [ -n "$line" ];then
      hostname=`echo $line | cut -d " " -f 2`
      ip=`echo $line | cut -d " " -f 1`
      if [[  $hostname != "salt"  ]];then
        scp -r node/ root@$ip:/tmp
        ssh root@$ip << remotessh
hostnamectl set-hostname $hostname
cd  /tmp/node/ && sh ./node_init.sh
exit
remotessh
      fi
    fi
  done  < node/hosts
}

help(){
  echo -e "
### 注意事项:
  运行脚本前请检查hosts文件中的ip、主机名和密码是否对应
  部署过程中会使用到salt-stack,执行当前脚本的机器为salt-master
  hosts文件中需要指定salt主机的ip(别写本地回环地址),例如：
  192.168.1.106  salt  12345

  **脚本运行完毕以后会删除hosts中的密码信息**
### 执行方法:
  **输入1 选择 init cluster 会初始化整个k8s集群环境**
  **输入2 选择 init node    会初始化单个节点环境**
  "
}



main(){
  help
  select var in "init cluster"  "init node" "help"; do
    break;
  done
  case $var in
  "init cluster")
    echo "脚本将根据hosts文件中指定的主机，初始化整个集群"
    ssh_trust
    init_cluster
    echo "--初始化完成，服务器将重启-- "
    reboot
  ;;
  "init node")
    echo "脚本将根据hosts文件中指定的主机，初始化单个节点"
    ssh_trust
    init_node
    echo "--初始化完成，服务器将重启-- "
    reboot
  ;;
  *)
  help
  ;;
  esac

}

main
