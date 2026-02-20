#!/bin/bash
# DESC: 从RAR中提取8K/4K ed2k链接

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

# 记录已处理的VR文件，避免第二轮重复处理
processed_files=""

# 查找包含"vr"字符的rar文件
while IFS= read -r rar_file; do
    base_name=$(basename "$rar_file" .rar)
    processed_files="$processed_files|$rar_file"

    temp_dir=$(mktemp -d)
    "$UNAR_PATH" "$rar_file" -o "$temp_dir" >/dev/null 2>&1

    txt_file=$(find "$temp_dir" -name "$base_name.txt" 2>/dev/null | head -1)

    if [ -f "$txt_file" ]; then
        matches=$(grep -i "^ed2k.*8k.*\.mp4" "$txt_file" || true)
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

    rm -rf "$temp_dir" >/dev/null 2>&1
done < <(find "$DOWNLOAD_DIR" -maxdepth 1 -name "*vr*.rar")

# 查找 _4K.rar 文件，跳过已处理的VR文件
while IFS= read -r rar_file; do
    # 跳过已在VR循环中处理的文件
    echo "$processed_files" | grep -qF "$rar_file" && continue

    base_name=$(basename "$rar_file" _4K.rar)
    temp_dir=$(mktemp -d)
    "$UNAR_PATH" "$rar_file" -o "$temp_dir" >/dev/null 2>&1

    txt_file=$(find "$temp_dir" -name "$base_name.txt" 2>/dev/null | head -1)

    if [ -f "$txt_file" ]; then
        matches=$(grep -i "^ed2k.*4k.*\.mp4" "$txt_file" || true)
        if [ -n "$matches" ]; then
            echo "$matches"
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

    rm -rf "$temp_dir" >/dev/null 2>&1
done < <(find "$DOWNLOAD_DIR" -maxdepth 1 -name "*_4K.rar")

# 输出没有匹配的文件
echo ""
echo "=== 没有匹配的文件 ==="
if [ ${#no_match_vr_files[@]} -gt 0 ]; then
    echo "VR 文件中没有找到 8K 内容的："
    printf '%s\n' "${no_match_vr_files[@]}"
fi

if [ ${#no_match_4k_files[@]} -gt 0 ]; then
    echo "_4K 文件中没有找到 4K 内容的："
    printf '%s\n' "${no_match_4k_files[@]}"
fi

if [ ${#no_match_vr_files[@]} -eq 0 ] && [ ${#no_match_4k_files[@]} -eq 0 ]; then
    echo "所有文件都找到了匹配内容"
fi
