---
name: shelve-review
description: 当用户要求 review 一个或多个 P4 shelved changelist（提供 changelist number）时使用此技能。
---

## 输入解析

用户可能提供一个或多个 shelved changelist number，常见格式：
- 单个：`review shelve 123456`
- 多个：`review shelve 123456 123457` 或 `review shelve 123456, 123457`

解析出所有 CL 编号后，按下述流程处理。

## 操作流程

### 1) 获取变更信息（只读，不 unshelve）

直接使用 `p4 describe -S` 读取 shelved changelist 的 diff，**无需 unshelve 到本地**，无需临时文件：

```bash
# 获取 shelved changelist 的文件列表和描述
p4 describe -s -S <N>

# 获取 shelved changelist 的完整 diff
p4 describe -du -S <N>
```

**多 CL 时批量获取**：
```bash
p4 describe -s -S <N1> <N2> <N3> ...
```

如果 diff 输出过长被截断，逐文件处理：
```bash
# 查看 shelved 版本的完整文件内容
p4 print <file>@=<N>

# 对比当前版本与 shelved 版本
p4 diff2 -du <file> <file>@=<N>
```

#### 多 CL 策略

1. **去重合并文件列表**：多个 CL 可能修改同一文件，合并后按文件维度组织变更
2. **识别 CL 关联性**：判断多个 CL 是否属于同一功能的连续提交，若是则作为整体审查
3. **使用子代理并行**：每个 CL 的 diff 获取委派给子代理并行执行，加速信息收集

### 2) 代码审查

按照 `../code-review/SKILL.md` 中定义的审查流程（第 2-3 步：并行审查扫描 + 结果汇总去重）执行代码审查，**但仅关注 P0、P1、P2 级别的问题**：
- 架构与设计原则检查
- C7 项目专项 & 安全可靠性检查
- 代码质量扫描
- **跳过** P3（风格、命名、小建议）— 不输出、不报告

输出格式中只包含 P0/P1/P2 三个级别的小节，不输出 P3 小节。

#### 多 CL 审查策略

- **关联 CL（同一功能）**：合并为一次审查，按文件维度输出，每个发现项标注所属 CL 编号
- **无关 CL**：每个 CL 分别审查，使用子代理并行执行各 CL 的审查，最后汇总结果
- **跨 CL 问题**：特别关注多个 CL 之间的交互问题

### 3) 输出格式

#### 单 CL 输出

```
## 代码审查摘要 — Shelved CL <N>

**描述**：<changelist description>
**审查文件数**：X 个文件，Y 行变更
**总体评估**：[通过 / 需要修改 / 仅建议]

## 发现项

### P0 - 严重
（无 或 列出）

### P1 - 高危
1. **[CL:file:line]** 简要标题
   - 问题描述
   - 建议修复

### P2 - 中等
2. （继续编号）
```

#### 多 CL 输出

```
## 代码审查摘要 — Shelved CL <N1>, <N2>, ...

**审查范围**：X 个 CL，共 Y 个文件，Z 行变更
**总体评估**：[通过 / 需要修改 / 仅建议]

| CL | 描述 | 文件数 | 评估 |
|----|------|--------|------|
| <N1> | ... | X | 通过 |
| <N2> | ... | Y | 需要修改 |

## 发现项

（所有 CL 的发现项统一编号，每项标注 CL 编号）

### P0 - 严重
（无 或 列出）

### P1 - 高危
1. **[CL<N>:file:line]** 简要标题
   - 问题描述
   - 建议修复

### P2 - 中等
2. （继续编号）

## 跨 CL 问题
（如有多个 CL 之间的交互/一致性问题，在此列出）
```

### 4) 导出审查记录

按照 `../code-review/SKILL.md` 第 5 步的规则，将审查结果导出到 `Server/docs/reviews/` 目录（基于 workspace 中 `Server/` 的实际路径定位）。文件命名使用 `CR-<日期>-Shelve<N>.md` 格式（多 CL 时用下划线连接编号）。

### 5) 审查后处理

展示审查结果后，提供以下选项：
1. **全部修复** — unshelve 到本地并实施所有建议
2. **仅修复 P0/P1** — unshelve 到本地，处理严重和高危问题
3. **修复指定项** — unshelve 到本地，用户选择要修复的项
4. **不做修改** — 审查完成

**重要**：未经用户确认，不要主动实施修改。

#### Unshelve 流程（仅在用户选择修复时执行）

用 `cmd /c` 管道创建 changelist 并 unshelve，**无需临时文件**：

```powershell
# 1. 创建本地 changelist（通过 cmd 管道避免 PowerShell 编码问题）
$output = cmd /c 'p4 --field "Description=Review shelved CL <N>" change -o | p4 change -i'
# 从输出提取编号，格式：Change <LOCAL_CL> created.
$LOCAL_CL = [regex]::Match($output, 'Change (\d+)').Groups[1].Value

# 2. Unshelve 到本地 changelist
p4 unshelve -s <N> -c $LOCAL_CL

# 3. 实施修改...
```

修复完成后，提供选项：
- **Reshelve** — 将修改后的文件重新 shelve 回原 CL：
  ```
  p4 shelve -f -c $LOCAL_CL
  p4 revert -c $LOCAL_CL //...
  p4 change -d $LOCAL_CL
  ```
- **保留本地** — 不 reshelve，保留本地 changelist 供用户后续操作
- **还原** — 撤销所有修改：
  ```
  p4 revert -c $LOCAL_CL //...
  p4 change -d $LOCAL_CL
  ```
