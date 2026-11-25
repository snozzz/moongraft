# 2026 MoonBit 黑客松项目申报书（MoonGraft）

## 一、基本信息

- **项目名称**：MoonGraft —— 面向 MoonBit 与多语言生态的无损三路 CST 结构化合并引擎与多智能体 Git Merge Driver
- **模块名称（`mooncakes.io`）**：`snozzz/moongraft`
- **参赛者 GitHub ID**：`snozzz`
- **GitHub 仓库链接**：https://github.com/snozzz/moongraft
- **开源许可证**：Apache-2.0
- **项目方向**：可复用基础组件库（`mooncakes.io`） / 开发者工具 / 多智能体协同基础设施
- **项目类型**：参考成熟语言生态结构化合并范式与学术论文算法的纯 MoonBit 原生重写与扩展

## 二、项目简介与真实需求

在多人协作与多智能体并行开发（Multi-Agent Worktrees）场景中，传统基于行的 `git merge`（`diff3`）缺乏语法树认知：当两个分支在 MoonBit 文件末尾并行新增 `///|` 顶层函数、移动函数位置并修改内部逻辑、在 `moon.pkg` 中并行引入依赖，或在 `package.json` / `Cargo.toml` / `.yml` 中并行追加键值时，行级合并会频繁产生假冲突（尾逗号陷阱、块顺序冲突），甚至在跨分支函数重命名时产生静默编译损坏。

MoonBit 社区目前已有行级差分库、纯 MoonBit Git（`mizchi/bit`）与双路 AST 对比工具（`moondiff`），但**尚无三路结构化自动合并库**。`MoonGraft` 将 Rust 等成熟生态验证过的无损具体语法树（Lossless CST）三路合并能力引入 MoonBit，既可作为零 FFI 纯库发布到 `mooncakes.io` 供 IDE、Git 工具与 Agent 编排器直接调用，也可作为标准 `git config merge.driver` 命令行与浏览器可视化工作台独立运行。

## 三、核心功能范围、测试与文档交付

1. **全保真无损红绿具体语法树（`src/cst`）**：完整保留空白、缩进、注释与 `///|` 分隔符，满足往返恒等律 `unparse(parse(s)) == s`，配备 SplitMix64 顺序无关多集结构哈希与精确哈希。
2. **六大类语言无损解析器与健全性门禁（`src/lang`）**：原生支持 **MoonBit (`.mbt`/`.mbti`)**、**MoonBit 清单 (`moon.pkg`/`moon.mod`)**、**JSON/JSONC**、**TOML**、**YAML** 及 **TypeScript/JS、Python、Rust**。
3. **双阶段 GumTree 匹配与三路结构化编织（`src/matcher`、`src/merger`）**：支持跨位置 **Move + Edit（移动并修改）复合消解**、JSON/`moon.pkg` 逗号自动规范化、同键新建节递归合并，以及合并后重解析语法/重复键安全回退门禁（零静默数据丢失）。
4. **事后冲突求解、跨分支重命名审计与多智能体 Octopus 合并（`src/solver`、`src/refactor`、`src/workspace`）**：支持直接消解含 `<<<<<<<` 标记的冲突文件、基于词袋 Dice 相似度检测跨分支重命名悬空引用，以及 $K$ 分支并行内存工作区合并。
5. **最小化可运行 Demo、CI 与测试验证**：提供一键运行的最小 Demo（`moon run cmd/demo`、`moon run demo.mbtx`、`./demo.sh`）、跨 Linux/macOS/Windows 三平台严格 CI（`moon check --target all --deny-warn`、`moon test --deny-warn`），以及与真实 `git merge-file` 和 `moon check` 编译器对照的 120 轮随机化差分验证套件（`scripts/verify_harness.py`）。

## 四、参考与移植合规说明

- **参考算法与对标生态项目**：
  1. AST 匹配算法参考论文 *GumTree: Fine-grained and accurate source code differencing*（ASE 2014，[`GumTreeDiff/gumtree`](https://github.com/GumTreeDiff/gumtree)，仅参考论文算法思想，零代码拷贝）；
  2. 结构化对比与三路 Git Merge Driver 交互范式对标 [`Wilfred/difftastic`](https://github.com/Wilfred/difftastic)（MIT 许可证）及 Rust 社区结构化三路合并工具范式。
- **MoonBit 原生重设计与边界说明**：
  - 全部 11,000+ 行 MoonBit 代码均为零第三方源码拷贝的 Clean-Room 原创实现，采用 **Apache-2.0** 许可证，无任何许可证冲突；
  - 针对 MoonBit 语言原生扩展了上游工具不具备的 `.mbt` `///|` 块语义、`moon.pkg`/`moon.mod` DSL 解析、跨分支重命名悬空调用分析与多智能体 N 路 Octopus 内存合并接口；
  - 为保证 `wasm-gc` / `js` / `native` 全后端零 FFI 可移植性，当前版本不依赖外部 C `tree-sitter` 动态语法库，C/C++ 宏展开等留作后续扩展方向。
