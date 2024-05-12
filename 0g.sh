#!/bin/bash

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 检查并安装 Node.js 和 npm
function install_nodejs_and_npm() {
    if command -v node > /dev/null 2>&1; then
        echo "Node.js 已安装"
    else
        echo "Node.js 未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi

    if command -v npm > /dev/null 2>&1; then
        echo "npm 已安装"
    else
        echo "npm 未安装，正在安装..."
        sudo apt-get install -y npm
    fi
}

# 检查并安装 PM2
function install_pm2() {
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 已安装"
    else
        echo "PM2 未安装，正在安装..."
        npm install pm2@latest -g
    fi
}

# 检查Go环境
function check_go_installation() {
    if command -v go > /dev/null 2>&1; then
        echo "Go 环境已安装"
        return 0 
    else
        echo "Go 环境未安装，正在安装..."
        return 1 
    fi
}

# 节点安装功能
function install_node() {

    install_nodejs_and_npm
    install_pm2

    # 检查curl是否安装，如果没有则安装
    if ! command -v curl > /dev/null; then
        sudo apt update && sudo apt install curl git -y
    fi

    # 更新和安装必要的软件
    sudo apt update && sudo apt upgrade -y
    sudo apt install curl git wget htop tmux build-essential jq make lz4 gcc unzip liblz4-tool -y

    # 安装 Go
    if ! check_go_installation; then
        sudo rm -rf /usr/local/go
        curl -L https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
        source $HOME/.bash_profile
        go version
    fi

    # 安装所有二进制文件
    git clone -b v0.1.0 https://github.com/0glabs/0g-chain.git
    cd 0g-chain
    make install

    # 配置0gchaind
    export MONIKER="My_Node"
    export WALLET_NAME="wallet"

    # 获取初始文件和地址簿
    cd $HOME
    0gchaind init $MONIKER --chain-id zgtendermint_16600-1
    0gchaind config chain-id zgtendermint_16600-1
    0gchaind config node tcp://localhost:26657


    # 配置节点
    wget -O ~/.0gchain/config/genesis.json https://github.com/0glabs/0g-chain/releases/download/v0.1.0/genesis.json
    0gchaind validate-genesis
    wget https://smeby.fun/0gchaind-addrbook.json -O $HOME/.0gchain/config/addrbook.json
    
    # 配置节点
    SEEDS="c4d619f6088cb0b24b4ab43a0510bf9251ab5d7f@54.241.167.190:26656,44d11d4ba92a01b520923f51632d2450984d5886@54.176.175.48:26656,f2693dd86766b5bf8fd6ab87e2e970d564d20aff@54.193.250.204:26656,f878d40c538c8c23653a5b70f615f8dccec6fb9f@54.215.187.94:26656"
    PEERS="a8d7c5a051c4649ba7e267c94e48a7c64a00f0eb@65.108.127.146:26656,8f463ad676c2ea97f88a1274cdcb9f155522fd49@209.126.8.121:26657,75a398f9e3a7d24c6b3ba4ab71bf30cd59faee5c@95.216.42.217:26656,5a202fb905f20f96d8ff0726f0c0756d17cf23d8@43.248.98.100:26656,9d88e34a436ec1b50155175bc6eba89e7a1f0e9a@213.199.61.18:26656,2b8ee12f4f94ebc337af94dbec07de6f029a24e6@94.16.31.161:26656,52e30a030ff6ded32e7a499de6246c574f57cc27@152.53.32.51:26656"
    sed -i "s/persistent_peers = \"\"/persistent_peers = \"$PEERS\"/" $HOME/.0gchain/config/config.toml
    sed -i "s/seeds = \"\"/seeds = \"$SEEDS\"/" $HOME/.0gchain/config/config.toml


    # 使用 PM2 启动节点进程
    pm2 start 0gchaind -- start && pm2 save && pm2 startup
    
    pm2 stop 0gchaind
    SNAP_NAME=$(curl -s https://testnet.anatolianteam.com/0g/ | egrep -o ">zgtendermint_16600-1.*\.tar.lz4" | tr -d ">")
    curl -L https://testnet.anatolianteam.com/0g/${SNAP_NAME} | tar -I lz4 -xf - -C $HOME/.0gchain
    mv $HOME/.0gchain/priv_validator_state.json.backup $HOME/.0gchain/data/priv_validator_state.json 

    pm2 restart 0gchaind

    echo '====================== 安装完成,请退出脚本后执行 source $HOME/.bash_profile 以加载环境变量==========================='
    
}

# 查看0gai 服务状态
function check_service_status() {
    pm2 list
}

# 0gai 节点日志查询
function view_logs() {
    pm2 logs 0gchaind
}

# 卸载节点功能
function uninstall_node() {
    echo "你确定要卸载0gchain 节点程序吗？这将会删除所有相关的数据。[Y/N]"
    read -r -p "请确认: " response

    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载节点程序..."
            pm2 stop 0gchaind && pm2 delete 0gchaind
            rm -rf $HOME/.0gchain $HOME/0gchain $(which 0gchaind) && rm -rf 0g-chain
            echo "节点程序卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}

# 创建钱包
function add_wallet() {
    read -p "请输入你想设置的钱包名称: " wallet_name
    0gchaind keys add $wallet_name --eth
}

# 导入钱包
function import_wallet() {
    read -p "请输入你想设置的钱包名称: " wallet_name
    0gchaind keys add $wallet_name --recover --eth
}

# 查询余额
function check_balances() {
    read -p "请输入钱包地址: " wallet_address
    0gchaind query bank balances "$wallet_address"
}

# 查看节点同步状态
function check_sync_status() {
    0gchaind status 2>&1 | jq .sync_info
}

# 创建验证者
function add_validator() {

read -p "请输入您的钱包名称: " wallet_name
read -p "请输入您想设置的验证者的名字: " validator_name
read -p "请输入您的验证者详情（例如'吊毛资本'）: " details


0gchaind tx staking create-validator \
  --amount=1000000ua0gi \
  --pubkey=$(0gchaind tendermint show-validator) \
  --moniker=$validator_name \
  --chain-id=zgtendermint_16600-1 \
  --commission-rate=0.05 \
  --commission-max-rate=0.10 \
  --commission-max-change-rate=0.01 \
  --min-self-delegation=1 \
  --from=$wallet_name \
  --identity="" \
  --website="" \
  --details="$details" \
  --gas=auto \
  --gas-adjustment=1.4
}

function install_storage_node() {

    sudo apt-get update
    sudo apt-get install clang cmake build-essential git screen cargo -y


# 安装Go
    sudo rm -rf /usr/local/go
    curl -L https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    source $HOME/.bash_profile

    
# 克隆仓库
git clone https://github.com/0glabs/0g-storage-node.git

#进入对应目录构建
cd 0g-storage-node
git submodule update --init

# 构建代码
cargo build --release

#后台运行
cd run


read -p "请输入你想导入的EVM钱包私钥，不要有0x: " minerkey

sed -i "s/miner_id = \"\"/miner_id = \"$(openssl rand -hex 32)\"/" config.toml
sed -i "s/miner_key = \"\"/miner_key = \"$minerkey\"/" config.toml




screen -dmS zgs_node_session ../target/release/zgs_node --config config.toml

echo '====================== 安装完成 ==========================='
echo '===进入对应路径:/0g-storage-node/run/log，使用tail -f logs文件名，查看logs 即可========================'

}


function install_storage_kv() {

# 克隆仓库
git clone https://github.com/0glabs/0g-storage-kv.git


#进入对应目录构建
cd 0g-storage-kv
git submodule update --init

# 构建代码
cargo build --release

#后台运行
cd run

echo "请输入RPC节点信息: "
read blockchain_rpc_endpoint


cat > config.toml <<EOF
stream_ids = ["000000000000000000000000000000000000000000000000000000000000f2bd", "000000000000000000000000000000000000000000000000000000000000f009", "00000000000000000000000000"]

db_dir = "db"
kv_db_dir = "kv.DB"

rpc_enabled = true
rpc_listen_address = "127.0.0.1:6789"
zgs_node_urls = "http://127.0.0.1:5678"

log_config_file = "log_config"

blockchain_rpc_endpoint = "$blockchain_rpc_endpoint"
log_contract_address = "0x22C1CaF8cbb671F220789184fda68BfD7eaA2eE1"
log_sync_start_block_number = 670000

EOF

echo "配置已成功写入 config.toml 文件"
screen -dmS storage_kv ../target/release/zgs_kv --config config.toml

}

# 给自己地址验证者质押
function delegate_self_validator() {
read -p "请输入质押代币数量(单位为ua0gai,比如你有1000000个ua0gai，留点水给自己，输入900000回车就行): " math
read -p "请输入钱包名称: " wallet_name
0gchaind tx staking delegate $(0gchaind keys show $wallet_name --bech val -a)  ${math}ua0gi --from $wallet_name   --gas=auto --gas-adjustment=1.4 -y

}

# 查看存储节点同步状态
function check_storage_status() {
    tail -f "$(find ~/0g-storage-node/run/log/ -type f -printf '%T+ %p\n' | sort -r | head -n 1 | cut -d' ' -f2-)"
}

# 查看存储节点同步状态
function start_storage() {
cd 0g-storage-node/run && screen -dmS zgs_node_session ../target/release/zgs_node --config config.toml
echo '====================== 启动成功，请通过screen -r zgs_node_session 查询 ==========================='

}

# 转换ETH地址
function transfer_EIP() {
read -p "请输入你的钱包名称: " wallet_name
echo "0x$(0gchaind debug addr $(0gchaind keys show $wallet_name -a) | grep hex | awk '{print $3}')"

}

# 卸载节点功能
function uninstall_old_node() {
    echo "你确定要卸载0g ai 节点程序吗？这将会删除所有相关的数据。[Y/N]"
    read -r -p "请确认: " response

    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载节点程序..."
            pm2 stop evmosd && pm2 delete evmosd
            rm -rf $HOME/.evmosd $HOME/evmos $(which evmosd) && rm -rf 0g-evmos
            echo "节点程序卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}


# 主菜单
function main_menu() {
    while true; do
        clear
        echo "脚本以及教程由推特用户大赌哥 @y95277777 编写，免费开源，请勿相信收费"
        echo "=======================验证节点功能================================"
        echo "节点社区 Telegram 群组:https://t.me/niuwuriji"
        echo "节点社区 Discord 社群:https://discord.gg/GbMV5EcNWF"
        echo "退出脚本，请按键盘ctrl c退出即可"
        echo "请选择要执行的操作:"
        echo "1. 安装节点"
        echo "2. 创建钱包"
        echo "3. 导入钱包"
        echo "4. 查看钱包地址余额"
        echo "5. 查看节点同步状态"
        echo "6. 查看当前服务状态"
        echo "7. 运行日志查询"
        echo "8. 卸载节点"
        echo "9. 创建验证者"  
        echo "10. 给自己验证者地址质押代币"
        echo "11. 转换ETH地址"
        echo "=======================存储节点功能================================"
        echo "12. 创建存储节点"  
        echo "13. 查看存储节点日志"  
        echo "14. 单独启动存储节点代码，适用于需要修改存储路径等功能修改过后使用"
        echo "=======================卸载evmos测试网节点功能================================"
        echo "15. 卸载evmos验证者节点"  
        read -p "请输入选项（1-15）: " OPTION

        case $OPTION in
        1) install_node ;;
        2) add_wallet ;;
        3) import_wallet ;;
        4) check_balances ;;
        5) check_sync_status ;;
        6) check_service_status ;;
        7) view_logs ;;
        8) uninstall_node ;;
        9) add_validator ;;
        10) delegate_self_validator ;;
        11) transfer_EIP ;;
        12) install_storage_node ;;
        13) check_storage_status ;;
        14) start_storage ;;
        15) uninstall_old_node ;;

        *) echo "无效选项。" ;;
        esac
        echo "按任意键返回主菜单..."
        read -n 1
    done
    
}

# 显示主菜单
main_menu
