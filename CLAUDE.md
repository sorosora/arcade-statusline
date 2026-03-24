# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案概述

此 repo 存放 Claude Code 的自訂設定檔，目前包含一個 Pac-Man 風格的 statusline 腳本（`statusline.sh`）。

## statusline.sh 架構

這是一個 Bash 腳本，用於 Claude Code 的 status line 顯示。它從 stdin 讀取 JSON 輸入（包含 `context_window` 和 `rate_limits` 資訊），並輸出帶有 ANSI 色彩的 Pac-Man 迷宮動畫。

核心流程：
1. 用 `jq` 解析 JSON，提取 context window 使用率、5 小時 / 7 天 rate limit 百分比與重置時間
2. 定義 30×7 的迷宮（3 條水平走廊 + 5 條垂直通道）
3. 從迷宮中心 (row 3, col 14) 執行 BFS，決定小點被吃掉的順序
4. Pac-Man 位置由 context window 使用率決定（使用率越高，吃掉越多點）
5. 兩隻鬼魂分別代表 5 小時 rate limit（紅色）和 7 天 rate limit（紫色），位於未被吃掉的區域
6. 最終渲染迷宮 + 左側顯示 "CLAUDE" ASCII art 和使用率數字

## 慣例

- commit message 禁止提及由 AI 或相關工具撰寫
- 對話使用繁體中文（台灣用語）
