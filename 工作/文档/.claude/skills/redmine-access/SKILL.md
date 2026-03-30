---
name: redmine-access
description: 当用户要求访问 Redmine 链接、读取 issue 内容、分析报错单或根据 bug 单号定位代码时使用此技能。
---

## 概述

C7 项目的 Redmine 页面链接经常是前端 SPA 壳页面，直接访问网页 URL 即使返回 200，也可能只拿到 HTML 外壳，拿不到 issue 正文。遇到这类需求时，**优先通过 Redmine JSON API 读取 issue**，再结合当前代码库做分析。

## 配置来源

优先读取以下配置文件获取 Redmine 地址和 API Token：

- `E:\workspace\Server\Tools\DefCheck\RedmineConfig.yaml`

重点字段：

- `RedmineURL`：当前可用的 API 根地址，通常形如 `https://c7-game-redmine.corp.kuaishou.com/issues.json`
- `RedmineToken`：访问 Redmine API 所需的 Token

> 注意：不要手写固定 token，优先从配置文件读取当前仓库中的配置。

## 推荐流程

### 1) 提取 issue ID

issue ID 可能来自：

- 完整链接：`https://gamecloud-redmine.corp.kuaishou.com/1007/projects/c7/issues/262453`
- 纯单号：`262453`
- 标题里附带的 `[262453]`

优先提取纯数字 issue ID。

### 2) 优先使用 API，不依赖页面 HTML

如果 `RedmineURL` 是：

```text
https://c7-game-redmine.corp.kuaishou.com/issues.json
```

则单个 issue API 可按下面方式构造：

```text
https://c7-game-redmine.corp.kuaishou.com/issues/<issueId>.json
```

或直接在 `RedmineURL` 基础上替换：

- `/issues.json` -> `/issues/<issueId>.json`

请求头需要带：

```text
X-Redmine-API-Key: <RedmineToken>
```

### 3) PowerShell 访问示例（Windows）

```powershell
$cfgPath = "E:\workspace\Server\Tools\DefCheck\RedmineConfig.yaml"
$yaml = Get-Content $cfgPath -Raw
$baseUrl = ([regex]::Match($yaml, 'RedmineURL:\s*"([^"]+)"')).Groups[1].Value
$token = ([regex]::Match($yaml, 'RedmineToken:\s*"([^"]+)"')).Groups[1].Value
$issueId = 262453
$issueUrl = $baseUrl -replace '/issues\.json$', "/issues/$issueId.json"
$headers = @{ 'X-Redmine-API-Key' = $token }
Invoke-WebRequest -Uri $issueUrl -Headers $headers -UseBasicParsing | Select-Object -ExpandProperty Content
```

如果只想快速看关键字段，可继续解析 JSON：

```powershell
$content = Invoke-WebRequest -Uri $issueUrl -Headers $headers -UseBasicParsing | Select-Object -ExpandProperty Content
$data = $content | ConvertFrom-Json
$data.issue | Select-Object id, subject, status, category, assigned_to, fixed_version, description | Format-List
```

### 4) 页面链接与 API 域名不一致时的处理

常见情况：

- 用户给的是页面链接域名：`gamecloud-redmine.corp.kuaishou.com`
- 实际可读 API 域名在配置里：`c7-game-redmine.corp.kuaishou.com`

这时按以下优先级处理：

1. **先相信配置文件中的 `RedmineURL`**
2. 页面 URL 只用于提取 issue ID
3. 只要 API 能返回 JSON，就以 API 返回内容为准

## 常见现象与判断

### 现象 1：网页返回 200，但内容只有 `<div id="app"></div>`

这通常说明拿到的是前端 SPA 外壳，不是 issue 内容。

处理方式：

- 不继续分析 HTML
- 改用 JSON API

### 现象 2：`/issues/<id>.json` 返回 HTML，而不是 JSON

通常说明：

- 当前域名不是 API 域名
- 被重定向到前端页面
- 未按配置中的可用域名访问

处理方式：

- 改用 `RedmineConfig.yaml` 中的 `RedmineURL` 所在域名重新构造 API

### 现象 3：401 / 403 / 无权限

说明当前 token 无权限或网络环境无法访问。

处理方式：

- 优先确认是否使用了配置中的 token
- 若仍失败，向用户索要最小必要信息继续分析：
    - 报错原文
    - issue 标题
    - description
    - 复现步骤
    - 客户端/服务端日志片段

### 现象 4：拿到 issue 后需要结合代码库分析

按以下顺序收敛：

1. 从 issue 的 `subject`、`description`、日志堆栈中提取：
    - 文件名
    - 行号
    - 组件名 / Service 名 / Entity 名
    - RPC 名（如 `Req*` / `Sync*` / `Notify*`）
2. 优先定位：
    - `Client/Content/Script/Data/NetDefs/`
    - `Server/script_lua/Logic/Components/`
    - `Server/script_lua/Logic/Service/`
    - `Server/script_lua/Logic/Entities/`
    - `Client/Content/Script/Gameplay/LogicSystem/`
3. 若是报错日志，优先沿堆栈中的首个项目文件继续向上追调用链

## 输出建议

拿到 issue 后，优先整理以下信息再开始代码分析：

- issue ID
- 标题
- 状态 / 分类 / 指派人
- 报错原文或描述摘要
- 是否有附加文档链接
- 对应代码文件与关键调用链
- 最可能的问题来源
- 建议验证方式

## 最小结论模板

```markdown
## Redmine 信息
- Issue: <id>
- 标题: <subject>
- 状态: <status>
- 分类: <category>
- 指派: <assigned_to>

## 报错摘要
- <核心报错或现象>

## 代码库定位
- 入口文件: `<path>`
- 关键函数: `<symbol>`
- 调用链: `A -> B -> C`

## 可能问题
1. <最可能原因>
2. <次可能原因>

## 建议验证
1. <验证步骤>
2. <补充日志/数据>
```

## 注意事项

- 页面链接返回 200 不代表拿到了 issue 内容
- 优先使用配置文件中的 API 地址，不要默认用户提供的页面域名一定可直接读
- 读取到 issue 后，要结合本地代码库继续追踪，不要只停留在 Redmine 描述层
- 如果 issue 描述中包含内网文档链接，可作为补充线索，但核心分析仍以代码和日志为准

