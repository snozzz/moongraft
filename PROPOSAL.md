# 2026 MoonBit 黑客松项目申报书（PROPOSAL）

## 1. 项目基本信息

- **项目名称**：`MoonGraft`（纯 MoonBit 语法感知三路 CST 结构化合并引擎与多智能体 Git Merge Driver）
- **模块名称**：`snozzz/moongraft`
- **开源许可证**：Apache-2.0
- **参赛赛道 / 方向**：开发者工具 × AI 协同基础设施 × 通用基础库
- **目标后端**：全后端支持（核心算法包零 FFI，同时支持 `wasm-gc`、`js`、`native` 编译与运行）

---

## 2. 真实痛点与立项背景

在 AI 辅助编程与多智能体并行开发（Multi-Agent Coding / Parallel Worktrees）成为主流工作流的背景下，多个 Agent 或开发者同时修改同一仓库已成常态。然而，Git 默认的三路行合并算法（`diff3`）完全不理解编程语言与配置文件的语法结构，导致大量**本无语义冲突的并行修改触发假冲突（False Conflicts）**，甚至在部分场景下产生**静默语义损坏**：

1. **MoonBit 原生块结构痛点**：MoonBit 官方规范推崇以 `///|` 分隔顺序无关的顶层声明与测试块，但两个分支同时在文件末尾新增函数、移动函数并修改函数体，或同时在 `moon.pkg` 的 `import { ... }` 块中引入新包时，传统 `git merge` 100% 产生行冲突。
2. **配置文件尾逗号陷阱（Trailing-Comma Trap）**：在 `package.json`、`Cargo.toml` 内联表、GitHub Actions `.yml` 中并行追加依赖或步骤时，行级合并因上一行末尾逗号变化必然冲突，人工或简单脚本消解极易破坏语法合法性。
3. **跨分支重命名语义悬空引用**：分支 A 将函数 `parse_config` 重命名为 `load_config`，而分支 B 新增了对旧名 `parse_config` 的调用——行级合并表面“零冲突”，实则直接破坏编译。

同时，MoonBit 生态虽已有行级差分库（`ruifeng/diff`、`mizchi/bit_diff_core`）、纯 MoonBit Git 实现（`mizchi/bit`）以及双路 AST 对比工具（`moonbit-community/moondiff`），但**完全空白于“无损三路 CST 结构化自动合并（Three-Way Structural Merge）”这一核心拼图**；而 Rust 生态的 `Mergiraf` 既不支持 MoonBit 语法（`.mbt` / `moon.pkg` / `moon.mod`），也无法以零 FFI 纯 Wasm-GC / JS 库形态嵌入浏览器 IDE（Moonpad）或纯 MoonBit 多智能体编排运行时。

---

## 3. 核心技术方案与四大评分维度对齐

### 01 工程深度与实现强度
- **全保真无损红绿具体语法树（Lossless CST，`src/cst`）**：完整保留源码全部空白、缩进、注释与 `///|` 分隔符，严格满足往返恒等律 `parse_cst(src, lang).unparse() == src`。
- **六大类语言前端支持（`src/lang`）**：原生支持 **MoonBit (`.mbt`/`.mbti`)**、**MoonBit 清单 (`moon.pkg`/`moon.mod`)**、**JSON/JSONC**、**TOML**、**YAML** 以及 **TypeScript/JavaScript、Python、Rust**。
- **完整工具链形态**：同时交付可复用的 `mooncakes` 风格库 API、兼容 `git config merge.driver` 协议的命令行工具（支持 `merge`、`solve`、`diff`、`inspect`、`bench-suite`、`setup` 六大子命令）、多智能体 N 路 Octopus 内存工作区合并器（`src/workspace`）以及纯 MoonBit 编译驱动的浏览器交互式可视化工作台（`web/index.html`）。

### 02 技术贡献与攻关
- **交换律多集 Merkle 哈希设计**：对 `CommutativeByKey` 与 `CommutativeBlocks` 容器采用 SplitMix64 雪崩混合 + XOR/Sum 顺序无关子哈希聚合，使重排或仅格式化变更的子树在 $O(1)$ 时间内精确识别等价性。
- **双阶段 GumTree + 语义签名匹配与 LIS 移动检测（`src/matcher`）**：结合按高度优先级的自顶向下同构匹配、跨位置声明签名关联（实现 **Move + Edit 移动与内部修改复合消解**）以及基于最长递增子序列（LIS）的最小移动集合判定。
- **标量字面量原子保护与分隔符自动合成（`src/merger`、`src/diff3`）**：精确重排并合成 JSON / `moon.pkg` 逗号与 `///|` 块分隔符，防止尾逗号语法破坏；在子行词法合并中严格锁定字符串与语义化版本号字面量原子性。
- **合并后语法与重复键健全性门禁（Post-Merge Soundness Gate）**：任何零冲突合并产物均自动重解析校验括号配对、语法错误节点与重复声明签名；一旦发现潜在不安全情形立即保守回退至 `diff3`，杜绝静默损坏代码。
- **跨分支重命名与悬空调用检测（`src/refactor`）**：基于去签名词袋 Dice 相似度（$\ge 65\%$）自动识别跨分支符号重命名，并精准报告或无损传播另一分支新增的过期引用。

### 03 生态增量与外部基线对比
- 以 **GNU/Git `git merge-file --diff3`** 作为外部硬基线：在覆盖 6 类语言的 16 个典型多智能体并发修改场景中，Git `diff3` 仅能无冲突合并 **1/13 (7.7%)**，而 `MoonGraft` 无冲突合并 **13/13 (100%)**，且对 3 类真实语义冲突（如 `Delete-Modify`、同键标量冲突）保持 **100% 准确拦截**。
- 可直接作为底层库接入纯 MoonBit Git（如 `mizchi/bit`）、AI Agent 并行编排框架以及云端/浏览器端代码编辑器。

### 04 开发与验证能力闭环
- 构建了**单元测试 + 代数定律属性测试（幂等律、左右单位元律、交换律）+ 外部真实 `git merge-file` 差分测试 + 真实编译器闭环校验（调用 `moon check`、`python3 ast/json/tomllib` 校验合并产物可编译性）+ 120 轮随机化模糊演化测试**（`scripts/verify_harness.py`）+ **`moon bench` 性能基准**的完整工程闭环，并在开发过程中实际捕获并沉淀了 4 项关键回归用例（详见 `ARCHITECTURE.md`）。
