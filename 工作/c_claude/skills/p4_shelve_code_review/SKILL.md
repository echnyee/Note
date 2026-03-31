---
name: p4-shelve-code-review
description: Fetches Perforce changelist content (shelved or submitted) by CL number and performs structured C++ code review. Use when the user provides a P4 changelist number and wants a code review.
---

# P4 Changelist Code Review

## Overview

When the user provides a Perforce changelist number, fetch the file content and perform a structured code review. This skill handles both **shelved** and **submitted** changelists. Use the full review checklist from `references/cpp-code-review-checklist.md`, applied to the diff/changed code.

## Trigger

- User says "review", "review下", "看下" followed by a P4 changelist number
- User says "p4 shelve", "p4提交", "changelist" followed by a number

## Workflow

### Step 1: Get Changelist Metadata

First try shelved:
```bash
p4 describe -S <CHANGELIST_NUMBER>
```

If no shelved files found (output contains "Affected files" but no "Shelved files"), it's a submitted CL — use:
```bash
p4 describe <CHANGELIST_NUMBER>
```

Parse the output to extract:
- Changelist description
- List of affected/shelved file paths (lines starting with `...`)
- Inline diff (the `Differences` section)

### Step 2: Fetch Full File Contents

For each changed file, fetch the full content at the changelist revision:

**Shelved changelist:**
```bash
p4 print "<FILE_PATH>@=<CHANGELIST_NUMBER>"
```

**Submitted changelist:**
```bash
p4 print "<FILE_PATH>#<REVISION>"
```
where the revision number comes from the `p4 describe` output (e.g. `#144` in `...path#144 edit`).

Read the full file content around the changed areas to understand context. For large files, focus on the diff regions ±50 lines.

### Step 3: Analyze the Diff

Use the diff from `p4 describe` to identify exactly what changed:
- Lines starting with `<` are removed (old code)
- Lines starting with `>` are added (new code)
- Line numbers like `274c274,279` indicate the change location

### Step 4: Perform Code Review

Read and apply the full checklist from `references/cpp-code-review-checklist.md`. Read `references/scene_framework_overview.md` to understand project-specific architecture patterns (Actor lifecycle, component tick flow, combat effect chains, bullet destruction callbacks, etc.) and use this context to identify project-specific risks. Analyze the **changed code** (not unchanged code). Cross-reference with unchanged surrounding code for context. Focus review effort on new/modified logic.

### Step 5: Output Report

Produce a structured report using the following header, then append the report sections from `references/cpp-code-review-checklist.md`:

```markdown
# P4 Code Review

**Changelist:** <number>
**Description:** <from p4 describe>
**Reviewer:** AI Assistant
**Date:** <date>

---

## 变更概述

<1-3 sentence summary of what the changelist does>

---
```

Followed by all report sections (一、崩溃风险 through 问题汇总) as defined in `references/cpp-code-review-checklist.md`.
