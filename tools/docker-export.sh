#!/bin/bash
# DESC: 导出Docker容器，压缩并拷贝到本地

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 默认配置
DEFAULT_OUTPUT_DIR="$HOME/Downloads"
DEFAULT_COMPRESSION="zip"

show_help() {
    echo -e "${BLUE}Docker容器导出工具${NC}"
    echo ""
    echo -e "${YELLOW}用法:${NC} $0 [选项] <容器名称或ID>"
    echo ""
    echo -e "${YELLOW}选项:${NC}"
    echo "  -r, --remote HOST     远程Docker主机 (SSH连接)"
    echo "  -o, --output DIR      输出目录 (默认: $DEFAULT_OUTPUT_DIR)"
    echo "  -c, --compress TYPE   压缩类型: gzip|bzip2|xz|zip (默认: $DEFAULT_COMPRESSION)"
    echo "  -n, --name NAME       导出文件名前缀"
    echo "  -l, --list            列出可用容器"
    echo "  --no-compress         不压缩导出文件"
    echo "  -h, --help            显示此帮助信息"
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo "  $0 my-container                          # 导出本地容器"
    echo "  $0 -r user@server my-container           # 导出远程容器"
    echo "  $0 -o /path/to/exports my-container      # 指定输出目录"
    echo "  $0 -c bzip2 my-container                 # 使用bzip2压缩"
    echo "  $0 -c zip my-container                   # 使用zip压缩"
    echo "  $0 -n backup my-container                # 指定文件名前缀"
    echo "  $0 -l                                    # 列出所有容器"
    echo "  $0 -r user@server -l                     # 列出远程容器"
}

list_containers() {
    local remote_host="$1"
    
    echo -e "${BLUE}可用容器列表:${NC}"
    echo ""
    
    if [ -n "$remote_host" ]; then
        echo -e "${CYAN}远程主机: $remote_host${NC}"
    else
        echo -e "${CYAN}本地Docker${NC}"
    fi
    echo ""
    
    # 运行中的容器
    echo -e "${GREEN}运行中的容器:${NC}"
    if [ -n "$remote_host" ]; then
        ssh "$remote_host" 'docker ps --format "table {{.Names}}\t{{.ID}}\t{{.Image}}\t{{.Status}}"' || {
            echo -e "${RED}无法获取运行中的容器列表${NC}"
            return 1
        }
    else
        docker ps --format "table {{.Names}}\t{{.ID}}\t{{.Image}}\t{{.Status}}" || {
            echo -e "${RED}无法获取运行中的容器列表${NC}"
            return 1
        }
    fi
    
    echo ""
    
    # 所有容器
    echo -e "${YELLOW}所有容器:${NC}"
    if [ -n "$remote_host" ]; then
        ssh "$remote_host" 'docker ps -a --format "table {{.Names}}\t{{.ID}}\t{{.Image}}\t{{.Status}}"' || {
            echo -e "${RED}无法获取容器列表${NC}"
            return 1
        }
    else
        docker ps -a --format "table {{.Names}}\t{{.ID}}\t{{.Image}}\t{{.Status}}" || {
            echo -e "${RED}无法获取容器列表${NC}"
            return 1
        }
    fi
}

get_container_info() {
    local remote_host="$1"
    local container="$2"
    
    # 获取容器信息
    local container_info
    if [ -n "$remote_host" ]; then
        container_info=$(ssh "$remote_host" "docker inspect \"$container\" --format \"{{.Name}}|{{.Id}}|{{.Config.Image}}\"" 2>/dev/null) || {
            echo -e "${RED}错误: 容器 '$container' 不存在${NC}" >&2
            return 1
        }
    else
        container_info=$(docker inspect "$container" --format "{{.Name}}|{{.Id}}|{{.Config.Image}}" 2>/dev/null) || {
            echo -e "${RED}错误: 容器 '$container' 不存在${NC}" >&2
            return 1
        }
    fi
    
    echo "$container_info"
}

export_container() {
    local remote_host="$1"
    local container="$2"
    local output_dir="$3"
    local compression="$4"
    local filename_prefix="$5"
    local no_compress="$6"
    
    # 获取容器信息
    local container_info
    container_info=$(get_container_info "$remote_host" "$container") || return 1
    
    local container_name=$(echo "$container_info" | cut -d'|' -f1 | sed 's/^\/*//')
    local container_id=$(echo "$container_info" | cut -d'|' -f2 | cut -c1-12)
    local image_name=$(echo "$container_info" | cut -d'|' -f3)
    
    echo -e "${BLUE}容器信息:${NC}"
    echo "  名称: $container_name"
    echo "  ID: $container_id"
    echo "  镜像: $image_name"
    echo ""
    
    # 创建输出目录
    mkdir -p "$output_dir"
    
    # 生成文件名
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    local base_filename="${filename_prefix:-${container_name}}_${timestamp}"
    local tar_filename="${base_filename}.tar"
    
    echo -e "${CYAN}开始导出容器...${NC}"
    
    if [ -n "$remote_host" ]; then
        # 远程导出
        echo -e "${YELLOW}从远程主机导出: $remote_host${NC}"
        
        # 在远程主机上导出
        local remote_tar_path="/tmp/${tar_filename}"
        ssh "$remote_host" "docker export \"$container\" -o \"$remote_tar_path\"" || {
            echo -e "${RED}远程导出失败${NC}" >&2
            return 1
        }
        
        echo -e "${GREEN}✓ 远程导出完成${NC}"
        
        # 拷贝到本地
        local local_tar_path="${output_dir}/${tar_filename}"
        echo -e "${YELLOW}拷贝到本地...${NC}"
        scp "${remote_host}:${remote_tar_path}" "$local_tar_path" || {
            echo -e "${RED}文件拷贝失败${NC}" >&2
            return 1
        }
        
        # 清理远程文件
        ssh "$remote_host" "rm -f \"$remote_tar_path\""
        echo -e "${GREEN}✓ 文件拷贝完成${NC}"
        
    else
        # 本地导出
        local local_tar_path="${output_dir}/${tar_filename}"
        echo -e "${YELLOW}本地导出到: $local_tar_path${NC}"
        docker export "$container" -o "$local_tar_path" || {
            echo -e "${RED}本地导出失败${NC}" >&2
            return 1
        }
        echo -e "${GREEN}✓ 本地导出完成${NC}"
    fi
    
    # 压缩文件
    if [ "$no_compress" != "true" ]; then
        echo -e "${YELLOW}压缩文件...${NC}"
        local compressed_path
        
        case "$compression" in
            gzip)
                compressed_path="${local_tar_path}.gz"
                gzip "$local_tar_path" || {
                    echo -e "${RED}压缩失败${NC}" >&2
                    return 1
                }
                ;;
            bzip2)
                compressed_path="${local_tar_path}.bz2"
                bzip2 "$local_tar_path" || {
                    echo -e "${RED}压缩失败${NC}" >&2
                    return 1
                }
                ;;
            xz)
                compressed_path="${local_tar_path}.xz"
                xz "$local_tar_path" || {
                    echo -e "${RED}压缩失败${NC}" >&2
                    return 1
                }
                ;;
            zip)
                compressed_path="${local_tar_path}.zip"
                # 切换到文件所在目录，只压缩文件名，避免包含目录结构
                local tar_dir=$(dirname "$local_tar_path")
                local tar_filename=$(basename "$local_tar_path")
                (cd "$tar_dir" && zip -q "$(basename "$compressed_path")" "$tar_filename") || {
                    echo -e "${RED}压缩失败${NC}" >&2
                    return 1
                }
                # 删除原始tar文件，因为zip不会自动删除源文件
                rm -f "$local_tar_path"
                ;;
            *)
                echo -e "${RED}不支持的压缩格式: $compression${NC}" >&2
                return 1
                ;;
        esac
        
        local_tar_path="$compressed_path"
        echo -e "${GREEN}✓ 压缩完成${NC}"
    fi
    
    # 显示结果
    local file_size=$(du -sh "$local_tar_path" | cut -f1)
    echo ""
    echo -e "${GREEN}导出成功!${NC}"
    echo -e "${YELLOW}文件路径:${NC} $local_tar_path"
    echo -e "${YELLOW}文件大小:${NC} $file_size"
    
    # 生成导入命令提示
    echo ""
    echo -e "${BLUE}导入命令:${NC}"
    if [ "$no_compress" = "true" ]; then
        echo "  docker import $local_tar_path ${container_name}:imported"
    else
        case "$compression" in
            gzip)
                echo "  zcat $local_tar_path | docker import - ${container_name}:imported"
                ;;
            bzip2)
                echo "  bzcat $local_tar_path | docker import - ${container_name}:imported"
                ;;
            xz)
                echo "  xzcat $local_tar_path | docker import - ${container_name}:imported"
                ;;
            zip)
                echo "  unzip -p $local_tar_path | docker import - ${container_name}:imported"
                ;;
        esac
    fi
}

main() {
    local remote_host=""
    local output_dir="$DEFAULT_OUTPUT_DIR"
    local compression="$DEFAULT_COMPRESSION"
    local filename_prefix=""
    local no_compress="false"
    local list_only="false"
    local container=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--remote)
                remote_host="$2"
                shift 2
                ;;
            -o|--output)
                output_dir="$2"
                shift 2
                ;;
            -c|--compress)
                compression="$2"
                shift 2
                ;;
            -n|--name)
                filename_prefix="$2"
                shift 2
                ;;
            -l|--list)
                list_only="true"
                shift
                ;;
            --no-compress)
                no_compress="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                echo -e "${RED}未知参数: $1${NC}" >&2
                show_help
                exit 1
                ;;
            *)
                container="$1"
                shift
                ;;
        esac
    done
    
    # 检查Docker是否可用
    if [ -z "$remote_host" ]; then
        if ! command -v docker &> /dev/null; then
            echo -e "${RED}错误: Docker未安装或不在PATH中${NC}" >&2
            exit 1
        fi
    fi
    
    # 列出容器
    if [ "$list_only" = "true" ]; then
        list_containers "$remote_host"
        exit 0
    fi
    
    # 检查容器参数
    if [ -z "$container" ]; then
        echo -e "${RED}错误: 请指定容器名称或ID${NC}" >&2
        show_help
        exit 1
    fi
    
    # 验证压缩格式
    if [ "$no_compress" != "true" ] && [[ ! "$compression" =~ ^(gzip|bzip2|xz|zip)$ ]]; then
        echo -e "${RED}错误: 不支持的压缩格式 '$compression'${NC}" >&2
        echo -e "${YELLOW}支持的格式: gzip, bzip2, xz, zip${NC}" >&2
        exit 1
    fi
    
    # 导出容器
    export_container "$remote_host" "$container" "$output_dir" "$compression" "$filename_prefix" "$no_compress"
}

main "$@" 