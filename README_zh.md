# git-pullkeep

[![CI](https://github.com/aiti-ai/git-pullkeep/actions/workflows/test.yml/badge.svg)](https://github.com/aiti-ai/git-pullkeep/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/aiti-ai/git-pullkeep)](https://github.com/aiti-ai/git-pullkeep/releases)
![MIT](https://img.shields.io/badge/license-MIT-green.svg)
[![npm](https://img.shields.io/npm/v/git-pullkeep)](https://www.npmjs.com/package/git-pullkeep)
![platform](https://img.shields.io/badge/平台-Linux%20%7C%20macOS%20%7C%20Windows-blue.svg)

[English](README.md) · **简体中文**

`git pull` 因本地改动与上游改动重叠而失败时，**只把真正挡住拉取的那几个文件临时收进一个提交**，
让这几个路径上的工作区变干净、拉取得以通过；其余脏文件全程留在工作区不动。
拉取成功后自动把这个提交拆回未提交状态——本地改动、暂存（staged）状态、未跟踪文件全部原样保留。

## 动机

真实的仓库里永远躺着大量**本来就该长期不提交**的本地改动：本机配置、改到一半的重构、机器专属
修改、方案笔记。任何一台跟踪上游的机器上，每次 `git pull` 都是抽奖：上游一旦碰到你本地改过的
文件，拉取直接拒绝——而惯用的逃生通道全都比问题本身更糟：

- `git stash` + `git pull` + `git stash pop` 挪动**整个工作区**，忘记哪些是 staged 的，一旦
  恢复冲突，冲突标记撒满拉取根本不关心的文件。
- `git pull --autostash` 是同一件事的一条命令版：整棵树进一个 stash，恢复是一次大三方合并；
  未跟踪文件与上游新文件同名时拉取直接中止；中途被打断就永远说不清 pop 到底发生过没有；
  staged 改动回来全部变成未暂存。
- 为了拉一次代码把半成品提交进历史，事后还得清理 `wip:` 噪音。

`git pullkeep` 的原则不同：**挪得最少、证明没动别的、每一步可回滚。** 只有真正挡住拉取的路径
被收进带标记的临时提交；其余 70 个脏文件从头到尾没被碰过；操作前的快照 ref 让 `--undo` 精确
还原；操作后的状态与操作前逐条比对并打印出来——“有没有动到别的东西”是可核对的事实，不是承诺。

```console
$ git status --short
 M src/api/client.ts
 M src/service/handler.ts
 M docs/notes.md            # 另外还有 70 个脏文件，与本次拉取无关

$ git pull
error: Your local changes to the following files would be overwritten by merge:
        src/api/client.ts
        src/service/handler.ts
Please commit your changes or stash them before you merge.
Aborting

$ git pullkeep
==> fetch origin

branch      : main
upstream    : origin/main (a1b2c3d4)
incoming    : 12 file(s) across 14 new commit(s)
dirty       : 72 tracked file(s) + 3 untracked
strategy    : merge
blocking    : 2 file(s) overlap upstream, 2 file(s) will be parked
   - src/api/client.ts
   - src/service/handler.ts

==> snapshot of current working tree -> refs/pullkeep/20261106-101336
    'git pullkeep --undo' restores this exact dirty state at any time
==> temp commit: 3c9f1a2b (2 file(s))
    tagged "wip: pullkeep temp commit" so a later run can detect and collapse it
==> git pull --no-rebase origin main
==> collapsing commits: reset --mixed a1b2c3d4
==> verified: working tree state is identical to pre-pull (75 entries)

done. on origin/main (a1b2c3d4), 72 dirty file(s) still uncommitted.
  undo fully : git pullkeep --undo
  backups    : 1 ref(s) under refs/pullkeep/
```

> 运行时的输出刻意保持 ASCII 英文，这样 Windows 的 GBK 控制台（PowerShell 5.1）不会乱码——
> 上面这段就是原样拷贝。

## `git pullkeep` 与 `git pull --autostash` 的区别

| | ✅ `git pullkeep` | `git pull --autostash` |
|---|---|---|
| 🎯 要挪动的文件 | **只动真正挡住拉取的那几个文件** | 整个工作区 |
| 🛡️ 恢复时的冲突风险 | 没被挡住的文件从头到尾没动过，**不可能冲突** | 全量三方合并，可能卡在 `stash pop` 中间状态 |
| 📦 暂存（index）状态 | **跨越整个流程完整保留** | 丢失 |
| 🧾 可审计性 | 快照 ref + 带指纹的临时提交 + `--dry-run` / `--check` | 无 |
| ↩️ 回滚 | **`--undo` 精确回到操作前**，含未跟踪文件 | 只能翻 `git stash list` 人工排查 |
| 🔁 中断后重跑 | 残留临时提交可检出（exit 31），用 `--continue` / `--recover` 收敛 | 零散的 stash 记录容易丢 |
| 🔒 并发运行 | **同一仓库同一时刻只允许一个写操作**，第二个直接 exit 35，不在 index 上抢 | 完全无协调：两次运行可能同时改写 index 和 stash |
| 📄 未跟踪文件 vs 上游新文件 | 自动挪开保住本地版，拉取继续 | 拉取直接中止，要手动挪走才能拉 |
| ⚙️ 参数透传 | fetch + merge + `--rebase[=merges]`，你写的写法原样传下去 | `git pull` 支持什么就支持什么 |
| ⚠️ 不支持 | 仅当需要收进文件时才拒绝 `--ff-only`/`--squash`/`--no-commit` 等，其余原样透传 | 全部支持 |

## 局限

把脏工作区交给它之前，先读这一节：

- **`--ff-only`、`--squash`、`--no-commit`、`--all`、`--rebase=interactive` 只在确实需要收进
  文件时才拒绝**（exit 21）。没有重叠（拉取保持原生）时它们原样透传、由 `git pull` 自己裁决，
  干净树的 `--ff-only` 直接可用。收进挡路文件必然产生本地提交——这正是这些组合无法在收进
  运行中存活的原因：更新不可能是快进，也必须留一个提交层供事后拆解。
- **真冲突仍然需要人**。pullkeep 在第一个合并/变基冲突处停下（exit 20），绝不替你改冲突标记。
  解决后 `git pullkeep --continue` 继续，或者 `--undo -y` 拿着操作前的精确状态离场。
- **分叉不是魔法。** 本地和上游各走出几十个提交时，冲突与裸 pull 一模一样会发生；pullkeep
  只是让退场（`--undo`）变安全。
- **`--rebase` 会收进全部已跟踪脏文件**——rebase 本身要求干净工作区。“只动挡路文件”的性质
  只属于 merge 模式。
- **merge 模式会把重叠之外的 staged 条目一并收走**。`git merge` 在 index 与 HEAD 不一致时
  直接拒绝启动，哪怕合并根本不碰那些路径；所以 staged 条目和挡路文件同等对待，一并收进、
  事后还原。
- **staged 与工作区内容不同的文件，成功路径会塌成一层**：staged 副本保留工作区版本（并保持
  staged）；单独暂存的那个版本只活在快照里——`--undo` 可以把两层精确还原。
- **从开始到拆解之间，你的改动是真实提交**（临时提交）。这正是拉取得以进行的原因；
  `pullkeep-temp:` trailer 让这种提交永远可识别，`--recover` / `--undo` 负责收尾。
  不要手动在它之上叠提交。
- **写模式需要 `user.name` / `user.email`**（要创建 commit 对象）；`--dry-run` 和 `--check`
  不需要。Git ≥ 2.23、bash ≥ 3.2；Windows 上请用 `git pullkeep` 子命令形式
  （Git for Windows ≥ 2.30），不要用 npm 的裸 shim——它可能命中 WSL 的 bash。

## 安装

单文件 bash 脚本（≥ 3.2），除 `git` 与 POSIX 工具外零依赖。它通过 Git 自带的 dashed-external
机制被发现：`PATH` 上任何名为 `git-pullkeep` 的文件就是 `git pullkeep` 子命令——无需配置、
无需插件系统。npm 只是分发渠道，git 本身从不查任何注册中心。

**全平台（npm）**

```sh
npm install -g git-pullkeep       # v0.1.3 起可用；在此之前请用下面的安装脚本
npx git-pullkeep --dry-run        # 不安装也能直接试
```

**macOS / Linux**

```sh
curl -fsSL https://gitee.com/aiti-ai/git-pullkeep/raw/main/install.sh \
  | GIT_PULLKEEP_REPO=https://gitee.com/aiti-ai/git-pullkeep/raw sh
# GitHub 直连：
curl -fsSL https://raw.githubusercontent.com/aiti-ai/git-pullkeep/main/install.sh | sh
# Homebrew（规划中）
brew install aiti-ai/tap/git-pullkeep
```

**Windows**（PowerShell 5.1+）

```powershell
# 国内走 Gitee：先告诉安装脚本也从 Gitee 取 git-pullkeep 本体
$env:GIT_PULLKEEP_REPO = 'https://gitee.com/aiti-ai/git-pullkeep/raw'
irm https://gitee.com/aiti-ai/git-pullkeep/raw/main/install.ps1 | iex
# 安装到 %USERPROFILE%\bin\git-pullkeep 并追加到用户 PATH
```

**手动安装**：把 `git-pullkeep`（无扩展名、LF 行尾）复制到 `PATH` 上任一目录，
用 `git help -a | grep pullkeep` 验证。

> Windows 说明：请始终用 `git pullkeep`。Git for Windows 会用自带的 bash 执行该脚本，
> 所以子命令形式可用；而 npm 装出来的裸 `git-pullkeep` 可能先命中 `C:\Windows\System32\bash.exe`（WSL），
> 报 `No such file or directory`。另外 `git help -a` 可能多列一条 `pullkeep.ps1`，
> 那是 npm 生成的 PowerShell shim，无副作用。

## 使用

```console
git pullkeep                 # 默认 merge，本地改动全部保留
git pullkeep --rebase        # 变基；所有已跟踪脏文件都会临时收进提交，事后原样还原
git pullkeep --dry-run       # 只分析（仍会 fetch，除非加 --no-fetch）
git pullkeep --check         # 若需要挪动文件或需人工处理则退出码 10（可做 CI 门禁）
git pullkeep --continue      # 解决冲突后拆掉临时的提交层
git pullkeep --recover       # 收敛中断运行留下的临时提交
git pullkeep --undo -y       # 精确回滚到操作前的工作区（`--abort` 是同义词）
git pullkeep --no-fetch      # 直接用当前远端跟踪 ref，不联网
git pullkeep --keep-backups=3 # 只保留最新 3 份快照（默认 5）
git pullkeep origin main     # 显式指定 remote/branch，替代 @{upstream}
git pullkeep -h              # 帮助（务必用 -h：--help 会被 git 接管去查 man 页）
```

### 与 `git pull` 的兼容性

目标是即插即用：**`git pull` 接受的一切都原样透传**——策略类（`--rebase[=merges]`、
`--no-rebase`）、fetch 类（`--prune`、`--tags`、`--force`、`--depth`、`--unshallow`、
`--recurse-submodules`、`--negotiation-tip` 等）、merge 类（`--no-ff`、`-X`、`-s`、`--log`、
`--stat`、`--signoff`、`--verify-signatures` 等）、`--set-upstream`、位置参数
`<remote> <branch>`，以及一切尚不认识的选项（附带警告透传，git 未来新增参数照常能用）。
`--autostash` / `--no-autostash` 接受但忽略——保留你的改动本来就是 pullkeep 的全部工作。
只有当本次运行确实需要收进文件时，才有五种组合被拒绝（exit 21，附原因与替代命令）：

| 收进文件时拒绝 | 原因 |
|---|---|
| `--ff-only` | 收进的文件会产生本地提交，更新永远不可能是快进 |
| `--squash` / `--no-commit` | 必须留下一个提交层供事后拆解 |
| `--all` | 预检 fetch 按名抓取单个远端，`git fetch --all` 拒绝显式 refspec |
| `--rebase=interactive` | 无法脚本化，收进的变基必须无人值守地完成 |

### 退出码

| 码 | 含义 |
|---|---|
| 0 | 成功（含“已是最新”） |
| 2 | 命令行本身有误：未知参数、缺少参数值，或在无终端的环境里用 `--undo` 却没给 `-y` |
| 10 | `--check`：本次拉取需要挪动文件，或需人工处理 |
| 20 | 流程停住、需要人介入：合并/变基冲突，或 `git pull` 本身失败（你的改动没丢） |
| 21 | 被拒绝的参数组合 |
| 30 | 仓库或其环境不可用：非仓库、游离 HEAD、无上游分支、fetch 失败，或未配置 `user.name` / `user.email` |
| 31 | 存在未完成的 merge/rebase，**或** 历史里还残留上次运行的临时提交 |
| 35 | 本仓库已有另一个 pullkeep 正在运行（锁被占用） |
| 40 | 内部错误（若已创建快照 ref，会保留下来供 `--undo` 使用） |

## 工作原理

所有写模式先取仓库锁（见[并发](#并发)），然后：

1. `git fetch`，计算 `incoming = base..upstream`、`dirty = HEAD..工作区`。
2. `blocking = incoming ∩ dirty`；上游新增而同名未跟踪的文件会被搬到 `.git/pullkeep-aside/<stamp>/`；
   `modify/delete`（本地删除 + 上游修改）冲突会在动手前先告警。
3. 把脏工作区快照成 `refs/pullkeep/<stamp>`（一个提交对象，**不是** stash，分支不移动），
   同时记录当时的索引树，使 `--undo` 精确可还原。
4. `git add` + `git commit --only -- <被挡住的路径>`：只包含这些路径的临时提交。merge 模式下，
   重叠之外的 staged 条目也会一并收进——`git merge` 在 index 与 HEAD 不一致时直接拒绝启动，
   哪怕合并根本不碰那些路径；`--rebase` 模式则收进全部已跟踪脏文件（rebase 本身要求干净工作区）。
5. 执行 `git pull <你的参数>`——此时这些路径的工作区是干净的。
6. `git reset --mixed <新上游 tip>` 拆掉临时提交与合并提交；随后把原先 staged 的路径重新暂存，
   索引状态得以保留。
7. 对比操作前后的 `git status --porcelain` 并输出结果，“有没有动到别的东西”是可核对的事实，而不是承诺。

## 安全性：中断与幂等

一次半途而废的拉取（冲突、Ctrl-C、进程被杀）绝不能在永久历史里留下一条
`wip: pullkeep temp commit`。四道独立防线保证这一点：

1. **临时提交自带标识。** 提交信息是 `wip: pullkeep temp commit (N file(s))`，并附一条机器可读的
trailer：`pullkeep-temp: stamp=... base=... upstream=... strategy=...`；同样的事实写入
`.git/pullkeep-meta/<stamp>`。因此检测**不依赖状态文件**：`git gc`、重新克隆、分支被移动后依然能认出来。
2. **下次运行直接拒绝。** 在改动任何东西之前，会扫描 `HEAD` 可达的**最近 50 个提交**
（可用环境变量 `PULLKEEP_SCAN` 调整）。一旦发现有提交带标记，就以 **31** 退出，并提示改用
`--continue` / `--recover` / `--undo`，而不是在旧的临时提交之上再叠一层。
3. **`--recover` 负责收敛。** 只有在答案唯一时它才动手：`@{upstream}`（或位置参数
`<remote> <branch>`）已经合入 `HEAD` 时以它为目标；拉取压根没完成时，则以临时提交的父提交为目标。
其他情形以 20 退出并给出指引——乱猜可能丢掉上游成果。若该临时提交已经进了远端跟踪分支，会明确告警。
4. **已发布的临时提交不动。** 如果标记提交已经能从某个远端跟踪分支到达（误推、或被同事合进上游），
收敛它相当于重写共享历史：此时只报告、不阻断，后续运行照常进行。

实际场景下的幂等行为：

| 场景 | 结果 |
|---|---|
| 在已是最新的分支上再跑一次 | `already up to date`，退出 0，不新增 ref，工作区不变 |
| 拉取冲突，自己 `git add` + `git commit` 解决了 | 下次运行退出 31 并拒绝执行；`--recover`（或 `--continue`）可收敛 |
| 拉取冲突，放弃并 `git merge --abort` | `--undo -y` 精确回到操作前 |
| `git pull` 成功但拆提交层前进程被杀 | 下次运行退出 31；`--continue` 或 `--recover` 收尾 |
| 没有可收敛的临时提交时跑 `--recover` | `nothing to recover`，退出 0 |

## 并发

`--dry-run` 和 `--check` 只读，其余模式都会写。因此写模式（`run`、`--continue`、`--recover`、
`--undo`）会先在**公共** git 目录里取一把锁：

```console
$ git pullkeep                      # 一个终端
$ git pullkeep                      # 同时，另一个终端
git-pullkeep: another pullkeep run is already working in this repository:
git-pullkeep:   pid 48162 on workstation since 20261106-114022
git-pullkeep: wait for it to finish; if you are sure it is gone, delete: /repo/.git/pullkeep.lock

$ echo $?
35
```

- 锁本身是一个 `mkdir`，在 bash 能跑的所有平台上都是原子的——不需要 `flock(1)`，也不存在锁文件竞态。
- 锁放在公共 git 目录里，所以同一仓库的多个 `git worktree` 检出也会被串行化（不同克隆各有自己的
  git 目录，互不干扰）。
- 持有者进程在本机已死时，锁会被自动回收并告警；若锁目录里没有 owner 文件（`mkdir` 之后、写入之前
  被杀），三秒后回收。
- 释放动作挂在 `EXIT` trap 上，所以冲突、Ctrl-C 都不会把锁留下。即使被 `SIGKILL`，下一次运行
  也会发现 owner 已死并接管。

两种“另一个运行”的错误是有意分开的：**35** 表示*等一等*，**31** 表示*这个仓库得先 `--recover`
或 `--undo`*。

## 兼容性

- Git ≥ 2.23；已在 2.24（macOS）/ 2.39 / 2.48 / 2.51 / 2.55 上验证。
- bash ≥ 3.2：macOS 自带 bash 可用（不含 `mapfile`、不依赖关联数组）。
- 仅使用 POSIX 工具，不依赖 `jq` / `python` / `perl`。
- 必须配置 `user.name` 与 `user.email`（每条写路径都要创建 commit 对象）；`--dry-run` 和
  `--check` 不需要，因为它们不创建任何对象。
- 子模块与链接式工作树（`git worktree`）已纳入测试：S15 在子模块里跑，S16 在链接工作树里跑，
  锁与元数据都从公共 git 目录解析。
- Windows：Git for Windows ≥ 2.30。

## 开发与测试

```sh
bash tests/run-tests.sh      # 28 组场景 / 154 条断言，全部在临时仓库内运行
shellcheck -s bash git-pullkeep
```

CI 在 Linux、macOS、Windows（Git Bash）三平台跑测试，并执行 `shellcheck`、`install.sh` 的
`dash -n` 校验以及 `bash 3.2` 语法校验。

## 开源协议

[MIT](LICENSE)
