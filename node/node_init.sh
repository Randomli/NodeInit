#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# Created by henry on 2020/6/5
# email 17607168727@163.com
# 服务器标准化脚本


is_salt_master(){
   salt_master_ip=`awk '{if($2~/^salt$/)print $1}' hosts`
   for i in   `ip a |grep inet |grep -v inet6 |grep -v 127.0.0.1 |awk  '{print $2}' |awk -F/ '{print $1}'`
     do
       if [ $i == $salt_master_ip ]
         then
           echo "--检测到本节点是salt主节点--"
           return 0
       fi
   done
   return 1
}


repo_add(){
  # salt repo
  yum install -y https://mirrors.aliyun.com/saltstack/yum/redhat/salt-repo-latest-2.el7.noarch.rpm
  sed -i "s|repo.saltstack.com/mirrors.aliyun.com|saltstack|g" /etc/yum.repos.d/salt-latest.repo
  # kernel repo
  yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
  # docker-ce.repo
  yum install -y yum-utils device-mapper-persistent-data lvm2
  yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

}


ntp_config(){
  timedatectl set-timezone Asia/Shanghai
  timedatectl set-local-rtc 0

  # 注册ntp服务 同步时间
  yum install -y ntpdate
  cat > /etc/ntp.conf << EOF
  driftfile  /var/lib/ntp/drift
  pidfile   /var/run/ntpd.pid
  logfile /var/log/ntp.log
  restrict    default kod nomodify notrap nopeer noquery
  restrict -6 default kod nomodify notrap nopeer noquery
  restrict 127.0.0.1
  server 127.127.1.0
  fudge  127.127.1.0 stratum 10
  server ntp.aliyun.com iburst minpoll 4 maxpoll 10
  restrict ntp.aliyun.com nomodify notrap nopeer noquery

  server ntp1.cloud.aliyuncs.com iburst minpoll 4 maxpoll 10
  restrict ntp1.cloud.aliyuncs.com nomodify notrap nopeer noquery
  server ntp2.cloud.aliyuncs.com iburst minpoll 4 maxpoll 10
  restrict ntp2.cloud.aliyuncs.com nomodify notrap nopeer noquery
  server ntp3.cloud.aliyuncs.com iburst minpoll 4 maxpoll 10
  restrict ntp3.cloud.aliyuncs.com nomodify notrap nopeer noquery
  server ntp4.cloud.aliyuncs.com iburst minpoll 4 maxpoll 10
  restrict ntp4.cloud.aliyuncs.com nomodify notrap nopeer noquery
  server ntp5.cloud.aliyuncs.com iburst minpoll 4 maxpoll 10
  restrict ntp5.cloud.aliyuncs.com nomodify notrap nopeer noquery
  server ntp6.cloud.aliyuncs.com iburst minpoll 4 maxpoll 10
  restrict ntp6.cloud.aliyuncs.com nomodify notrap nopeer noquery
EOF

  systemctl enable ntpdate
  systemctl  restart  ntpdate
  systemctl restart rsyslog
  systemctl restart crond
}


disable_unused_service(){
 systemctl stop postfix
 systemctl disable postfix
}


add_harbor_ca(){
  mkdir -p /etc/docker/certs.d/harbor.cjdgy.com
  cp harbor.cjdgy.com_public.crt  /etc/docker/certs.d/harbor.cjdgy.com
}


install_salt_minion(){
  yum install -y salt-minion
  echo -e "
grains:
 roles:
  - minion
  " > /etc/salt/minion
  systemctl restart salt-minion
  `systemctl enable salt-minion`

}

update_minion_role(){
  sed -i "s/- minion/- master/g" /etc/salt/minion
}

install_salt_master(){
  yum install -y salt-master
  systemctl enable salt-master
  if [ ! -f /etc/salt/master.default ];then
    cp /etc/salt/master /etc/salt/master.default
  fi
  echo -e  "
auto_accept: True
file_roots:
  base:
    - /srv/salt/base
 " > /etc/salt/master
  mkdir /srv/salt/
  systemctl restart salt-master
  firewall-cmd --zone=public --add-port=4505/tcp --permanent
  firewall-cmd --zone=public --add-port=4506/tcp --permanent
}


disable_selinux(){
  setenforce 0
  sed --follow-symlinks -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
}


config_firewalld_trusted(){
  firewall-cmd --set-default-zone=trusted
  firewall-cmd --complete-reload
  iptables -F
}


add_hosts(){
  # 清空init_node脚本添加的内容
  num=0 begin=0
  while read line ; do
      ((num++))
      if [[  $line == "# GEBIN init_node add"  ]] && [[  $begin == 0  ]];then
        begin=1
        begin_num=$num
      elif [[  $line == "# END init_node add"  ]];then
        end_num=$num
      fi
  done  < /etc/hosts
  if [ -n "$begin_num" ] && [ -n "$end_num" ];then
    sed -i  "${begin_num},${end_num}d" /etc/hosts
  fi
  # 填充/etc/hosts
  echo "# GEBIN init_node add" >> /etc/hosts
  cat hosts |grep -v "^$"|grep -v "^#" >> /etc/hosts
  echo "# END init_node add" >> /etc/hosts
}

install_requirement(){
yum install -y ipvsadm

cat > /etc/rc.sysinit <<EOF
#!/bin/bash
for file in /etc/sysconfig/modules/*.modules ; do
[ -x $file ] && $file
done
EOF

cat > /etc/sysconfig/modules/br_netfilter.modules << EOF
modprobe br_netfilter
EOF
chmod 755  /etc/sysconfig/modules/br_netfilter.modules

modprobe br_netfilter
#系统参数优化/etc/sysctl.conf
cat > kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
vm.swappiness=0
# 禁止使用 swap 空间，只有当系统 OOM 时才允许使用它
vm.overcommit_memory=1
# 不检查物理内存是否够用
vm.panic_on_oom=0
# 开启 OOM
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720
EOF
cp kubernetes.conf  /etc/sysctl.d/kubernetes.conf
sysctl -p /etc/sysctl.d/kubernetes.conf
cat > /etc/sysctl.conf <<EOF
vm.swappiness = 0
net.ipv4.neigh.default.gc_stale_time = 120
# see details in https://help.aliyun.com/knowledge_detail/39428.html
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2
# see details in https://help.aliyun.com/knowledge_detail/41334.html
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
kernel.sysrq = 1

#阿里云版/etc/sysctl.conf 优化
#net.core.somaxconn = 65535
#net.core.netdev_max_backlog = 65535
#net.ipv4.tcp_syncookies = 1
#net.ipv4.tcp_max_syn_backlog = 20480
#net.ipv4.ip_local_port_range = 1024 65000
#net.ipv4.tcp_tw_reuse = 1
#net.ipv4.tcp_tw_recycle = 0
#net.ipv4.tcp_fin_timeout = 30


#内网版/etc/sysctl.conf 优化
net.ipv4.neigh.default.gc_stale_time=120
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_synack_retries = 2
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 20480
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_fin_timeout = 30
EOF
/sbin/sysctl -p

#文件打开数优化
echo ulimit -n 65535 >>/etc/profile
source /etc/profile

cat >  /etc/security/limits.conf <<EOF
*        soft    noproc 65535
*        hard    noproc 65535
*        soft    nofile 65535
*        hard    nofile 65535
EOF

mkdir /var/log/journal # 持久化保存日志的目录
mkdir /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-prophet.conf <<EOF
[Journal]
# 持久化保存到磁盘
Storage=persistent
# 压缩历史日志
Compress=yes

SyncIntervalSec=5m
RateLimitInterval=30s
RateLimitBurst=1000

# 最大占用空间 10G
SystemMaxUse=10G
# 单日志文件最大 200M
SystemMaxFileSize=200M
# 日志保存时间 2 周
MaxRetentionSec=2week
# 不将日志转发到 syslog
ForwardToSyslog=no
EOF
systemctl restart systemd-journald

}

kernel_upgrade(){

  yum install -y  --enablerepo=elrepo-kernel kernel-lt-4.4.226
  # 查看当前内核 `awk -F\' '$1=="menuentry " {print $2}' /etc/grub2.cfg`
  # 设置默认内核
  grub2-set-default "CentOS Linux (4.4.226-1.el7.elrepo.x86_64) 7 (Core)"
  # 更新grub.cfg文件
  grub2-mkconfig -o /boot/grub2/grub.cfg
}


disable_NUMA(){
  cp /etc/default/grub{,.bak}
  sed -i "s/numa=off//g" /etc/default/grub
  sed -i "s/rhgb quiet/rhgb quiet numa=off/g" /etc/default/grub
  cp /boot/grub2/grub.cfg{,.bak}
  grub2-mkconfig -o /boot/grub2/grub.cfg
}


install_docker(){
  yum install -y yum-utils device-mapper-persistent-data lvm2
  yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
  yum install -y   docker-ce
  systemctl daemon-reload
  systemctl enable  docker
  systemctl restart docker
}


install_docker_compose(){
  curl -L https://github.com/docker/compose/releases/download/1.24.1/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
}


wget_breeze_yaml(){
  curl -L https://raw.githubusercontent.com/wise2c-devops/breeze/v1.18/docker-compose-centos-aliyun.yml -o docker-compose.yml
  docker-compose up -d
}


main(){
  #添加解析记录
  add_hosts
  #添加repo
  repo_add
  #调整时区 配置ntp服务
  ntp_config
  #关闭不用的服务
  disable_unused_service
  #关闭selinux
  disable_selinux
  #关闭防火墙
  config_firewalld_trusted
  #添加harbor证书
  add_harbor_ca
  #安装minion
  install_salt_minion
  #安装依赖
  install_requirement
  #调整内核参数 升级内核
  kernel_upgrade
  #关闭NUMA
  disable_NUMA
  # 判断是不是master主机
  if is_salt_master
    then
      #安装master配置
      install_salt_master
      #修改minion角色
      update_minion_role
      #开启FORWARD链
      iptables -P FORWARD ACCEPT
      #安装docker
      install_docker
      #安装docker-compose
      install_docker_compose
      #下载breeze配置文件 启动breeze
      wget_breeze_yaml
  else
      echo "--初始化完成，服务器将重启-- "
      reboot
  fi

}


main