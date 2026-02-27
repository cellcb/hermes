#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "playwright",
# ]
# ///
"""
DMM视频文件重命名工具

从JSON文件中读取视频信息，访问DMM网站获取演员名称，
并生成包含重命名映射的CSV文件。

使用方法:
    python3 process_json_rename.py input.json -o output.csv
    python3 process_json_rename.py input.json --verbose
    python3 process_json_rename.py input.json --min-delay 2 --max-delay 5
"""

import json
import time
import random
import csv
import re
import argparse
import sys
import urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright


SITE_PREFIXES = ("hhd800.com@", "4k2.me@")
ID_STRIP_SUFFIXES = ("hhb", "ch")


def strip_site_prefix(filename):
    """去掉站点前缀，返回前缀后的部分；无匹配则返回原文件名"""
    for prefix in SITE_PREFIXES:
        if filename.startswith(prefix):
            return filename[len(prefix):]
    return filename


def is_jav_code(video_id):
    """判断是否为标准番号格式（如 ABF-284, DASS-821）"""
    return bool(re.match(r'^[A-Z]+-\d+$', video_id))


def extract_video_id(filename):
    """
    从文件名中提取视频编号

    Args:
        filename: 文件名，例如 "hhd800.com@mfyd00001_4K60fps.mp4"

    Returns:
        视频编号，例如 "mfyd00001"，如果提取失败则返回 None
    """
    after_prefix = strip_site_prefix(filename)

    # 提取编号部分（在 _ 或 . 之前的部分）
    match = re.match(r'([^_\.]+)', after_prefix)
    if match:
        video_id = match.group(1)
        # 去掉尾部的无关后缀
        for suffix in ID_STRIP_SUFFIXES:
            if video_id.endswith(suffix):
                video_id = video_id[:-len(suffix)]
                break
        return video_id
    return None


def extract_suffix(filename):
    """
    从文件名中提取 video ID 之后、扩展名之前的后缀部分

    Examples:
        hhd800.com@13dsvr01892.part1_8K.mp4 → ".part1_8K"
        hhd800.com@ssis00952_4K60fps.mp4    → "_4K60fps"
        hhd800.com@ATID-637.mp4            → ""
    """
    after_prefix = strip_site_prefix(filename)
    # 去掉扩展名
    stem = after_prefix.rsplit('.', 1)[0] if '.' in after_prefix else after_prefix
    # 去掉 video ID（第一个 _ 或 . 之前的部分）
    video_id = extract_video_id(filename)
    if not video_id:
        return ""
    suffix = stem[len(video_id):]
    return suffix


def get_performer_from_javbus(video_id, verbose=False):
    """
    从JavBus获取演员名称

    Args:
        video_id: 标准番号，例如 "ABF-284"
        verbose: 是否显示详细输出

    Returns:
        演员名称，如果获取失败则返回 None
    """
    url = f"https://www.javbus.com/{video_id}"
    if verbose:
        print(f"  Fetching: {url}")

    try:
        req = urllib.request.Request(url)
        req.add_header('Cookie', 'existmag=mag; age=verified; dv=1')
        req.add_header('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')

        response = urllib.request.urlopen(req, timeout=15)
        html = response.read().decode('utf-8')

        match = re.search(r'<div class="star-name"><a[^>]*>([^<]+)</a>', html)
        if match:
            performer_name = match.group(1).strip()
            if verbose:
                print(f"  Found performer: {performer_name}")
            return performer_name

        if verbose:
            print(f"  Performer not found in JavBus page")
        return None

    except Exception as e:
        if verbose:
            print(f"  Error fetching from JavBus: {e}")
        return None


def get_performer_for_video(video_id, browser, verbose=False):
    """
    根据视频编号从DMM获取演员名称

    Args:
        video_id: 视频编号，例如 "mfyd00001"
        browser: Playwright浏览器实例
        verbose: 是否显示详细输出

    Returns:
        演员名称，如果获取失败则返回 None
    """
    # 标准番号格式用 JavBus
    if is_jav_code(video_id):
        if verbose:
            print(f"  Detected JAV code format, using JavBus...")
        return get_performer_from_javbus(video_id, verbose)

    # 非番号格式用 DMM（原有逻辑不变）
    url = f"https://video.dmm.co.jp/av/content/?id={video_id}"

    if verbose:
        print(f"  Fetching: {url}")

    try:
        page = browser.new_page()
        page.goto(url, wait_until="domcontentloaded", timeout=30000)

        # 等待页面加载
        time.sleep(1)

        # 检查是否在年龄确认页面
        if "年齢認証" in page.title():
            if verbose:
                print(f"  Age confirmation detected, clicking continue...")
            yes_button = page.query_selector('a[href*="declared=yes"]')
            if yes_button:
                yes_button.click()
                page.wait_for_load_state("domcontentloaded")
                time.sleep(3)  # 等待JavaScript加载
            else:
                if verbose:
                    print(f"  ERROR: Could not find confirmation button")
                page.close()
                return None

        # 从页面内容中提取演员名称
        performer_name = None

        # 方法1: 在HTML中查找"出演者"后面的演员名称
        try:
            html_content = page.content()
            actress_match = re.search(r'出演者.*?<a[^>]*>([^<]+)</a>', html_content, re.DOTALL)
            if actress_match:
                performer_name = actress_match.group(1).strip()
                if verbose:
                    print(f"  Found performer: {performer_name}")
        except Exception as e:
            if verbose:
                print(f"  Extraction method 1 failed: {e}")

        # 方法2: 如果方法1失败，尝试从标题中提取
        if not performer_name:
            try:
                title = page.title()
                if "｜" in title:
                    before_bar = title.split("｜")[0].strip()
                    parts = before_bar.rsplit(" ", 1)
                    if len(parts) == 2:
                        performer_name = parts[1].strip()
                        if verbose:
                            print(f"  Found performer from title: {performer_name}")
            except Exception as e:
                if verbose:
                    print(f"  Extraction method 2 failed: {e}")

        page.close()
        return performer_name

    except Exception as e:
        if verbose:
            print(f"  Error: {e}")
        try:
            page.close()
        except:
            pass
        return None


def process_json_file(json_path, output_csv_path, min_delay=1, max_delay=3, verbose=False):
    """
    处理JSON文件并生成CSV重命名文件

    Args:
        json_path: 输入JSON文件路径
        output_csv_path: 输出CSV文件路径
        min_delay: 请求之间的最小延迟（秒）
        max_delay: 请求之间的最大延迟（秒）
        verbose: 是否显示详细输出

    Returns:
        处理成功的文件数量
    """
    # 验证输入文件
    json_file = Path(json_path)
    if not json_file.exists():
        print(f"✗ Error: Input file not found: {json_path}")
        return 0

    if not json_file.is_file():
        print(f"✗ Error: Input path is not a file: {json_path}")
        return 0

    # 读取JSON文件
    print(f"Reading JSON file: {json_path}")
    try:
        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"✗ Error: Invalid JSON file: {e}")
        return 0
    except Exception as e:
        print(f"✗ Error reading file: {e}")
        return 0

    # 获取data数组
    items = data.get('data', [])
    if not items:
        print(f"✗ Warning: No 'data' array found in JSON or array is empty")
        return 0

    print(f"Found {len(items)} items in data array")

    # 统计需要处理的文件
    files_to_process = [item for item in items if item.get('n', '')]
    print(f"Found {len(files_to_process)} files matching criteria\n")

    if not files_to_process:
        print("✗ No files to process")
        return 0

    # 准备CSV数据
    csv_data = []
    processed_count = 0
    failed_count = 0
    performer_cache = {}  # video_id → performer_name, 避免同 ID 重复查询

    # 启动Playwright浏览器
    print("Starting browser...\n")
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)

        for idx, item in enumerate(files_to_process, 1):
            filename = item.get('n', '')

            print(f"[{idx}/{len(files_to_process)}] Processing: {filename}")

            # 提取视频编号
            video_id = extract_video_id(filename)

            if video_id:
                if verbose:
                    print(f"  Video ID: {video_id}")

                # 获取演员名称（使用缓存避免同 video ID 重复查询）
                if video_id in performer_cache:
                    performer_name = performer_cache[video_id]
                    if verbose:
                        print(f"  Using cached performer: {performer_name}")
                else:
                    performer_name = get_performer_for_video(video_id, browser, verbose)
                    performer_cache[video_id] = performer_name

                    # 随机暂停，避免请求过快（仅在实际发起请求后暂停）
                    if idx < len(files_to_process):
                        sleep_time = random.uniform(min_delay, max_delay)
                        if verbose:
                            print(f"  Pausing for {sleep_time:.2f} seconds...")
                        time.sleep(sleep_time)

                if performer_name:
                    # 生成新文件名: 演员名称-视频编号+后缀.mp4
                    suffix = extract_suffix(filename)
                    new_filename = f"{performer_name}-{video_id}{suffix}.mp4"
                    csv_data.append([filename, new_filename])
                    print(f"  ✓ New filename: {new_filename}")
                    processed_count += 1
                else:
                    print(f"  ✗ Performer not found")
                    failed_count += 1
            else:
                print(f"  ✗ Could not extract video ID")
                failed_count += 1

        browser.close()

    # 写入CSV文件
    if csv_data:
        try:
            output_path = Path(output_csv_path)
            output_path.parent.mkdir(parents=True, exist_ok=True)

            with open(output_csv_path, 'w', encoding='utf-8-sig', newline='') as f:
                writer = csv.writer(f)
                # 写入表头
                writer.writerow(['原名称', '新名称', '注：1、第一行固定不变、删除模板无效；'])
                # 写入数据
                for row in csv_data:
                    writer.writerow([row[0], row[1], ''])

            print(f"\n{'='*60}")
            print(f"✓ CSV file generated: {output_csv_path}")
            print(f"✓ Successfully processed: {processed_count} files")
            if failed_count > 0:
                print(f"✗ Failed: {failed_count} files")
            print(f"{'='*60}")
        except Exception as e:
            print(f"\n✗ Error writing CSV file: {e}")
            return processed_count
    else:
        print("\n✗ No files were successfully processed. CSV not generated.")

    return processed_count


def main():
    """主函数，处理命令行参数并执行处理"""
    parser = argparse.ArgumentParser(
        description='从JSON文件中提取视频信息并生成重命名CSV文件',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  %(prog)s sample.json
  %(prog)s sample.json -o my_output.csv
  %(prog)s sample.json --verbose
  %(prog)s sample.json --min-delay 2 --max-delay 5
  %(prog)s sample.json -o output.csv -v --min-delay 1.5 --max-delay 3.5
        """
    )

    parser.add_argument(
        'input_json',
        help='输入的JSON文件路径'
    )

    parser.add_argument(
        '-o', '--output',
        default='rename_output.csv',
        help='输出CSV文件路径 (默认: rename_output.csv)'
    )

    parser.add_argument(
        '--min-delay',
        type=float,
        default=1.0,
        help='请求之间的最小延迟秒数 (默认: 1.0)'
    )

    parser.add_argument(
        '--max-delay',
        type=float,
        default=3.0,
        help='请求之间的最大延迟秒数 (默认: 3.0)'
    )

    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='显示详细输出信息'
    )

    parser.add_argument(
        '--version',
        action='version',
        version='%(prog)s 1.0.0'
    )

    args = parser.parse_args()

    # 验证延迟参数
    if args.min_delay < 0 or args.max_delay < 0:
        print("✗ Error: Delay values must be non-negative")
        sys.exit(1)

    if args.min_delay > args.max_delay:
        print("✗ Error: min-delay must be less than or equal to max-delay")
        sys.exit(1)

    # 执行处理
    try:
        processed = process_json_file(
            args.input_json,
            args.output,
            min_delay=args.min_delay,
            max_delay=args.max_delay,
            verbose=args.verbose
        )

        sys.exit(0 if processed > 0 else 1)

    except KeyboardInterrupt:
        print("\n\n✗ Process interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
