#!/bin/bash
# DESC: 显示系统信息和资源使用情况

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

show_help() {
    echo -e "${BLUE}系统信息工具${NC}"
    echo ""
    echo -e "${YELLOW}用法:${NC} $0 [选项]"
    echo ""
    echo -e "${YELLOW}选项:${NC}"
    echo "  -a, --all         显示所有信息 (默认)"
    echo "  -s, --system      只显示系统基本信息"
    echo "  -h, --hardware    只显示硬件信息"
    echo "  -n, --network     只显示网络信息"
    echo "  -d, --disk        只显示磁盘信息"
    echo "  -p, --processes   只显示进程信息"
    echo "  -r, --resources   只显示资源使用情况"
    echo "  --help            显示此帮助信息"
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo "  $0                # 显示所有信息"
    echo "  $0 -s             # 只显示系统信息"
    echo "  $0 -r             # 只显示资源使用情况"
}

print_section() {
    local title="$1"
    echo -e "\n${CYAN}=== $title ===${NC}"
}

show_system_info() {
    print_section "系统基本信息"
    
    echo -e "${YELLOW}操作系统:${NC}"
    if command -v sw_vers &> /dev/null; then
        # macOS
        echo "  $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    elif [ -f /etc/os-release ]; then
        # Linux
        source /etc/os-release
        echo "  $PRETTY_NAME"
    else
        echo "  $(uname -s) $(uname -r)"
    fi
    
    echo -e "\n${YELLOW}内核信息:${NC}"
    echo "  $(uname -sr)"
    
    echo -e "\n${YELLOW}主机信息:${NC}"
    echo "  主机名: $(hostname)"
    echo "  用户: $(whoami)"
    echo "  开机时间: $(uptime -s 2>/dev/null || date)"
    echo "  运行时长: $(uptime | sed 's/.*up //' | sed 's/,.*load.*//')"
}

show_hardware_info() {
    print_section "硬件信息"
    
    echo -e "${YELLOW}CPU信息:${NC}"
    if command -v sysctl &> /dev/null; then
        # macOS
        local cpu_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "未知")
        local cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "未知")
        echo "  处理器: $cpu_brand"
        echo "  核心数: $cpu_cores"
    elif [ -f /proc/cpuinfo ]; then
        # Linux
        local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
        local cpu_cores=$(nproc)
        echo "  处理器: $cpu_model"
        echo "  核心数: $cpu_cores"
    fi
    
    echo -e "\n${YELLOW}内存信息:${NC}"
    if command -v sysctl &> /dev/null; then
        # macOS
        local total_mem=$(sysctl -n hw.memsize 2>/dev/null)
        if [ -n "$total_mem" ]; then
            local total_gb=$((total_mem / 1024 / 1024 / 1024))
            echo "  总内存: ${total_gb}GB"
        fi
    elif [ -f /proc/meminfo ]; then
        # Linux
        local total_mem=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
        local total_gb=$((total_mem / 1024 / 1024))
        echo "  总内存: ${total_gb}GB"
    fi
}

show_network_info() {
    print_section "网络信息"
    
    echo -e "${YELLOW}网络接口:${NC}"
    if command -v ip &> /dev/null; then
        # Linux
        ip addr show | grep -E "^[0-9]+:" | awk '{print "  " $2}' | sed 's/:$//'
    elif command -v ifconfig &> /dev/null; then
        # macOS/BSD
        ifconfig | grep -E "^[a-z]" | awk '{print "  " $1}' | sed 's/:$//'
    fi
    
    echo -e "\n${YELLOW}IP地址:${NC}"
    if command -v ip &> /dev/null; then
        # Linux
        ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print "  " $7 ": " $2}'
    elif command -v ifconfig &> /dev/null; then
        # macOS/BSD
        ifconfig | grep "inet " | grep -v "127.0.0.1" | awk '{print "  " $NF ": " $2}'
    fi
    
    echo -e "\n${YELLOW}DNS服务器:${NC}"
    if [ -f /etc/resolv.conf ]; then
        grep "nameserver" /etc/resolv.conf | awk '{print "  " $2}'
    fi
}

show_disk_info() {
    print_section "磁盘信息"
    
    echo -e "${YELLOW}磁盘使用情况:${NC}"
    df -h | grep -E "^(/dev|/System)" | while read line; do
        echo "  $line"
    done
    
    echo -e "\n${YELLOW}磁盘I/O统计:${NC}"
    if command -v iostat &> /dev/null; then
        iostat -d 1 1 2>/dev/null | tail -n +4 | head -5
    else
        echo "  iostat 命令不可用"
    fi
}

show_processes_info() {
    print_section "进程信息"
    
    echo -e "${YELLOW}运行进程数:${NC}"
    local total_processes=$(ps ax | wc -l)
    echo "  总进程数: $((total_processes - 1))"
    
    echo -e "\n${YELLOW}CPU占用前5的进程:${NC}"
    ps aux | sort -rk3,3 | head -6 | tail -5 | awk '{printf "  %-20s %5s%% %s\n", $11, $3, $2}'
    
    echo -e "\n${YELLOW}内存占用前5的进程:${NC}"
    ps aux | sort -rk4,4 | head -6 | tail -5 | awk '{printf "  %-20s %5s%% %s\n", $11, $4, $2}'
}

show_resources_info() {
    print_section "资源使用情况"
    
    echo -e "${YELLOW}CPU使用率:${NC}"
    if command -v top &> /dev/null; then
        # 获取CPU使用率
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            top -l 1 -n 0 | grep "CPU usage" | awk '{print "  用户: " $3 ", 系统: " $5 ", 空闲: " $7}'
        else
            # Linux
            top -bn1 | grep "Cpu(s)" | awk '{print "  用户: " $2 ", 系统: " $4 ", 空闲: " $8}'
        fi
    fi
    
    echo -e "\n${YELLOW}内存使用率:${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        local mem_pressure=$(memory_pressure 2>/dev/null | head -1 || echo "无法获取内存压力信息")
        echo "  $mem_pressure"
    elif [ -f /proc/meminfo ]; then
        # Linux
        local total=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
        local available=$(grep "MemAvailable" /proc/meminfo | awk '{print $2}')
        local used=$((total - available))
        local usage_percent=$((used * 100 / total))
        echo "  已用: ${usage_percent}% ($(($used / 1024))MB / $(($total / 1024))MB)"
    fi
    
    echo -e "\n${YELLOW}负载平均:${NC}"
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    echo "  $load_avg"
    
    echo -e "\n${YELLOW}磁盘I/O:${NC}"
    if command -v iotop &> /dev/null 2>&1; then
        echo "  $(iotop -a -o -d 1 -n 1 2>/dev/null | head -1 || echo '无法获取I/O信息')"
    else
        echo "  iotop 命令不可用"
    fi
}

main() {
    local show_all=true
    local show_system=false
    local show_hardware=false
    local show_network=false
    local show_disk=false
    local show_processes=false
    local show_resources=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                show_all=true
                shift
                ;;
            -s|--system)
                show_all=false
                show_system=true
                shift
                ;;
            -h|--hardware)
                show_all=false
                show_hardware=true
                shift
                ;;
            -n|--network)
                show_all=false
                show_network=true
                shift
                ;;
            -d|--disk)
                show_all=false
                show_disk=true
                shift
                ;;
            -p|--processes)
                show_all=false
                show_processes=true
                shift
                ;;
            -r|--resources)
                show_all=false
                show_resources=true
                shift
                ;;
            --help)
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
    
    echo -e "${MAGENTA}系统信息报告 - $(date)${NC}"
    
    if [ "$show_all" = "true" ]; then
        show_system_info
        show_hardware_info
        show_network_info
        show_disk_info
        show_processes_info
        show_resources_info
    else
        [ "$show_system" = "true" ] && show_system_info
        [ "$show_hardware" = "true" ] && show_hardware_info
        [ "$show_network" = "true" ] && show_network_info
        [ "$show_disk" = "true" ] && show_disk_info
        [ "$show_processes" = "true" ] && show_processes_info
        [ "$show_resources" = "true" ] && show_resources_info
    fi
    
    echo ""
}

main "$@" 