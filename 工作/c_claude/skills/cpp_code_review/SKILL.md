---
name: cpp-code-review
description: 基于项目编码规范（cpp-code-style）对 C++ 代码进行结构化 Review。当用户要求审查 .cpp/.hpp 文件的代码质量、规范合规性、崩溃风险和性能问题时使用。
---

# C++ Code Review

## Overview

When the user asks to review C++ code (files or directories), perform a structured code review based on the review checklist defined in `references/cpp-code-review-checklist.md` and the project architecture in `references/scene_framework_overview.md`.

## Trigger

- User says "review", "code review", "检查", "review下" followed by a file or directory path
- User pastes C++ code and asks for feedback
- User asks to check code quality or style compliance

## Workflow

### Step 1: Read Target Files

- Read the file(s) specified by the user
- If a directory is given, list files and read the relevant `.cpp` / `.hpp` files
- Also read the corresponding header/source counterpart (e.g. reviewing `foo.cpp` → also read `foo.hpp`)

### Step 2: Perform Review

Read and apply the full checklist from `references/cpp-code-review-checklist.md`. Read `references/scene_framework_overview.md` to understand project-specific architecture patterns (Actor lifecycle, component tick flow, combat effect chains, bullet destruction callbacks, etc.) and use this context to identify project-specific risks. Classify each finding by severity.

### Step 3: Output Report

Produce a structured report using the following header, then append the report sections from `references/cpp-code-review-checklist.md`:

```markdown
# C++ Code Review Report

**File(s):** <file paths>
**Reviewer:** AI Assistant
**Date:** <date>

---
```

Followed by all report sections (一、崩溃风险 through 问题汇总) as defined in `references/cpp-code-review-checklist.md`.
