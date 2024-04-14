#!/bin/bash
set -eo pipefail

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 用户执行此脚本"
    exit 1
fi

source /etc/profile

#### 函数定义 ####
# 检查系统版本
_system_version=$(cat /etc/issue)
function check_version {
    if [[ "$_system_version" == *"Debian GNU/Linux 10"* ]]; then
        echo "当前系统为 Debian 10 (Buster)。"
    elif [[ "$_system_version" == *"Debian GNU/Linux 11"* ]]; then
        echo "当前系统为 Debian 11 (Bullseye)。"
    elif [[ "$_system_version" == *"Debian GNU/Linux 12"* ]]; then
        echo "当前系统为 Debian 12 (Bookworm)。"
    else
        echo "当前系统不是 Debian 10、11 或 12。"
        exit 1 
    fi
}

# 检查架构
_arch=$(dpkg --print-architecture)
function check_arch {
    if [[ "$_arch" == "amd64" ]]; then
        echo "当前系统架构是 amd64。"
    elif [[ "$_arch" == "arm64" ]]; then
        echo "当前系统架构是 arm64。"
    else
        echo "当前系统架构不是 amd64 或 arm64，不受支持"
        exit 1 
    fi
}

#### 服务端主函数 ####
function install_server {
    check_version
    check_arch
    echo "安装依赖..."
    apt update -qy >> /dev/null 2>&1
    apt install net-tools curl wget unzip gzip lsof psmisc -qy >> /dev/null 2>&1
    echo "下载 Gost..."
    if [[ "$_arch" == "amd64" ]]; then
        gost_url="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz"
    elif [[ "$_arch" == "arm64" ]]; then
        gost_url="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-armv8-2.11.5.gz"
    fi
    wget -qO- $gost_url | gzip -d > /usr/local/bin/gost
    chmod +x /usr/local/bin/gost
    echo "下载 Gost 完成"
    while true; do
        read -p "请输入用来连接 Sock5 的用户名：" gostUsername
        if [ -z "$gostUsername" ]; then
            echo "用户名不能为空，请重新输入。"
        elif [[ ! "$gostUsername" =~ ^[a-z0-9]+$ ]]; then
            echo "用户名只能包含小写字母和数字，请重新输入"
        else
            break
        fi
    done
    while true; do
        read -p "请输入用来连接 Sock5 的密码：" gostPasswd
        if [ -z "$gostPasswd" ]; then
            echo "密码不能为空，请重新输入。"
        elif [[ ! "$gostPasswd" =~ ^[a-zA-Z0-9]+$ ]]; then
            echo "密码只能包含字母和数字，请重新输入"
        else
            break
        fi
    done
    while true; do
        read -p "请输入 Sock5 服务的端口号：" gostPort
        if [ -z "$gostPort" ]; then
            echo "端口号不能为空，请重新输入。"
        elif [[ ! "$gostPort" =~ ^[0-9]+$ ]]; then
            echo "端口号只能包含数字，请重新输入"
        elif [ "$gostPort" -lt 1 ] || [ "$gostPort" -gt 65535 ]; then
            echo "端口号必须在 1 到 65535 之间，请重新输入"
        else
            break
        fi
    done

    configDir="$HOME/.config/gost"
    configFile="$configDir/config.json"
    if [ ! -d "$configDir" ]; then
        mkdir -p $configDir
    fi
    if [ -f "$configFile" ]; then
        rm -f $configFile
    fi
    
    if [ -f "/etc/systemd/system/gost.service" ]; then
        rm -f /etc/systemd/system/gost.service
    fi

    cat > "$configFile" <<EOF
{
    "Debug": false,
    "Retries": 0,
    "ServeNodes": [
        "socks5://$gostUsername:$gostPasswd@:$gostPort"
    ]
}
EOF
    cat > "/etc/systemd/system/gost.service" <<EOF
[Unit]
Description=GOST PROXY SERVER
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -C $configFile
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable gost.service
    systemctl start gost.service
    echo "Gost 服务已启动，如果有任何错误，请手动检查 /etc/systemd/system/gost.service 文件是否正确。\n同时，如果你想修改 Gost 的配置，请编辑 /etc/systemd/system/gost.service 文件，接着\n执行 systemctl daemon-reload && systemctl restart gost 即可。"
    echo "\n\n如果你发现有什么问题，请手动执行查看错误信息:"  
}


#### 客户端主函数 ####
function install_client {
    check_version
    check_arch
    echo "安装依赖..."
    apt update -qy >> /dev/null 2>&1
    apt install net-tools curl wget unzip gzip iptables vim iproute2 psmisc -qy >> /dev/null 2>&1
    echo "下载 Tun2socks..."
    if [[ "$_arch" == "amd64" ]]; then
        tun2socks_url="https://github.com/xjasonlyu/tun2socks/releases/download/v2.5.2/tun2socks-linux-amd64.zip"
        t2sFileName="tun2socks-linux-amd64"
    elif [[ "$_arch" == "arm64" ]]; then
        tun2socks_url="https://github.com/xjasonlyu/tun2socks/releases/download/v2.5.2/tun2socks-linux-arm64.zip"
        t2sFileName="tun2socks-linux-arm64"
    fi
    wget -qO- $tun2socks_url -O /tmp/tun2socks.zip >> /dev/null 2>&1
    unzip -o -q /tmp/tun2socks.zip -d /usr/local/bin/
    mv /usr/local/bin/$t2sFileName /usr/local/bin/tun2socks
    chmod +x /usr/local/bin/tun2socks
    echo "下载 Tun2socks 完成"
    echo "下载 xgpl..."
    wget -qO- https://raw.githubusercontent.com/X1A0CA1/xgpl/main/xgpl > /tmp/xgpl_tmp
    echo "下载 xgpl 完成"
    current_TUNDEVICE=$(grep '^TUNDEVICE=' /tmp/xgpl_tmp | cut -d '"' -f 2)
    current_TUNIPRANGE=$(grep '^TUNIPRANGE=' /tmp/xgpl_tmp | cut -d '"' -f 2)
    current_TUNNETMASK=$(grep '^TUNNETMASK=' /tmp/xgpl_tmp | cut -d '"' -f 2)
    current_ETHDEV=$(grep '^ETHDEV=' /tmp/xgpl_tmp | cut -d '"' -f 2)
    current_REMOTEIP=$(grep '^REMOTEIP=' /tmp/xgpl_tmp | cut -d '"' -f 2)
    current_REMOTEPORT=$(grep '^REMOTEPORT=' /tmp/xgpl_tmp | cut -d '"' -f 2)
    current_USERNAME=$(grep '^USERNAME=' /tmp/xgpl_tmp | cut -d '"' -f 2)
    current_PASSWD=$(grep '^PASSWD=' /tmp/xgpl_tmp | cut -d '"' -f 2)
    current_BYPASSIPS=$(grep '^BYPASSIPS=(' /tmp/xgpl_tmp | cut -d '"' -f 2-3)

    read -p "请输入 tun 设备名，回车跳过 (默认值: $current_TUNDEVICE): " new_TUNDEVICE
    new_TUNDEVICE=${new_TUNDEVICE:-$current_TUNDEVICE}
    read -p "请输入 tun 设备的 IP 范围，回车跳过 (默认值: $current_TUNIPRANGE): " new_TUNIPRANGE
    new_TUNIPRANGE=${new_TUNIPRANGE:-$current_TUNIPRANGE}
    read -p "请输入 tun 设备的子网掩码，回车跳过 (默认值: $current_TUNNETMASK): " new_TUNNETMASK
    new_TUNNETMASK=${new_TUNNETMASK:-$current_TUNNETMASK}
    

    mainETHDev=$(ip route | head -n 1 | awk '{print $5}')
    ifconfigOutput=$(ifconfig)
    echo "ifconfig 输出如下：\n$ifconfigOutput"
    echo "脚本检测的主网卡是： $mainGatewayDev"
    echo "请根据 ifconfig 的的信息检查网卡是否正确，如果不正确请现在手动输入正确的值："
    read -p "请输入默认网卡名，回车跳过: " new_ETHDEV
    new_ETHDEV=${new_ETHDEV:-$mainETHDev}

    read -p "请输入 Gost 服务端的 IP 地址 (默认值: $current_REMOTEIP): " new_REMOTEIP
    new_REMOTEIP=${new_REMOTEIP:-$current_REMOTEIP}
    while true; do
        read -p "请输入 Gost 服务端的端口号：" new_REMOTEPORT
        if [ -z "$new_REMOTEPORT" ]; then
            echo "端口号不能为空，请重新输入。"
        elif [[ ! "$new_REMOTEPORT" =~ ^[0-9]+$ ]]; then
            echo "端口号只能包含数字，请重新输入"
        elif [ "$new_REMOTEPORT" -lt 1 ] || [ "$new_REMOTEPORT" -gt 65535 ]; then
            echo "端口号必须在 1 到 65535 之间，请重新输入"
        else
            break
        fi
    done
    new_REMOTEPORT=${new_REMOTEPORT:-$current_REMOTEPORT}

    while true; do
        read -p "请输入 Gost 服务端的用户名：" new_USERNAME
        if [ -z "$new_USERNAME" ]; then
            echo "用户名不能为空，请重新输入。"
        elif [[ ! "$new_USERNAME" =~ ^[a-z0-9]+$ ]]; then
            echo "用户名只能包含小写字母和数字，请重新输入"
        else
            break
        fi
    done
    new_USERNAME=${new_USERNAME:-$current_USERNAME}

    while true; do
        read -p "请输入 Gost 服务端的密码：" new_PASSWD
        if [ -z "$new_PASSWD" ]; then
            echo "密码不能为空，请重新输入。"
        elif [[ ! "$new_PASSWD" =~ ^[a-zA-Z0-9]+$ ]]; then
            echo "密码只能包含字母和数字，请重新输入"
        else
            break
        fi
    done
    new_PASSWD=${new_PASSWD:-$current_PASSWD}


    sed "s/TUNDEVICE=\"$current_TUNDEVICE\"/TUNDEVICE=\"$new_TUNDEVICE\"/; \
        s/TUNIPRANGE=\"$current_TUNIPRANGE\"/TUNIPRANGE=\"$new_TUNIPRANGE\"/; \
        s/TUNNETMASK=\"$current_TUNNETMASK\"/TUNNETMASK=\"$new_TUNNETMASK\"/; \
        s/ETHDEV=\"$current_ETHDEV\"/ETHDEV=\"$new_ETHDEV\"/; \
        s/REMOTEIP=\"$current_REMOTEIP\"/REMOTEIP=\"$new_REMOTEIP\"/; \
        s/REMOTEPORT=\"$current_REMOTEPORT\"/REMOTEPORT=\"$new_REMOTEPORT\"/; \
        s/USERNAME=\"$current_USERNAME\"/USERNAME=\"$new_USERNAME\"/; \
        s/PASSWORD=\"$current_PASSWORD\"/PASSWORD=\"$new_PASSWORD\"/" \
        /tmp/xgpl_tmp > /usr/local/bin/xgpl

    chmod +x /usr/local/bin/xgpl
    rm -f /tmp/xgpl_tmp

    cat > "/etc/systemd/system/xgpl.service" <<EOF
[Unit]
Description=XiaoCai Global Proxy for Linux Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xgpl start
ExecStop=/usr/local/bin/xgpl stop
ExecReload=/usr/local/bin/xgpl restart
restartRestart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xgpl 
    systemctl start xgpl
    echo "xgpl 服务已启动，如果有任何错误，请手动检查 /usr/local/bin/xgpl 文件是否正确。\n同时，如果你想修改配置，请编辑 /usr/local/bin/xgpl 文件，接着\n执行 systemctl restart xgpl.service 即可。"
}

#### 主程序 ####
echo "请选择要执行的操作："
echo "1. 安装服务端"
echo "2. 安装客户端"
read -p "请输入选项编号：" choice

case $choice in
    1)
        install_server
        ;;
    2)
        install_client
        ;;
    *)
        echo "选项错误，请重新运行脚本。"
        exit 1
esac
