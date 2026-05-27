#!/bin/bash

set -e  

KEY_DIR="$HOME/.ssh"
PRIVATE_KEY="$KEY_DIR/id_ed25519"
PUBLIC_KEY="$KEY_DIR/id_ed25519.pub"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

detect_ssh_service() {
    if systemctl list-units --full -all | grep -q "sshd.service"; then
        echo "sshd"
    elif systemctl list-units --full -all | grep -q "ssh.service"; then
        echo "ssh"
    else
        echo "sshd"  
    fi
}

backup_existing_keys() {
    if [ -f "$PRIVATE_KEY" ] || [ -f "$PUBLIC_KEY" ]; then
        BACKUP_DIR="$KEY_DIR/backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        [ -f "$PRIVATE_KEY" ] && cp "$PRIVATE_KEY" "$BACKUP_DIR/"
        [ -f "$PUBLIC_KEY" ] && cp "$PUBLIC_KEY" "$BACKUP_DIR/"
        [ -f "$KEY_DIR/authorized_keys" ] && cp "$KEY_DIR/authorized_keys" "$BACKUP_DIR/"
        
        echo -e "${YELLOW}>>> 已备份现有密钥到: $BACKUP_DIR${NC}"
        return 0
    fi
    return 1
}

generate_keys() {
    local key_password=""
    local force_mode="${1:-false}"
    
    echo ">>> 正在生成 SSH 密钥对 (算法: ed25519)..."

    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"

    if [ "$force_mode" != "true" ]; then
        echo -e "${YELLOW}【安全建议】为私钥设置密码可以提供额外保护${NC}"
        echo -e "${YELLOW}即使私钥泄露，攻击者也无法直接使用（需要破解密码）${NC}"
        echo ""

        while true; do
			read -s -p "请输入私钥密码（直接回车表示不设置密码）: " key_password </dev/tty
            echo ""

            if [ -n "$key_password" ]; then
                local confirm_password=""
                read -s -p "请再次输入密码确认: " confirm_password < /dev/tty
                echo ""
                if [ "$key_password" != "$confirm_password" ]; then
                    echo -e "${RED}>>> 密码不匹配，请重新输入${NC}"
                    continue
                fi
            fi
            break
        done

        if [ -z "$key_password" ]; then
            echo -e "${RED}⚠️  警告：私钥将无密码保护！${NC}"
            echo -e "${RED}任何获得此私钥的人都能访问您的服务器${NC}"
            echo ""

            while true; do
                read -p "确认要继续使用无密码私钥吗？(y/n): " confirm < /dev/tty
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo ">>> 继续生成无密码密钥..."
                    break
                elif [[ "$confirm" =~ ^[Nn]$ ]]; then
                    echo ">>> 已取消密钥生成"
                    exit 1
                else
                    echo -e "${GREEN}>>> 请输入 y（继续）或 n（取消）${NC}"
                fi
            done
        else
            echo -e "${GREEN}>>> 将使用密码保护私钥${NC}"
        fi
    fi

    if [ -z "$key_password" ]; then
        ssh-keygen -t ed25519 -N '' -f "$PRIVATE_KEY" -q <<< y
    else
        ssh-keygen -t ed25519 -N "$key_password" -f "$PRIVATE_KEY" -q <<< y
    fi

    chmod 600 "$PRIVATE_KEY"
    chmod 644 "$PUBLIC_KEY"

    cat "$PUBLIC_KEY" >> "$KEY_DIR/authorized_keys"
    chmod 600 "$KEY_DIR/authorized_keys"

    echo -e "${GREEN}>>> SSH 密钥对生成完毕${NC}"
    echo ""

    echo -e "${YELLOW}============================================${NC}"
    echo -e "${RED}【请立即保存以下私钥内容】${NC}"
    echo -e "${YELLOW}新建文本文档，复制以下内容粘贴进去保存，随后修改文件名为【id_ed25519】${NC}"
    echo -e "${YELLOW}============================================${NC}"
    cat "$PRIVATE_KEY"
    echo -e "${YELLOW}============================================${NC}"
    echo ""

    echo -e "${RED}【对应公钥内容】${NC}"
    echo -e "${YELLOW}============================================${NC}"
    cat "$PUBLIC_KEY"
    echo -e "${YELLOW}============================================${NC}"
    echo ""
}
configure_ssh() {
    local force_mode="${1:-false}"
    local ssh_service=$(detect_ssh_service)
  
	if [ ! -w "/etc/ssh/sshd_config" ]; then
    echo -e "${RED}>>> 无法写入 /etc/ssh/sshd_config${NC}"
    exit 1
	fi
	
	if [ ! -s "$KEY_DIR/authorized_keys" ]; then
    echo -e "${RED}>>> 错误：authorized_keys 为空，无法禁用密码登录${NC}"
    echo -e "${YELLOW}>>> 请先生成或添加公钥${NC}"
    exit 1
	fi
	
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}>>> 错误：需要 root 权限修改 SSH 配置${NC}"
        echo -e "${YELLOW}>>> 请使用 sudo 运行此脚本${NC}"
        echo -e "${YELLOW}>>> 示例: sudo $0 ${@}${NC}"
        exit 1
    fi

    echo ">>> 备份 /etc/ssh/sshd_config 到 /etc/ssh/sshd_config.bak"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    echo ">>> 正在修改 SSH 配置..."

    sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config

    grep -q "^PubkeyAuthentication" /etc/ssh/sshd_config || echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
    grep -q "^PasswordAuthentication" /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config

    echo -e "${GREEN}>>> SSH 配置已修改 (PasswordAuthentication no)${NC}"

    echo ">>> 检查 SSH 配置语法..."
    if ! sshd -t; then
        echo -e "${RED}>>> SSH 配置语法错误！${NC}"
        echo -e "${YELLOW}>>> 正在回滚配置...${NC}"
        cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        systemctl restart "$ssh_service"
        echo -e "${RED}>>> 已回滚到原始配置${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}>>> SSH 配置语法正确${NC}"

    echo ">>> 重启 SSH 服务..."
    systemctl restart "$ssh_service"

    echo -e "${GREEN}>>> SSH 服务已重启 (服务名: $ssh_service)${NC}"

    if [ "$force_mode" != "true" ]; then
        echo ""
        echo -e "${YELLOW}============================================${NC}"
        echo -e "${YELLOW}【重要】SSH 配置已更改，密码登录已禁用！${NC}"
        echo -e "${YELLOW}============================================${NC}"
        echo -e "${RED}请在 60 秒内打开【新终端】测试 SSH 登录！${NC}"
        echo -e "${RED}如果测试失败，脚本将自动回滚配置${NC}"
        echo ""

        read -p "按回车键开始 60 秒倒计时..." < /dev/tty
        
        echo -e "${YELLOW}>>> 等待 60 秒，请在另一终端测试 SSH 登录...${NC}"
        for i in {60..1}; do
            printf "\r>>> 剩余 %3d 秒" $i
            sleep 1
        done
        echo ""
        
        echo -e "${YELLOW}>>> 请在另一个终端中测试 SSH 连接${NC}"
        echo ""

        while true; do
            read -p "SSH 测试是否成功？(y/n): " test_result < /dev/tty
            
            if [[ "$test_result" =~ ^[Yy]$ ]]; then
                echo -e "${GREEN}>>> 测试成功，保留配置${NC}"
                break
            elif [[ "$test_result" =~ ^[Nn]$ ]]; then
                echo -e "${RED}>>> 用户确认测试失败，正在回滚配置...${NC}"
                cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
                systemctl restart "$ssh_service"
                echo -e "${YELLOW}>>> 已回滚到原始配置，密码登录已恢复${NC}"
                exit 1
            else
                echo -e "${RED}>>> 请输入 y（成功）或 n（失败）${NC}"
            fi
        done
    fi
}
show_keys_only() {
    if [ -f "$PRIVATE_KEY" ] && [ -f "$PUBLIC_KEY" ]; then
        echo -e "${YELLOW}============================================${NC}"
        echo -e "${RED}【现有私钥内容】${NC}"
        echo -e "${YELLOW}============================================${NC}"
        cat "$PRIVATE_KEY"
        echo -e "${YELLOW}============================================${NC}"
        echo ""
        echo -e "${RED}【现有公钥内容】${NC}"
        echo -e "${YELLOW}============================================${NC}"
        cat "$PUBLIC_KEY"
        echo -e "${YELLOW}============================================${NC}"
		echo -e "${RED}【安全提示】${NC}"
		echo "请勿在公共场合或共享屏幕时显示私钥内容！"
        echo ""
        return 0
    else
        echo -e "${RED}>>> 未找到完整的密钥对，无法显示。${NC}"
        return 1
    fi
}

do_generate() {
    local force_mode="${1:-false}"
    
    if [ -f "$PRIVATE_KEY" ] || [ -f "$PUBLIC_KEY" ]; then
        echo -e "${YELLOW}>>> 准备重新生成密钥对...${NC}"
        
        local old_pub_key=""
        [ -f "$PUBLIC_KEY" ] && old_pub_key=$(cat "$PUBLIC_KEY" 2>/dev/null || echo "")
        
        backup_existing_keys
        rm -f "$PRIVATE_KEY" "$PUBLIC_KEY"
        
        if [ -n "$old_pub_key" ] && [ -f "$KEY_DIR/authorized_keys" ]; then
            local temp_file=$(mktemp)
            grep -vF "$old_pub_key" "$KEY_DIR/authorized_keys" > "$temp_file" 2>/dev/null || true
            mv "$temp_file" "$KEY_DIR/authorized_keys"
            chmod 600 "$KEY_DIR/authorized_keys"
            echo -e "${GREEN}>>> 已从 authorized_keys 中移除旧公钥${NC}"
        fi
    fi
    
    generate_keys "$force_mode"
    configure_ssh "$force_mode"
}

interactive_mode() {
    local force_mode="${1:-false}"
    
    if [ -f "$PRIVATE_KEY" ] || [ -f "$PUBLIC_KEY" ]; then
        echo -e "${YELLOW}============================================${NC}"
        echo -e "${YELLOW}检测到已有 SSH 密钥对${NC}"
        echo -e "${YELLOW}============================================${NC}"
        [ -f "$PRIVATE_KEY" ] && echo "私钥: $PRIVATE_KEY (存在)"
        [ -f "$PUBLIC_KEY" ] && echo "公钥: $PUBLIC_KEY (存在)"
        echo ""
        echo "请选择操作："
        echo "1. 重新生成密钥对（会覆盖现有密钥，旧密钥将被备份）"
        echo "2. 仅显示现有密钥内容（不修改任何文件）"
        echo "3. 保留现有密钥，仅配置 SSH"
        echo "4. 退出"
        echo ""

        while true; do
            read -p "请输入选项 [1/2/3/4]: " choice < /dev/tty
            
            case $choice in
                1)
                    echo ""
                    do_generate "$force_mode"
                    break
                    ;;
                2)
                    echo ""
                    show_keys_only
                    exit 0
                    ;;
                3)
                    echo ""
                    echo -e "${YELLOW}>>> 保留现有密钥，仅配置 SSH${NC}"
                    configure_ssh "$force_mode"
                    break
                    ;;
                4)
                    echo ">>> 退出脚本"
                    exit 0
                    ;;
                *)
                    echo -e "${RED}>>>请输入 1、2、3 或 4${NC}"
                    echo ""
                    ;;
            esac
        done
    else
        generate_keys "$force_mode"
        configure_ssh "$force_mode"
    fi
}
FORCE_MODE=false
ACTION=""


while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--generate)
            ACTION="generate"
            shift
            ;;
        -s|--show)
            ACTION="show"
            shift
            ;;
        -c|--configure)
            ACTION="configure"
            shift
            ;;
        --force)
            FORCE_MODE=true
            shift
            ;;
    esac
done

case "${ACTION}" in
    generate)
        do_generate "$FORCE_MODE"
        ;;
    show)
        show_keys_only
        exit 0
        ;;
    configure)
        configure_ssh "$FORCE_MODE"
        ;;
    interactive|"")
        interactive_mode "$FORCE_MODE"
        ;;
esac

if [[ "$ACTION" != "show" ]]; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}配置完成！${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo -e "当前用户:${GREEN} $(whoami) ${NC}"
    echo -e "私钥路径:${GREEN} $PRIVATE_KEY ${NC}"
    echo -e "公钥路径:${GREEN} $PUBLIC_KEY ${NC}"
    echo ""
    echo -e "${RED}【重要警告】${NC}"
    echo "1. 密码登录已被禁用！"
    echo "2. 请务必将上面显示的私钥内容完整保存到本地计算机"
    echo "3. 如果丢失私钥，您将无法登录此服务器！"
    echo ""
    echo "如果私钥设置了密码，连接时会提示输入密码"
    echo "确认新终端可以正常登录后，再关闭当前会话。"
    echo -e "${GREEN}============================================${NC}"
fi
