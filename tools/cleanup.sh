#!/bin/bash
# DESC: 清理临时文件、缓存和日志

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 清理目标配置
CLEANUP_TARGETS=(
    "$HOME/.Trash"
    "$HOME/Downloads/*.tmp"
    "$HOME/.cache"
    "/tmp"
    "$HOME/Library/Caches" # macOS specific
    "$HOME/.npm/_cacache"
    "$HOME/.yarn/cache"
)

show_help() {
    echo -e "${BLUE}系统清理工具${NC}"
    echo ""
    echo -e "${YELLOW}用法:${NC} $0 [选项]"
    echo ""
    echo -e "${YELLOW}选项:${NC}"
    echo "  -a, --all         清理所有目标 (默认)"
    echo "  -s, --safe        安全模式 (只清理明确的临时文件)"
    echo "  -d, --dry-run     预览模式 (只显示将要删除的文件)"
    echo "  -l, --list        列出清理目标"
    echo "  -h, --help        显示此帮助信息"
    echo ""
    echo -e "${YELLOW}清理目标:${NC}"
    echo "  • 垃圾箱"
    echo "  • 临时下载文件"
    echo "  • 系统缓存"
    echo "  • NPM/Yarn 缓存"
    echo "  • 浏览器缓存"
    echo ""
    echo -e "${RED}警告: 清理操作不可逆，请谨慎使用${NC}"
}

get_size() {
    local path="$1"
    if [ -e "$path" ]; then
        du -sh "$path" 2>/dev/null | cut -f1 || echo "0B"
    else
        echo "0B"
    fi
}

list_targets() {
    echo -e "${BLUE}清理目标列表:${NC}"
    echo ""
    
    local total_size=0
    
    for target in "${CLEANUP_TARGETS[@]}"; do
        if [[ "$target" == *"*"* ]]; then
            # 处理通配符路径
            local dir=$(dirname "$target")
            local pattern=$(basename "$target")
            if [ -d "$dir" ]; then
                local count=$(find "$dir" -maxdepth 1 -name "$pattern" 2>/dev/null | wc -l)
                local size=$(find "$dir" -maxdepth 1 -name "$pattern" -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1 || echo "0B")
                echo -e "  ${CYAN}$target${NC}"
                echo -e "    文件数: $count, 大小: $size"
            else
                echo -e "  ${RED}$target (目录不存在)${NC}"
            fi
        else
            local size=$(get_size "$target")
            if [ -e "$target" ]; then
                echo -e "  ${GREEN}$target${NC} - $size"
            else
                echo -e "  ${RED}$target (不存在)${NC}"
            fi
        fi
    done
}

clean_path() {
    local path="$1"
    local dry_run="$2"
    local safe_mode="$3"
    
    if [[ "$path" == *"*"* ]]; then
        # 处理通配符路径
        local dir=$(dirname "$path")
        local pattern=$(basename "$path")
        
        if [ -d "$dir" ]; then
            local files=$(find "$dir" -maxdepth 1 -name "$pattern" 2>/dev/null)
            if [ -n "$files" ]; then
                echo -e "${BLUE}清理: $path${NC}"
                if [ "$dry_run" = "true" ]; then
                    echo "$files" | while read -r file; do
                        echo -e "  ${YELLOW}[预览] 将删除: $file${NC}"
                    done
                else
                    echo "$files" | while read -r file; do
                        rm -f "$file" && echo -e "  ${GREEN}✓ 删除: $file${NC}"
                    done
                fi
            fi
        fi
    else
        if [ -e "$path" ]; then
            local size=$(get_size "$path")
            echo -e "${BLUE}清理: $path${NC} ($size)"
            
            if [ "$dry_run" = "true" ]; then
                echo -e "  ${YELLOW}[预览] 将删除${NC}"
            else
                if [ -d "$path" ]; then
                    if [ "$safe_mode" = "true" ]; then
                        # 安全模式：只删除明确的缓存文件
                        find "$path" -name "*.cache" -o -name "*.tmp" -o -name "*.log" | while read -r file; do
                            rm -f "$file" && echo -e "  ${GREEN}✓ 删除文件: $file${NC}"
                        done
                    else
                        rm -rf "$path" && echo -e "  ${GREEN}✓ 删除目录${NC}"
                    fi
                else
                    rm -f "$path" && echo -e "  ${GREEN}✓ 删除文件${NC}"
                fi
            fi
        else
            echo -e "${YELLOW}跳过: $path (不存在)${NC}"
        fi
    fi
}

perform_cleanup() {
    local dry_run="$1"
    local safe_mode="$2"
    
    echo -e "${CYAN}开始清理操作...${NC}"
    if [ "$dry_run" = "true" ]; then
        echo -e "${YELLOW}[预览模式] 只显示将要删除的文件${NC}"
    fi
    if [ "$safe_mode" = "true" ]; then
        echo -e "${YELLOW}[安全模式] 只清理明确的临时文件${NC}"
    fi
    echo ""
    
    for target in "${CLEANUP_TARGETS[@]}"; do
        clean_path "$target" "$dry_run" "$safe_mode"
    done
    
    echo ""
    if [ "$dry_run" = "true" ]; then
        echo -e "${BLUE}预览完成。使用不带 -d 参数的命令执行实际清理。${NC}"
    else
        echo -e "${GREEN}清理完成!${NC}"
        
        # 显示剩余空间
        echo -e "${YELLOW}磁盘空间信息:${NC}"
        df -h "$HOME" | tail -1 | awk '{print "  可用空间: " $4 " / " $2}'
    fi
}

main() {
    local dry_run="false"
    local safe_mode="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                # 默认行为，清理所有
                shift
                ;;
            -s|--safe)
                safe_mode="true"
                shift
                ;;
            -d|--dry-run)
                dry_run="true"
                shift
                ;;
            -l|--list)
                list_targets
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
    
    # 确认操作（除非是预览模式）
    if [ "$dry_run" = "false" ]; then
        echo -e "${RED}警告: 此操作将永久删除临时文件和缓存${NC}"
        echo -e "${YELLOW}是否继续? [y/N]${NC}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}操作已取消${NC}"
            exit 0
        fi
    fi
    
    perform_cleanup "$dry_run" "$safe_mode"
}

main "$@" 