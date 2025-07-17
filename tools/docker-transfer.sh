#!/bin/bash
# DESC: Docker镜像传输工具 - 下载镜像并传输到远程服务器

# Docker镜像传输脚本
# 功能：下载Docker镜像，上传到指定服务器并加载
# 参数：镜像名 主机名

# 颜色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示使用方法
show_usage() {
    echo -e "${BLUE}Docker镜像传输工具${NC}"
    echo ""
    echo -e "${YELLOW}用法:${NC} hermes docker-transfer <镜像名> <主机名> [选项]"
    echo "      或: $0 <镜像名> <主机名> [选项]"
    echo ""
    echo -e "${YELLOW}参数:${NC}"
    echo "  镜像名    要下载的Docker镜像名称（如：nginx:latest）"
    echo "  主机名    目标服务器的主机名或IP地址"
    echo ""
    echo -e "${YELLOW}选项:${NC}"
    echo "  -u, --user        SSH用户名（默认：root）"
    echo "  -p, --port        SSH端口（默认：22）"
    echo "  -k, --key         SSH私钥文件路径"
    echo "  -d, --dir         远程临时目录（默认：/tmp）"
    echo "  -f, --force       强制覆盖已存在的镜像文件"
    echo "  -c, --cleanup     传输完成后删除本地tar文件"
    echo "  -h, --help        显示此帮助信息"
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo "  hermes docker-transfer nginx:latest 192.168.1.100"
    echo "  hermes docker-transfer nginx:latest server.example.com -u ubuntu -p 2222"
    echo "  hermes docker-transfer nginx:latest 192.168.1.100 -k ~/.ssh/id_rsa -c"
    echo ""
    echo -e "${BLUE}功能说明:${NC}"
    echo "  1. 从Docker Hub下载指定镜像（支持linux/amd64平台）"
    echo "  2. 将镜像保存为tar文件"
    echo "  3. 通过SSH上传到远程服务器"
    echo "  4. 在远程服务器上加载镜像"
    echo "  5. 自动清理临时文件"
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "命令 '$1' 未找到，请确保已安装"
        exit 1
    fi
}

# 检查必要的工具
check_requirements() {
    log_info "检查必要工具..."
    check_command "docker"
    check_command "ssh"
    check_command "scp"
    log_success "所有必要工具已安装"
}

# 清理函数
cleanup() {
    if [[ "$CLEANUP" == "true" && -f "$LOCAL_TAR_PATH" ]]; then
        log_info "清理本地tar文件: $LOCAL_TAR_PATH"
        rm -f "$LOCAL_TAR_PATH"
    fi
}

# 信号处理
trap cleanup EXIT

# 默认参数
SSH_USER="root"
SSH_PORT="22"
SSH_KEY=""
REMOTE_DIR="/tmp"
FORCE="false"
CLEANUP="false"

# 参数解析
parse_args() {
    if [[ $# -lt 2 ]]; then
        log_error "参数不足"
        show_usage
        exit 1
    fi

    IMAGE_NAME="$1"
    HOST_NAME="$2"
    shift 2

    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--user)
                SSH_USER="$2"
                shift 2
                ;;
            -p|--port)
                SSH_PORT="$2"
                shift 2
                ;;
            -k|--key)
                SSH_KEY="$2"
                shift 2
                ;;
            -d|--dir)
                REMOTE_DIR="$2"
                shift 2
                ;;
            -f|--force)
                FORCE="true"
                shift
                ;;
            -c|--cleanup)
                CLEANUP="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# 构建SSH命令选项
build_ssh_options() {
    SSH_OPTIONS="-p $SSH_PORT"
    SCP_OPTIONS="-P $SSH_PORT"
    
    if [[ -n "$SSH_KEY" ]]; then
        if [[ ! -f "$SSH_KEY" ]]; then
            log_error "SSH私钥文件不存在: $SSH_KEY"
            exit 1
        fi
        SSH_OPTIONS="$SSH_OPTIONS -i $SSH_KEY"
        SCP_OPTIONS="$SCP_OPTIONS -i $SSH_KEY"
    fi
    
    # 禁用主机密钥检查（可选，用于自动化脚本）
    SSH_OPTIONS="$SSH_OPTIONS -o StrictHostKeyChecking=no"
    SCP_OPTIONS="$SCP_OPTIONS -o StrictHostKeyChecking=no"
}

# 下载Docker镜像
download_image() {
    log_info "开始下载Docker镜像: $IMAGE_NAME"
    
    if docker pull --platform linux/amd64 "$IMAGE_NAME"; then
        log_success "Docker镜像下载成功"
    else
        log_error "Docker镜像下载失败"
        exit 1
    fi
}

# 保存镜像为tar文件
save_image() {
    # 生成tar文件名
    SAFE_IMAGE_NAME=$(echo "$IMAGE_NAME" | tr '/:' '_')
    LOCAL_TAR_PATH="/tmp/${SAFE_IMAGE_NAME}.tar"
    REMOTE_TAR_PATH="${REMOTE_DIR}/${SAFE_IMAGE_NAME}.tar"
    
    log_info "保存镜像为tar文件: $LOCAL_TAR_PATH"
    
    # 检查本地文件是否存在
    if [[ -f "$LOCAL_TAR_PATH" && "$FORCE" != "true" ]]; then
        log_warn "本地tar文件已存在: $LOCAL_TAR_PATH"
        read -p "是否覆盖? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "跳过保存步骤"
            return 0
        fi
    fi
    
    if docker save "$IMAGE_NAME" -o "$LOCAL_TAR_PATH"; then
        log_success "镜像保存成功: $LOCAL_TAR_PATH"
        # 显示文件大小
        FILE_SIZE=$(du -h "$LOCAL_TAR_PATH" | cut -f1)
        log_info "文件大小: $FILE_SIZE"
    else
        log_error "镜像保存失败"
        exit 1
    fi
}

# 上传tar文件到远程服务器
upload_image() {
    log_info "上传tar文件到远程服务器: $HOST_NAME"
    log_info "目标路径: $REMOTE_TAR_PATH"
    
    # 测试SSH连接
    log_info "测试SSH连接..."
    if ! ssh $SSH_OPTIONS "$SSH_USER@$HOST_NAME" "echo 'SSH连接测试成功'" &>/dev/null; then
        log_error "SSH连接失败，请检查主机名、用户名、端口和密钥配置"
        exit 1
    fi
    log_success "SSH连接测试成功"
    
    # 检查远程目录
    log_info "检查远程目录: $REMOTE_DIR"
    ssh $SSH_OPTIONS "$SSH_USER@$HOST_NAME" "mkdir -p $REMOTE_DIR"
    
    # 上传文件
    log_info "开始上传文件..."
    if scp $SCP_OPTIONS "$LOCAL_TAR_PATH" "$SSH_USER@$HOST_NAME:$REMOTE_TAR_PATH"; then
        log_success "文件上传成功"
    else
        log_error "文件上传失败"
        exit 1
    fi
}

# 在远程服务器加载镜像
load_image() {
    log_info "在远程服务器加载Docker镜像"
    
    # 检查远程Docker服务
    log_info "检查远程Docker服务..."
    if ! ssh $SSH_OPTIONS "$SSH_USER@$HOST_NAME" "docker --version" &>/dev/null; then
        log_error "远程服务器Docker服务不可用"
        exit 1
    fi
    log_success "远程Docker服务正常"
    
    # 加载镜像
    log_info "加载镜像: $REMOTE_TAR_PATH"
    if ssh $SSH_OPTIONS "$SSH_USER@$HOST_NAME" "docker load -i $REMOTE_TAR_PATH"; then
        log_success "镜像加载成功"
    else
        log_error "镜像加载失败"
        exit 1
    fi
    
    # 验证镜像
    log_info "验证镜像是否加载成功..."
    if ssh $SSH_OPTIONS "$SSH_USER@$HOST_NAME" "docker images | grep -q '$(echo $IMAGE_NAME | cut -d: -f1)'"; then
        log_success "镜像验证成功"
    else
        log_warn "镜像验证失败，请手动检查"
    fi
    
    # 清理远程tar文件
    log_info "清理远程tar文件"
    ssh $SSH_OPTIONS "$SSH_USER@$HOST_NAME" "rm -f $REMOTE_TAR_PATH"
}

# 主函数
main() {
    log_info "Docker镜像传输脚本开始运行..."
    
    # 解析参数
    parse_args "$@"
    
    # 显示配置信息
    echo "================================"
    log_info "配置信息:"
    echo "  镜像名称: $IMAGE_NAME"
    echo "  目标主机: $HOST_NAME"
    echo "  SSH用户: $SSH_USER"
    echo "  SSH端口: $SSH_PORT"
    echo "  远程目录: $REMOTE_DIR"
    [[ -n "$SSH_KEY" ]] && echo "  SSH密钥: $SSH_KEY"
    echo "================================"
    
    # 检查必要工具
    check_requirements
    
    # 构建SSH选项
    build_ssh_options
    
    # 执行主要步骤
    download_image
    save_image
    upload_image
    load_image
    
    log_success "Docker镜像传输完成！"
    log_info "你可以在远程服务器上使用以下命令查看镜像："
    echo "  ssh $SSH_USER@$HOST_NAME 'docker images'"
}

# 运行主函数
main "$@" 