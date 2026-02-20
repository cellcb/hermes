#!/bin/bash
# DESC: 从RAR中提取8K/4K ed2k链接

set -e

# 参数解析
AUTO_DELETE=false
DOWNLOAD_DIR="$HOME/Downloads"

for arg in "$@"; do
    case "$arg" in
        -d|--delete)
            AUTO_DELETE=true
            ;;
        *)
            DOWNLOAD_DIR="$arg"
            ;;
    esac
done

if [ ! -d "$DOWNLOAD_DIR" ]; then
    echo "错误: 目录不存在: $DOWNLOAD_DIR" >&2
    exit 1
fi

# 解压工具路径
UNAR_PATH="unar"

# 初始化数组存储没有匹配的文件
declare -a no_match_vr_files
declare -a no_match_4k_files

# 查找包含"vr"字符的rar文件
find "$DOWNLOAD_DIR" -name "*vr*.rar" | while read -r rar_file; do
    # 获取rar文件的基本名称（不含扩展名）
    base_name=$(basename "$rar_file" .rar)

    # 创建一个临时目录用于解压
    temp_dir=$(mktemp -d)

    # 使用指定的unar工具解压rar文件到临时目录，抑制所有输出
    "$UNAR_PATH" "$rar_file" -o "$temp_dir" >/dev/null 2>&1

    # 查找解压后的txt文件
    txt_file=$(find "$temp_dir" -name "$base_name.txt" 2>/dev/null)

    if [ -f "$txt_file" ]; then
        # 查找以 ed2k 开头且包含 8K 的行，忽略大小写，只输出匹配行
        matches=$(grep -i "^ed2k.*8k.*\.mp4" "$txt_file")
        if [ -n "$matches" ]; then
            echo "$matches"
            if [ "$AUTO_DELETE" = true ]; then
                rm -f "$rar_file"
                echo "  [已删除] $rar_file" >&2
            fi
        else
            no_match_vr_files+=("$rar_file")
        fi
    else
        no_match_vr_files+=("$rar_file")
    fi

    # 清理临时目录
    rm -rf "$temp_dir" >/dev/null 2>&1
done
# find "$DOWNLOAD_DIR" -name "*_4K.rar" | while read -r rar_file; do

find "$DOWNLOAD_DIR" -name "*.rar" | while read -r rar_file; do
    # 获取rar文件的基本名称（不含扩展名）
    base_name=$(basename "$rar_file" _4K.rar)

    # 创建一个临时目录用于解压
    temp_dir=$(mktemp -d)

    # 使用指定的unar工具解压rar文件到临时目录，抑制所有输出
    "$UNAR_PATH" "$rar_file" -o "$temp_dir" >/dev/null 2>&1

    # 查找解压后的txt文件œ
    txt_file=$(find "$temp_dir" -name "$base_name.txt" 2>/dev/null)

    if [ -f "$txt_file" ]; then
        # 查找以 ed2k 开头且包含 4K 的行，忽略大小写，只输出匹配行
        matches1=$(grep -i "^ed2k.*4K60fps.mp4" "$txt_file")
        matches2=$(grep -i "^ed2k.*4k.*mp4" "$txt_file")
        
        if [ -n "$matches1" ] || [ -n "$matches2" ]; then
            [ -n "$matches1" ] && echo "$matches1"
            [ -n "$matches2" ] && echo "$matches2"
            if [ "$AUTO_DELETE" = true ]; then
                rm -f "$rar_file"
                echo "  [已删除] $rar_file" >&2
            fi
        else
            no_match_4k_files+=("$rar_file")
        fi
    else
        no_match_4k_files+=("$rar_file")
    fi

    # 清理临时目录
    rm -rf "$temp_dir" >/dev/null 2>&1
done

# 输出没有匹配的文件
echo ""
echo "=== 没有匹配的文件 ==="
if [ ${#no_match_vr_files[@]} -gt 0 ]; then
    echo "VR 文件中没有找到 8K 内容的："
    printf '%s\n' "${no_match_vr_files[@]}"
fi

if [ ${#no_match_4k_files[@]} -gt 0 ]; then
    echo "所有 RAR 文件中没有找到 4K 内容的："
    printf '%s\n' "${no_match_4k_files[@]}"
fi

if [ ${#no_match_vr_files[@]} -eq 0 ] && [ ${#no_match_4k_files[@]} -eq 0 ]; then
    echo "所有文件都找到了匹配内容"
fi
