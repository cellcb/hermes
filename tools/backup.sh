#!/bin/bash
# DESC: 备份重要文件和目录

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 默认配置
DEFAULT_BACKUP_DIR="$HOME/backups"
DEFAULT_SOURCE_DIRS=(
    "$HOME/Documents"
    "$HOME/Desktop"
    "$HOME/.ssh"
    "$HOME/.zshrc"
    "$HOME/.bashrc"
)

show_help() {
    echo -e "${BLUE}备份工具${NC}"
    echo ""
    echo -e "${YELLOW}用法:${NC} $0 [选项]"
    echo ""
    echo -e "${YELLOW}选项:${NC}"
    echo "  -d, --dest DIR    指定备份目标目录 (默认: $DEFAULT_BACKUP_DIR)"
    echo "  -s, --source DIR  添加要备份的源目录"
    echo "  -l, --list        列出默认备份的目录"
    echo "  -h, --help        显示此帮助信息"
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo "  $0                        # 使用默认设置备份"
    echo "  $0 -d /path/to/backup     # 指定备份目录"
    echo "  $0 -s /path/to/source     # 添加额外的源目录"
    echo "  $0 -l                     # 列出默认备份目录"
}

list_sources() {
    echo -e "${BLUE}默认备份目录:${NC}"
    for dir in "${DEFAULT_SOURCE_DIRS[@]}"; do
        if [ -e "$dir" ]; then
            echo -e "  ${GREEN}✓${NC} $dir"
        else
            echo -e "  ${RED}✗${NC} $dir (不存在)"
        fi
    done
}

perform_backup() {
    local backup_dir="$1"
    shift
    local source_dirs=("$@")
    
    # 创建备份目录
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    local backup_path="${backup_dir}/backup_${timestamp}"
    
    echo -e "${YELLOW}创建备份目录: $backup_path${NC}"
    mkdir -p "$backup_path"
    
    # 执行备份
    for source in "${source_dirs[@]}"; do
        if [ -e "$source" ]; then
            echo -e "${BLUE}备份: $source${NC}"
            if [ -d "$source" ]; then
                cp -r "$source" "$backup_path/"
            elif [ -f "$source" ]; then
                cp "$source" "$backup_path/"
            fi
            echo -e "${GREEN}✓ 完成${NC}"
        else
            echo -e "${RED}跳过: $source (不存在)${NC}"
        fi
    done
    
    # 创建备份信息文件
    {
        echo "备份时间: $(date)"
        echo "备份目录: $backup_path"
        echo "源目录:"
        for source in "${source_dirs[@]}"; do
            echo "  - $source"
        done
    } > "$backup_path/backup_info.txt"
    
    echo ""
    echo -e "${GREEN}备份完成!${NC}"
    echo -e "${YELLOW}备份位置: $backup_path${NC}"
    
    # 显示备份大小
    local backup_size=$(du -sh "$backup_path" | cut -f1)
    echo -e "${BLUE}备份大小: $backup_size${NC}"
}

main() {
    local backup_dir="$DEFAULT_BACKUP_DIR"
    local source_dirs=("${DEFAULT_SOURCE_DIRS[@]}")
    local custom_sources=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dest)
                backup_dir="$2"
                shift 2
                ;;
            -s|--source)
                custom_sources+=("$2")
                shift 2
                ;;
            -l|--list)
                list_sources
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}未知参数: $1${NC}" >&2
                show_help
                exit 1
                ;;
        esac
    done
    
    # 添加自定义源目录
    if [ ${#custom_sources[@]} -gt 0 ]; then
        source_dirs+=("${custom_sources[@]}")
    fi
    
    echo -e "${BLUE}开始备份操作...${NC}"
    perform_backup "$backup_dir" "${source_dirs[@]}"
}

main "$@" 