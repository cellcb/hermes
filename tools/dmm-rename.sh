#!/bin/bash
# DESC: DMM视频文件重命名工具 - 从JSON提取信息生成CSV映射文件

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 获取脚本所在目录的父目录（hermes根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_ROOT="$(dirname "$SCRIPT_DIR")"
PYTHON_SCRIPT="${HERMES_ROOT}/process_json_rename.py"

# 检查 Python 脚本是否存在
if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo -e "${RED}错误: 找不到 Python 脚本: $PYTHON_SCRIPT${NC}" >&2
    exit 1
fi

# 检查 uv 是否可用
if ! command -v uv &> /dev/null; then
    echo -e "${RED}错误: 未找到 uv，请先安装: mise use -g uv@latest${NC}" >&2
    exit 1
fi

# 检查 Playwright chromium 浏览器是否已安装
check_playwright_browser() {
    if ! uv run --with playwright python -c "from playwright.sync_api import sync_playwright; p = sync_playwright().start(); p.chromium.executable_path; p.stop()" 2>/dev/null; then
        echo -e "${YELLOW}Playwright chromium 未安装，正在下载...${NC}"
        uv run --with playwright python -m playwright install chromium
    fi
}

# 显示帮助信息
show_help() {
    echo -e "${CYAN}===== DMM视频文件重命名工具 =====${NC}"
    echo ""
    echo -e "${YELLOW}功能:${NC}"
    echo "  从JSON文件中读取视频信息，访问DMM网站获取演员名称，"
    echo "  并生成包含重命名映射的CSV文件。"
    echo ""
    echo -e "${YELLOW}用法:${NC}"
    echo "  $0 <JSON文件> [选项]"
    echo ""
    echo -e "${YELLOW}选项:${NC}"
    echo "  -o, --output <文件>       输出CSV文件路径 (默认: rename_output.csv)"
    echo "  --min-delay <秒>          请求之间的最小延迟 (默认: 1.0)"
    echo "  --max-delay <秒>          请求之间的最大延迟 (默认: 3.0)"
    echo "  -v, --verbose             显示详细输出信息"
    echo "  -h, --help                显示此帮助信息"
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo "  $0 sample.json"
    echo "  $0 sample.json -o output.csv"
    echo "  $0 sample.json --verbose"
    echo "  $0 sample.json -o output.csv -v --min-delay 2 --max-delay 5"
    echo ""
    echo -e "${BLUE}提示: 需要 uv (mise use -g uv@latest)，首次使用会自动下载 chromium${NC}"
}

# 处理参数
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

# 检查是否是帮助命令
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# 检查 Playwright 浏览器
check_playwright_browser

# 执行 Python 脚本，传递所有参数
echo -e "${CYAN}启动 DMM 重命名工具...${NC}"
echo ""

uv run "$PYTHON_SCRIPT" "$@"
exit_code=$?

# 根据退出码显示结果
echo ""
if [ $exit_code -eq 0 ]; then
    echo -e "${GREEN}✓ 处理完成${NC}"
else
    echo -e "${RED}✗ 处理失败 (退出码: $exit_code)${NC}"
fi

exit $exit_code
