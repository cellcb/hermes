#!/bin/bash

# ==============================================================================
# 日常工具集合 - 主入口脚本
# ==============================================================================

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/tools"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
    echo -e "${CYAN}===== 日常工具集合 =====${NC}"
    echo -e "${YELLOW}用法:${NC} $0 <工具名称> [参数...]"
    echo ""
    echo -e "${YELLOW}可用工具:${NC}"
    
    if [ -d "$TOOLS_DIR" ]; then
        for tool in "$TOOLS_DIR"/*.sh; do
            if [ -f "$tool" ]; then
                tool_name=$(basename "$tool" .sh)
                # 尝试获取工具描述（从文件第一行注释中提取）
                description=$(grep -m1 "^# DESC:" "$tool" 2>/dev/null | sed 's/^# DESC: //' || echo "无描述")
                printf "  ${GREEN}%-15s${NC} - %s\n" "$tool_name" "$description"
            fi
        done
    else
        echo "  ${RED}未找到工具目录: $TOOLS_DIR${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo "  $0 help              # 显示此帮助信息"
    echo "  $0 backup            # 执行备份操作"
    echo "  $0 cleanup           # 清理临时文件"
    echo "  $0 sysinfo           # 显示系统信息"
    echo ""
    #echo -e "${BLUE}注意: 每个工具都是独立的shell脚本，位于 tools/ 目录中${NC}"
}

# 执行指定工具
run_tool() {
    local tool_name="$1"
    shift # 移除第一个参数，剩余参数传递给工具
    
    local tool_path="${TOOLS_DIR}/${tool_name}.sh"
    
    if [ ! -f "$tool_path" ]; then
        echo -e "${RED}错误: 工具 '$tool_name' 不存在${NC}" >&2
        echo -e "${YELLOW}运行 '$0 help' 查看可用工具${NC}" >&2
        exit 1
    fi
    
    if [ ! -x "$tool_path" ]; then
        echo -e "${YELLOW}警告: 工具 '$tool_name' 没有执行权限，正在添加...${NC}"
        chmod +x "$tool_path"
    fi
    
    echo -e "${CYAN}执行工具: $tool_name${NC}"
    echo -e "${BLUE}===================${NC}"
    
    # 执行工具脚本，传递所有剩余参数
    "$tool_path" "$@"
}

# 主逻辑
main() {
    # 确保工具目录存在
    if [ ! -d "$TOOLS_DIR" ]; then
        echo -e "${YELLOW}创建工具目录: $TOOLS_DIR${NC}"
        mkdir -p "$TOOLS_DIR"
    fi
    
    # 处理参数
    if [ $# -eq 0 ] || [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_help
        exit 0
    fi
    
    # 执行指定工具
    run_tool "$@"
}

# 执行主函数
main "$@" 