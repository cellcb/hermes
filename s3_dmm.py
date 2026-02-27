#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "playwright",
# ]
# ///

import os
import time
import random
import re
from playwright.sync_api import sync_playwright

def get_performer_for_video(video_id, browser):
    """根据视频编号从DMM获取演员名称（使用Playwright浏览器）"""
    url = f"https://video.dmm.co.jp/av/content/?id={video_id}"

    print(f"Fetching: {url}")

    try:
        page = browser.new_page()
        page.goto(url, wait_until="domcontentloaded", timeout=30000)

        # 等待页面加载
        time.sleep(1)

        # 检查是否在年龄确认页面
        if "年齢認証" in page.title():
            print(f"  Age confirmation page detected. Clicking 'Yes' button...")
            yes_button = page.query_selector('a[href*="declared=yes"]')
            if yes_button:
                yes_button.click()
                page.wait_for_load_state("domcontentloaded")
                time.sleep(3)  # 等待JavaScript加载
            else:
                print(f"  ERROR: Could not find 'Yes' button!")
                page.close()
                return None

        # 从页面内容中提取演员名称
        performer_name = None

        # 方法1: 在HTML中查找"出演者"后面的演员名称
        try:
            html_content = page.content()
            # 查找 "出演者" 后面跟着的演员名称
            actress_match = re.search(r'出演者.*?<a[^>]*>([^<]+)</a>', html_content, re.DOTALL)
            if actress_match:
                performer_name = actress_match.group(1).strip()
                print(f"  Found performer after '出演者': {performer_name}")
        except Exception as e:
            print(f"  Method 1 failed: {e}")

        # 方法2: 如果方法1失败，尝试从标题中提取
        if not performer_name:
            try:
                title = page.title()
                # 从标题最后一个空格后提取演员名称（在｜之前）
                if "｜" in title:
                    before_bar = title.split("｜")[0].strip()
                    parts = before_bar.rsplit(" ", 1)
                    if len(parts) == 2:
                        performer_name = parts[1].strip()
                        print(f"  Found performer from title: {performer_name}")
            except:
                pass

        page.close()
        return performer_name

    except Exception as e:
        print(f"  Error: {e}")
        try:
            page.close()
        except:
            pass
        return None

def process_files_in_directory(directory):
    # 启动Playwright浏览器
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)

        for filename in os.listdir(directory):
            # 仅处理符合规则的文件名
            if filename.endswith(".mp4") and "_" in filename:
                parts = filename.split("_")
                if len(parts) >= 3:
                    # 检查文件名是否已经包含 performer_name
                    if any("(" in part and ")" in part for part in parts[1:-1]):  # 检查编号是否已经包含 performer_name
                        print(f"Skipping already processed file: {filename}")
                        continue
                    four_digit_code = parts[0]  # 四位数字
                    identifier_with_part = parts[1]  # 包含 .part 的编号（例如 savr00442.part2）
                    # 去除 .part 和后面的部分
                    identifier = identifier_with_part.split('.part')[0]      # 编号（例如 savr00442）
                    # 提取 .part 和后续部分
                    part_suffix = identifier_with_part[len(identifier):] + filename[len(four_digit_code) + len(identifier_with_part) + 1:]  # 获取 .part 和后面的部分

                    print(f"\nProcessing: {filename}")
                    print(f"Video ID: {identifier}")

                    # 使用新的方法获取演员名称
                    performer_name = get_performer_for_video(identifier, browser)

                    if performer_name:
                        # 保留 .part 和后续部分
                        # 构建新的文件名，格式为 "四位数字_编号(performer_name).part..."
                        new_filename = f"{four_digit_code}_{identifier}({performer_name}){part_suffix}"
                        old_filepath = os.path.join(directory, filename)
                        new_filepath = os.path.join(directory, new_filename)

                        # 重命名文件
                        os.rename(old_filepath, new_filepath)
                        print(f"✓ Renamed: {filename} -> {new_filename}")
                        # 随机暂停1到3秒钟
                        sleep_time = random.uniform(1, 3)
                        print(f"  Pausing for {sleep_time:.2f} seconds...")
                        time.sleep(sleep_time)
                    else:
                        print(f"✗ Performer not found for: {filename}")
                else:
                    print(f"Filename format not matched: {filename}")
            else:
                print(f"Skipping non-matching file: {filename}")

        browser.close()

def main():
    directory = os.getcwd()  # 获取当前工作目录
    process_files_in_directory(directory)

if __name__ == "__main__":
    main()
