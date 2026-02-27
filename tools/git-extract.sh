#!/bin/bash
# DESC: 从Git提交中提取变更文件并保持目录结构

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 默认配置
DEFAULT_OUTPUT_DIR="./extracted_files"
DEFAULT_REPO_DIR="."

show_help() {
    echo -e "${BLUE}Git 提交文件提取工具${NC}"
    echo ""
    echo -e "${YELLOW}用法:${NC} $0 [选项]"
    echo ""
    echo -e "${YELLOW}选项:${NC}"
    echo "  -c, --commit <id>         提取单个提交的变更文件 (默认: HEAD)"
    echo "  -r, --range <range>       提取提交范围的变更文件 (如: commit1..commit2)"
    echo "  -o, --output <dir>        输出目录 (默认: extracted_<commit-id>_<timestamp>)"
    echo "  -d, --directory <path>    Git仓库路径 (默认: 当前目录)"
    echo "  -h, --help                显示此帮助信息"
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo "  $0                                        # 提取HEAD提交,自动命名输出目录"
    echo "  $0 -c abc123                              # 提取单个提交"
    echo "  $0 -r abc123..def456                      # 提取提交范围"
    echo "  $0 -c HEAD~5                              # 提取倒数第5个提交"
    echo "  $0 -r HEAD~10..HEAD                       # 提取最近10个提交"
    echo "  $0 -c abc123 -o /tmp/output               # 指定输出目录"
    echo "  $0 -c abc123 -d /path/to/repo             # 指定仓库路径"
    echo ""
    echo -e "${CYAN}注意:${NC}"
    echo "  - 如果文件在多次提交中被修改，只提取最新版本"
    echo "  - 已删除的文件将被跳过并记录在日志中"
    echo "  - 输出目录会包含提取信息文件 extraction_info.txt"
    echo "  - 未指定输出目录时,会自动生成包含commit ID的目录名"
}

# 验证是否为Git仓库
check_git_repo() {
    local repo_dir="$1"
    if ! git -C "$repo_dir" rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}错误: '$repo_dir' 不是有效的Git仓库${NC}" >&2
        exit 1
    fi
}

# 验证提交是否存在
check_commit_exists() {
    local repo_dir="$1"
    local commit="$2"
    if ! git -C "$repo_dir" rev-parse --verify "$commit^{commit}" > /dev/null 2>&1; then
        echo -e "${RED}错误: 提交 '$commit' 不存在${NC}" >&2
        exit 1
    fi
}

# 获取变更文件列表
get_changed_files() {
    local repo_dir="$1"
    local commit_spec="$2"

    # 根据是否包含 .. 或 ... 判断是单个提交还是范围
    if [[ "$commit_spec" == *".."* ]]; then
        # 提交范围
        git -C "$repo_dir" diff --name-only "$commit_spec"
    else
        # 单个提交
        git -C "$repo_dir" diff-tree --no-commit-id --name-only -r "$commit_spec"
    fi
}

# 提取文件
extract_files() {
    local repo_dir="$1"
    local commit_spec="$2"
    local output_dir="$3"

    echo -e "${BLUE}开始提取文件...${NC}"
    echo ""

    # 创建输出目录
    mkdir -p "$output_dir"

    # 获取变更文件列表
    local changed_files
    changed_files=$(get_changed_files "$repo_dir" "$commit_spec")

    if [ -z "$changed_files" ]; then
        echo -e "${YELLOW}没有找到变更的文件${NC}"
        return 0
    fi

    local total_files=$(echo "$changed_files" | wc -l | tr -d ' ')
    local current=0
    local extracted=0
    local skipped=0
    local deleted_files=()

    # 确定要使用的提交ID（用于提取文件内容）
    local target_commit
    if [[ "$commit_spec" == *".."* ]]; then
        # 对于范围，使用范围的结束提交
        target_commit=$(echo "$commit_spec" | sed 's/.*\.\.//')
    else
        # 单个提交
        target_commit="$commit_spec"
    fi

    # 解析为完整的commit hash
    target_commit=$(git -C "$repo_dir" rev-parse "$target_commit")

    # 逐个处理文件
    while IFS= read -r file; do
        ((current++))
        echo -e "${CYAN}[$current/$total_files]${NC} 处理: $file"

        # 创建目标目录
        local target_path="$output_dir/$file"
        local target_dir=$(dirname "$target_path")
        mkdir -p "$target_dir"

        # 尝试提取文件内容
        if git -C "$repo_dir" show "$target_commit:$file" > "$target_path" 2>/dev/null; then
            echo -e "  ${GREEN}✓ 已提取${NC}"
            ((extracted++))
        else
            # 文件可能已被删除
            echo -e "  ${YELLOW}⊘ 已跳过 (文件已删除或不存在)${NC}"
            deleted_files+=("$file")
            ((skipped++))
            rm -f "$target_path"
            # 如果目录为空则删除
            rmdir "$target_dir" 2>/dev/null || true
        fi
    done <<< "$changed_files"

    echo ""
    echo -e "${GREEN}提取完成!${NC}"
    echo -e "${BLUE}统计信息:${NC}"
    echo -e "  总文件数: $total_files"
    echo -e "  成功提取: ${GREEN}$extracted${NC}"
    echo -e "  已跳过: ${YELLOW}$skipped${NC}"

    # 创建提取信息文件
    local info_file="$output_dir/extraction_info.txt"
    {
        echo "======================================"
        echo "Git 提交文件提取信息"
        echo "======================================"
        echo ""
        echo "提取时间: $(date)"
        echo "仓库路径: $(cd "$repo_dir" && pwd)"
        echo "提交规格: $commit_spec"
        echo "目标提交: $target_commit"
        echo "输出目录: $(cd "$output_dir" && pwd)"
        echo ""
        echo "统计信息:"
        echo "  总文件数: $total_files"
        echo "  成功提取: $extracted"
        echo "  已跳过: $skipped"
        echo ""

        if [[ "$commit_spec" == *".."* ]]; then
            echo "提交范围详情:"
            git -C "$repo_dir" log --oneline "$commit_spec"
        else
            echo "提交详情:"
            git -C "$repo_dir" show --stat "$commit_spec"
        fi

        echo ""
        echo "提取的文件列表:"
        echo "$changed_files" | while IFS= read -r file; do
            if [ -f "$output_dir/$file" ]; then
                echo "  ✓ $file"
            fi
        done

        if [ ${#deleted_files[@]} -gt 0 ]; then
            echo ""
            echo "跳过的文件 (已删除):"
            for file in "${deleted_files[@]}"; do
                echo "  ⊘ $file"
            done
        fi

    } > "$info_file"

    echo ""
    echo -e "${YELLOW}输出位置: $(cd "$output_dir" && pwd)${NC}"
    echo -e "${CYAN}详细信息: $info_file${NC}"
}

main() {
    local commit_spec="HEAD"
    local output_dir=""
    local repo_dir="$DEFAULT_REPO_DIR"
    local output_specified=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--commit)
                commit_spec="$2"
                shift 2
                ;;
            -r|--range)
                commit_spec="$2"
                shift 2
                ;;
            -o|--output)
                output_dir="$2"
                output_specified=true
                shift 2
                ;;
            -d|--directory)
                repo_dir="$2"
                shift 2
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

    # 验证Git仓库
    check_git_repo "$repo_dir"

    # 验证提交存在性
    if [[ "$commit_spec" == *".."* ]]; then
        # 验证范围的两端
        local start_commit=$(echo "$commit_spec" | sed 's/\.\..*//')
        local end_commit=$(echo "$commit_spec" | sed 's/.*\.\.//')
        check_commit_exists "$repo_dir" "$start_commit"
        check_commit_exists "$repo_dir" "$end_commit"
    else
        check_commit_exists "$repo_dir" "$commit_spec"
    fi

    # 如果未指定输出目录,根据commit_spec自动生成目录名
    if [ "$output_specified" = false ]; then
        local timestamp=$(date "+%Y%m%d_%H%M%S")
        if [[ "$commit_spec" == *".."* ]]; then
            # 提交范围: 获取两端的短commit ID
            local start_short=$(git -C "$repo_dir" rev-parse --short "$start_commit")
            local end_short=$(git -C "$repo_dir" rev-parse --short "$end_commit")
            output_dir="./extracted_${start_short}..${end_short}_${timestamp}"
        else
            # 单个提交: 获取短commit ID
            local commit_short=$(git -C "$repo_dir" rev-parse --short "$commit_spec")
            output_dir="./extracted_${commit_short}_${timestamp}"
        fi
    fi

    echo -e "${CYAN}===== Git 提交文件提取工具 =====${NC}"
    echo -e "${BLUE}仓库路径: $repo_dir${NC}"
    echo -e "${BLUE}提交规格: $commit_spec${NC}"
    echo -e "${BLUE}输出目录: $output_dir${NC}"
    echo ""

    # 执行提取
    extract_files "$repo_dir" "$commit_spec" "$output_dir"
}

main "$@"
