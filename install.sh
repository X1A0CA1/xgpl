#!/bin/bash
set -eo pipefail

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 用户执行此脚本"
    exit 1
fi

source /etc/profile

#### 函数定义 ####

# 文本颜色
RED='\033[0;31m'        # 红色
GREEN='\033[0;32m'      # 绿色
YELLOW='\033[0;33m'     # 黄色
BLUE='\033[0;34m'       # 蓝色
PURPLE='\033[0;35m'     # 紫色
CYAN='\033[0;36m'       # 青色
WHITE='\033[0;37m'      # 白色
BOLD_RED='\033[1;31m'       # 加粗红色
BOLD_GREEN='\033[1;32m'     # 加粗绿色
BOLD_YELLOW='\033[1;33m'    # 加粗黄色
BOLD_BLUE='\033[1;34m'      # 加粗蓝色
BOLD_PURPLE='\033[1;35m'    # 加粗紫色
BOLD_CYAN='\033[1;36m'      # 加粗青色
BOLD_WHITE='\033[1;37m'     # 加粗白色
BG_RED='\033[0;41m'      # 红色背景
BG_GREEN='\033[0;42m'    # 绿色背景
BG_YELLOW='\033[0;43m'   # 黄色背景
BG_BLUE='\033[0;44m'     # 蓝色背景
BG_PURPLE='\033[0;45m'   # 紫色背景
BG_CYAN='\033[0;46m'     # 青色背景
BG_WHITE='\033[0;47m'    # 白色背景
RESET='\033[0m'

# 检查系统版本
_system_version=$(cat /etc/issue)
function check_version {
    if [[ "$_system_version" == *"Debian GNU/Linux 10"* ]]; then
        echo -e "当前系统为 ${GREEN}Debian 10 (Buster)${RESET}。"
    elif [[ "$_system_version" == *"Debian GNU/Linux 11"* ]]; then
        echo -e "当前系统为 ${GREEN}Debian 11 (Bullseye)${RESET}。"
    elif [[ "$_system_version" == *"Debian GNU/Linux 12"* ]]; then
        echo -e "当前系统为 ${GREEN}Debian 12 (Bookworm)${RESET}。"
    else
        echo -e "${RED}当前系统不受支持。${RESET}"
        exit 1 
    fi
}

# 检查架构
_arch=$(dpkg --print-architecture)
function check_arch {
    if [[ "$_arch" == "amd64" ]]; then
        echo -e "当前系统架构是 ${GREEN}amd64${RESET}。"
    elif [[ "$_arch" == "arm64" ]]; then
        echo -e "当前系统架构是 ${GREEN}arm64${RESET}。"
    else
        echo -e "${RED}当前系统架构不是 amd64 或 arm64，不受支持${RESET}"
        exit 1 
    fi
}

#### 服务端主函数 ####
function install_server {
    check_version
    check_arch
    echo -e "${CYAN}安装依赖...${RESET}"
    apt update -qy >> /dev/null 2>&1
    apt install net-tools curl wget unzip gzip lsof psmisc -qy >> /dev/null 2>&1
    echo -e "${CYAN}下载 Gost...${RESET}"
    if [[ "$_arch" == "amd64" ]]; then
        gost_url="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz"
    elif [[ "$_arch" == "arm64" ]]; then
        gost_url="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-armv8-2.11.5.gz"
    fi
    wget -qO- $gost_url | gzip -d > /usr/local/bin/gost
    chmod +x /usr/local/bin/gost
    echo -e "${GREEN}下载 Gost 完成${RESET}"
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
    echo "${GREEN}Gost 服务已启动${RESET}\n如果有任何错误，请手动检查 /etc/systemd/system/gost.service 文件是否正确。\n同时，如果你想修改 Gost 的配置，请编辑 /etc/systemd/system/gost.service 文件，接着\n执行 systemctl daemon-reload && systemctl restart gost 即可。"
    echo "\n\n${YELLOW}如果你发现有什么问题，请手动执行查看错误信息:${RESET} /usr/local/bin/gost -C $configFile"  
}


#### 客户端主函数 ####
function install_client {
    check_version
    check_arch
    echo -e "${CYAN}安装依赖...${RESET}"
    apt update -qy >> /dev/null 2>&1
    apt install net-tools curl wget unzip gzip iptables vim iproute2 psmisc -qy >> /dev/null 2>&1
    echo -e "${CYAN}下载 Tun2socks...${RESET}"
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
    echo -e "${GREEN}Tun2socks 下载并安装完成.${RESET}"
    echo -e "${CYAN}下载 xgpl...${RESET}"
    wget -qO- https://raw.githubusercontent.com/X1A0CA1/xgpl/main/xgpl > /tmp/xgpl_tmp
    echo -e "${GREEN}xgpl 下载完成.${RESET}"
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
    echo "脚本检测的主网卡是： $mainETHDev"
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
    
    # 输出上述定义的变量
    echo -e "tun 设备名: ${YELLOW}$new_TUNDEVICE${RESET}"
    echo -e "tun 设备 IP 范围: ${YELLOW}$new_TUNIPRANGE${RESET}"
    echo -e "tun 设备子网掩码: ${YELLOW}$new_TUNNETMASK${RESET}"
    echo -e "默认网卡名: ${YELLOW}$new_ETHDEV${RESET}"
    echo -e "Gost 服务端 IP 地址: ${YELLOW}$new_REMOTEIP${RESET}"
    echo -e "Gost 服务端端口号: ${YELLOW}$new_REMOTEPORT${RESET}"
    echo -e "Gost 服务端用户名: ${YELLOW}$new_USERNAME${RESET}"
    echo -e "Gost 服务端密码: ${YELLOW}$new_PASSWD${RESET}"

    while true; do
        read -p "请确认输入的信息无误并继续(y/N)：" new_BYPASSIPS
        case $new_BYPASSIPS in
            [Yy]* )
                break
                ;;
            [Nn]* )
                exit 1
                ;;
            * )
                echo "请输入 y 或 n"
                ;;
        esac
    done


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
    echo -e "${GREEN}xgpl 服务已启动${RESET}\n如果有任何错误，请手动检查 /usr/local/bin/xgpl 文件是否正确。\n同时，如果你想修改配置，请编辑 /usr/local/bin/xgpl 文件，接着\n执行 systemctl restart xgpl.service 即可。"
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
