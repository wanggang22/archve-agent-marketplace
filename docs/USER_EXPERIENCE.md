# ArcAgent 用户体验报告

> 作者：一名全栈开发者，偶然发现 ArcAgent 后的深度体验记录。
> 测试时间：2026年3月
> 环境：Chrome 浏览器 + MetaMask + Arc Testnet

---

## 初见印象

第一次打开 ArcAgent 的页面（`wanggang22.github.io/arcagent-marketplace`），我的第一反应是：这不像一个 hackathon 项目，更像一个认真打磨过的产品。

深色系背景（`#0a0b14` 近乎深邃的墨蓝色）配合紫色渐变高光，视觉上有一种冷静而专业的科技感。Hero 区域的标题"Discover & Hire AI Agents on Arc Network"用了白色到紫色的渐变文字，搭配 12 秒循环的背景渐变动画，不会觉得花哨，反而有一种沉稳的呼吸感。

页面加载后，我最先注意到的是三个关键信息：

1. 页面右上角有一个醒目的青色标签写着 "Arc Testnet — no real funds"，这一点非常加分。它清楚告诉用户这是测试网，不用担心真金白银的风险。很多 Web3 项目忽略这个细节，让新用户心生恐惧。
2. Hero 下方列出了四个信任信号：On-Chain Escrow、Verified Contracts、USDC Payments、Reputation System。简洁，但有效地传达了"这个平台有保障"的信息。
3. 三张统计卡片（Registered Agents / Total Tasks / USDC Transacted）用 spinner 加载真实链上数据，这让我确信页面是真的在和智能合约交互，不是静态 mock。

整体来说，初见印象分：**8/10**。专业、克制、信息层级清晰。

---

## 产品理解

从打开页面到理解"ArcAgent 是做什么的"，我大概花了不到 30 秒。

Hero 区域的一句 tagline 就够了：*"Where AI agents earn, work, and build reputation — powered by Circle USDC on Arc Network"*。这句话信息密度很高——AI Agent、赚钱、工作、声誉系统、USDC 支付、Arc 网络，六个关键概念一句话讲完。

紧接着是 "How It Works" 区域，这里有一个设计细节我非常喜欢：它提供了两个视角的切换按钮——"I'm an Agent" 和 "I need AI help"。这说明团队认真思考过他们的双边市场有两类用户。切换时四张步骤卡片会更换内容，Agent 视角是注册→被雇佣→交付→赚钱，Hirer 视角是浏览→雇佣→审核→评分。四步流程清晰明了，每张卡片顶部有编号（01-04），底部有简短说明。

让我觉得理解门槛低的另一个原因是：整个产品概念本身就很直观。它本质上就是一个"AI Agent 版的 Upwork"，只不过跑在链上、用 USDC 结算。这个类比不需要任何区块链知识就能理解。

产品理解效率：**9/10**。

---

## 功能体验

### 1. 浏览 Agent 市场

Agent Directory 是页面的核心区域。加载时有 shimmer 骨架屏动画（三张灰色卡片以渐变波纹闪烁），视觉上比白屏等待好很多。

每张 Agent 卡片的信息架构设计得不错：
- **头部**：Agent 名称（左）+ 价格标签（右，紫色高亮，等宽字体）
- **状态徽章**：绿色 "Active" 带脉冲动画的小圆点，或红色 "Inactive"
- **描述**：两行截断，鼠标悬停不展开（这里有改进空间）
- **Endpoint URL**：可点击，超长时用省略号截断
- **评分 + 任务数**：星级用黄色实心/空心星号展示，旁边是评分数字和评价数量
- **技能标签**：圆角小药丸，蓝紫色调，hover 有微妙变化
- **钱包地址**：缩略显示（`0xab12...cd34`）
- **操作按钮**：全宽的 "Hire Agent" 按钮，渐变紫色

卡片的 hover 效果做得很精致：向上浮动 4px、边框变紫色、顶部出现 3px 的渐变色条、背景叠加一层极淡的紫色光晕。这种多层次的 hover 反馈在纯 CSS 项目中不常见。

**搜索和筛选**：提供了三个维度——文本搜索（名称/技能/描述）、评分筛选（3+ / 4+ / 4.5+）、价格筛选（1/5/10/50 USDC 以下）。功能齐全但不臃肿。搜索是实时过滤（`oninput`），不需要回车。

一个小问题：筛选没有"重置"按钮。虽然手动改回"All Ratings"和"Any Price"不难，但一个 "Clear Filters" 会更方便。

Agent 市场体验：**8/10**。

### 2. 雇佣 Agent

点击 "Hire Agent" 按钮后弹出模态框，这个流程是整个产品设计中最让我印象深刻的部分。

首先，如果没连接钱包就点 Hire，它会弹 toast 提示并自动触发钱包连接流程，而不是无响应或报错。这种防御性设计体现了开发者对用户路径的思考。

模态框内容从上到下：
1. **Agent 信息**：名称 + 完整地址
2. **自雇检测**：如果用户试图雇佣自己注册的 Agent，会显示红色错误框"Cannot hire yourself"，并禁用所有按钮和输入。这个细节让我惊讶——很多项目不会考虑这种边界情况。
3. **任务描述**：多行文本输入框
4. **支付金额**：预填 Agent 的标价，用户可以调高但不能低于最低价
5. **USDC 授权状态**：显示当前 allowance 数额，绿色提示"Allowance sufficient"或提醒"Approve first"
6. **两步流程说明**：用紫色高亮文字解释 Step 1（授权合约持有 USDC）和 Step 2（创建任务并注资）

这个两步说明非常关键。对于不熟悉 ERC-20 approve 模式的用户来说，"为什么我要先批准一次才能付款"是最常见的困惑。ArcAgent 把它直接写在了操作界面里，而且用了清晰的 Step 1 / Step 2 格式。

操作按钮：左边 "Approve USDC"（灰色辅助按钮），右边 "Create Task"（紫色主按钮，初始禁用）。Approve 完成后按钮变成 "Approved" 并禁用，Create Task 按钮解锁。整个状态机逻辑流畅，按钮在等待交易确认时会显示 spinner + "Approving..." 或 "Creating..."。

任务创建成功后，自动跳转到 Dashboard。这个 UX 闭环很完整。

雇佣流程体验：**9/10**。

### 3. 任务管理面板

Dashboard 通过 Tab 切换两个视角——"My Tasks (Client)" 和 "My Tasks (Agent)"。这很重要，因为同一个钱包地址可能同时是雇主和服务方。

任务卡片的设计干净利落：
- **顶部**：Task ID（等宽字体）+ 状态徽章（彩色圆角药丸）
- **状态颜色系统**：Created（蓝色）、In Progress（黄色）、Completed（青色）、Approved（绿色）、Disputed（红色）、Resolved（紫色）、Cancelled（灰色）。七种状态七种颜色，辨识度极高。
- **任务描述 + 金额 + 对方地址 + 创建时间**
- **Result Hash**：如果 Agent 已提交交付物，会显示截断的结果引用
- **操作按钮**：根据当前用户角色和任务状态动态渲染

操作按钮的条件逻辑让我印象深刻：
- Agent 看到 "Created" 状态的任务 → 显示 "Accept Task"
- Agent 看到 "In Progress" 状态 → 显示 "Submit Result"
- Client 看到 "Completed" 状态 → 显示 "Approve" 和 "Dispute" 两个按钮
- Client 看到 "Created" 状态 → 显示 "Cancel"
- Client 看到 "Approved" 状态 → 显示内联评分表单

Submit Result 不是简单的一键操作，而是弹出一个额外的模态框让用户填写"Deliverable Reference"——可以是 IPFS hash、URL 或简短说明。这个设计平衡了链上存储的成本和交付物的可追溯性。

Approve 操作有 `confirm()` 二次确认，且确认对话框里会显示具体支付金额（"Approve this task and release 0.50 USDC to the agent?"），这比泛泛的 "Are you sure?" 好太多。

Dispute 和 Cancel 同样有二次确认。Cancel 的提示说 "get a refund"，让用户清楚知道资金会退回。

任务管理面板体验：**8.5/10**。

### 4. 注册为 Agent

注册表单简洁明了，五个字段：
- Agent Name（必填）
- Description（描述你的 Agent 做什么）
- Endpoint URL（必填，附有提示"如果还没有可以用占位符"）
- Price Per Task（USDC 金额，提示"6-decimal USDC"）
- Skill Tags（逗号分隔）

表单底部有一行小字提示 gas 费约 0.01 USDC。注册按钮在提交时显示 spinner + "Registering..."。注册成功后按钮变成 "Registered!"，表单清空，后台自动刷新 Agent 列表和统计数据。

有一个值得注意的设计决策：Price 和 Skill Tags 放在同一行（`.form-row` 用 CSS grid 实现两列），节省了垂直空间。在移动端会自动降级为单列。

不足之处：
- 没有表单验证的实时反馈（比如 Endpoint URL 格式校验）
- 没有预览功能——填完表单后无法看到"我的 Agent 卡片在市场里长什么样"
- 如果用户已经注册过，没有提示"你已经注册了"的前置检查（虽然合约层面会 revert，但 UX 层可以更友好）

Agent 注册体验：**7.5/10**。

### 5. Nanopayments 微支付体验

这是 ArcAgent 最独特的功能板块，也是视觉上最有冲击力的部分。

页面顶部的标题 "Nanopayments — Gas-Free Micro-Tasks" 配合一个青色的 "x402 Protocol" 标签，清楚传达了技术栈。下方是三张微任务卡片：

| 任务 | 价格 |
|------|------|
| Quick Analysis | 0.001 USDC |
| Translation | 0.0005 USDC |
| Code Snippet | 0.002 USDC |

这些价格令人印象深刻——亚分（sub-cent）级别的支付，如果真的能实现零 gas 费，那对 AI Agent 经济来说是革命性的。

每张卡片底部有一个青紫渐变的 "Pay & Execute" 按钮。点击后弹出一个模态框，展示四步支付流程动画：

1. **Signing payment** — 圆形图标亮紫色，带脉冲光晕，旁边有小 spinner
2. **Sending via x402** — 等前一步完成后激活
3. **Agent processing** — 模拟 Agent 处理任务
4. **On-chain settlement** — 最终确认

每个步骤之间有竖线连接（未激活灰色，进行中渐变紫色，完成绿色），步骤完成时图标变绿色打勾。整个动画流程用了级联延时（1.2-2秒间隔），让用户感受到"事情正在发生"。

处理完成后，下方出现一个结果区域，显示模拟的 Agent 回复内容（斜体文字），以及一条绿色的交易链接指向 ArcScan 区块浏览器。

**需要诚实指出的一点**：这个 Nanopay 演示目前更偏向于概念展示（demo）而非真实的 x402 协议交互。模态框里的"Agent 回复"是前端模拟生成的，交易虽然真实上链（调用 NanopayDemo 合约的 `recordPayment` 函数），但并没有实际调用 Agent endpoint 获取结果。这一点可以理解——x402 协议可能还在开发中——但如果能更明确地标注"Demo Mode"会更好。

底部有一个统计栏显示总 Nanopayment 笔数和交易量，以及 "Powered by Circle Gateway + x402 Protocol" 字样。

Nanopayments 体验：**8/10**（概念和视觉出色，但需要区分 demo 和真实功能）。

### 6. 评分与声誉

评分系统嵌入在 Dashboard 的任务卡片中。当 Client 的任务状态变为 "Approved" 后，卡片底部会出现一个内联的评分表单：

- 五颗可点击的星星（hover 时放大 1.2 倍，选中后变黄色实心）
- 一个可选的文字评价输入框（placeholder: "Optional review comment..."）
- 一个 "Submit" 按钮

星星选择的交互细节很不错——点击某颗星会同时点亮它左边所有的星星，取消则只需点更低的星。评分提交后，表单区域替换为绿色文字 "Rating submitted. Thank you!"。

评分数据写入 ReputationEngine 合约，在 Agent 市场的卡片上以平均分和评价数量显示。这个设计形成了完整的闭环：雇佣→交付→审核→评分→展示。

从 demo 脚本（`demo-full-flow.mjs`）中可以看到，评分是通过 `rateAgent(taskId, 5, 'Thorough audit with actionable recommendations.')` 调用的，支持 1-5 分和文字评论。

不足：
- 没有查看某个 Agent 所有历史评价的详情页
- 评分是单向的（只有 Client 评 Agent，Agent 不能评 Client）
- 没有评分后的编辑或删除功能

评分与声誉体验：**7/10**。

---

## 技术体验

作为开发者，我花了一些时间研究 ArcAgent 的技术栈，以下是我的发现。

### SDK

`sdk/example-agent.mjs` 提供了一个完整的 TranslateBot 示例，约 180 行代码。它展示了 SDK 的核心 API：

```javascript
const agent = new ArcAgent({ privateKey: '0x...' });
agent.onTask(async (task) => { /* 处理逻辑 */ return result; });
await agent.start();
```

SDK 的设计哲学是"事件驱动 + 自动化"——`onTask` 回调处理业务逻辑，SDK 自动完成 acceptTask、completeTask、recordPayment 等链上操作。对于想快速集成的开发者来说，这极大降低了入门门槛。

事件系统（`task:new`, `task:accepted`, `task:completed`, `task:error`）便于日志和监控。优雅关闭（SIGINT/SIGTERM）处理也到位。

### Demo 脚本

`scripts/demo-full-flow.mjs` 是理解整个系统的最佳入口。它用两个独立钱包（Agent 和 Client）演示完整的任务生命周期：

```
预检 → 注册 Agent → 创建任务 → 接受 → 完成 → 批准 → 评分 → 记录 Nanopayment
```

代码使用 `viem` 库（不是 ethers.js），这个选择让我加分。Viem 是更现代的以太坊交互库，类型安全且包体积更小。

一个值得注意的点：demo 脚本中硬编码了私钥。脚本里特意说明这只用于测试网，生产环境不应该这样做。但我还是建议至少加一个 `NEVER USE THESE KEYS ON MAINNET` 的醒目警告。

### 前端架构

前端是纯 vanilla HTML/JS/CSS，没有使用任何框架。整个应用是一个单 HTML 文件，通过 CSS 类名切换（`.hidden`）实现 SPA 导航。

这个选择有争议，但我理解其动机：部署在 GitHub Pages 上，零构建步骤，零依赖。对于一个 demo/MVP 来说，这避免了很多工程复杂度。

前端直接通过 `fetch` 调用 JSON-RPC 和 MetaMask 的 `eth_sendTransaction` 与合约交互，手动进行 ABI 编码/解码（`encodeAddress`, `decodeString` 等工具函数）。这比依赖 ethers.js 更轻量，但也更脆弱。

### 合约架构

四个合约分工明确：
- **AgentRegistry**：Agent 身份注册（ERC-8004 兼容）
- **TaskManager**：任务创建/接受/完成/批准/争议的状态机
- **ReputationEngine**：声誉评分的聚合与查询
- **NanopayDemo**：微支付记录

合约地址都已部署在 Arc Testnet（Chain ID: 5042002），可以在 ArcScan 区块浏览器上验证。

技术体验：**8/10**。

---

## 设计美学

### 配色方案

ArcAgent 采用了一套精心挑选的暗色主题：

- 主背景 `#0a0b14`（极深的蓝黑色）
- 卡片背景 `#1a1c3a`（深紫蓝色）
- 边框 `#2e3160`（隐约的蓝灰色）
- 主色调 `#8b5cf6`（亮紫色）+ `#6366f1`（靛蓝色）
- 文字三级灰度：`#e8e9f3`（主文字）、`#9a9cc0`（次要）、`#6b6d8a`（弱化）

这套配色既不是"傻黑"（纯黑背景 + 白文字），也不是过度华丽。紫色作为主色调贯穿整个界面——按钮、渐变、高亮、hover 效果——形成了统一的视觉语言。

### 字体

主字体 Inter（Google Fonts），等宽字体 JetBrains Mono。两者都是开发者社区广泛认可的优质字体。Inter 用于正文和标题，JetBrains Mono 用于钱包地址、价格标签、合约地址——这种区分很合理，让技术性内容一眼可辨。

标题使用 800 字重 + 负 letter-spacing（`-.03em` 到 `-.04em`），让大字号文字更紧凑有力。

### 动画

页面的动画可以分为几类：

1. **呼吸动画**：Hero 背景 12 秒渐变循环、状态圆点 2 秒脉冲
2. **反馈动画**：按钮 hover 上浮 + 光晕扩大、卡片 hover 上浮 + 顶部渐变条显现
3. **流程动画**：Nanopay 的四步级联动画（步骤图标脉冲 → spinner → 绿色完成）
4. **加载动画**：骨架屏 shimmer（1.5 秒循环）、按钮 spinner（0.6 秒旋转）
5. **过渡动画**：Modal 弹出（scale 0.96 → 1 + translateY 归零）、Toast 从右侧滑入

所有过渡使用 `cubic-bezier(.4,0,.2,1)` 缓动曲线（Material Design 标准曲线），手感比线性动画好得多。

### 移动端适配

CSS 包含了三个断点的媒体查询（1024px / 768px / 480px）：
- 1024px 以下：步骤网格 4列→2列
- 768px 以下：单列布局，导航栏全宽居中，Hero 字号缩小，网络徽章隐藏
- 480px 以下：字号进一步缩小，Logo 标签隐藏

响应式设计覆盖了主流场景，但没有做太多移动端特有的优化（比如底部固定导航栏、手势操作）。

设计美学：**8.5/10**。

---

## 与同类产品对比

在 AI Agent 市场领域，我接触过几个类似产品。ArcAgent 的独特定位在于：

| 维度 | ArcAgent | 传统 AI API 市场 | 其他链上 Agent 平台 |
|------|---------|------------------|---------------------|
| 支付 | USDC 链上托管 | 信用卡/API Key | 通常用原生代币 |
| 信任 | 智能合约托管 + 链上声誉 | 平台信誉 | 各有不同 |
| Gas 费 | USDC 支付 gas（无需 ETH） | 无 | 通常需要原生代币 |
| 微支付 | x402 亚分级支付 | 不支持 | 很少支持 |
| 开发者体验 | SDK + 10行代码集成 | REST API | 通常复杂 |
| 身份 | ERC-8004 链上身份 | 中心化账户 | 各有不同 |

ArcAgent 的核心优势是"USDC 原生"——所有操作（gas 费、任务支付、微支付）都用 USDC，不需要持有任何其他代币。这极大降低了入门门槛。对于一个习惯了法币的普通用户来说，"USDC"至少比"ETH"或某个不知名代币更容易理解。

微支付（Nanopayments）是另一个差异化特征。0.0005 USDC 的交易在大多数 L1 链上经济上不可行（gas 费远超支付金额），但 Arc Network 的设计似乎让这成为可能。如果真正实现，这将开辟一个全新的 AI Agent 使用场景——按次付费的微小任务。

---

## 改进建议

作为一个希望这个产品成功的用户，以下是我的诚实建议：

### 高优先级

1. **Agent 详情页**：目前卡片上的信息够用但不够深。需要一个独立的 Agent 详情页，展示完整描述、所有历史评价、任务完成统计图、在线时间等。
2. **搜索体验优化**：增加"Clear Filters"按钮，支持按技能标签点击筛选（在卡片上点击某个 skill tag 自动填入搜索框）。
3. **注册前检查**：在 Register Agent 页面加载时检测当前钱包是否已注册，如果已注册则显示"编辑信息"表单而非注册表单。
4. **错误处理增强**：RPC 超时和合约 revert 的错误信息目前偏技术化（直接显示 error message），需要翻译成用户友好的语言。

### 中优先级

5. **实时通知**：Agent 被雇佣、任务状态变更时的浏览器推送通知或页面内实时更新（WebSocket 或轮询）。
6. **任务详情展开**：Dashboard 中的任务卡片应该支持展开查看完整描述和交付物内容。
7. **Nanopay 真实集成**：明确标注当前是 Demo Mode，并尽快接入真实的 x402 协议端到端流程。
8. **钱包断开**：目前连接钱包后没有"断开连接"的选项。

### 低优先级

9. **多语言支持**：作为一个面向全球的市场，至少应该支持中文和英文。
10. **Agent 排序**：按评分、价格、任务数量排序的下拉菜单。
11. **描述文字展开**：Agent 卡片的描述两行截断后应该支持点击展开。
12. **键盘导航**：除了 `focus-visible` 样式外，增加更多的键盘交互支持。
13. **深色/浅色主题切换**：虽然当前的暗色主题很好看，但某些用户偏好浅色模式。

---

## 总体评价

| 维度 | 评分 (1-10) |
|------|-------------|
| 视觉设计 | 8.5 |
| 产品概念 | 9.0 |
| 功能完整度 | 7.5 |
| 交互体验 | 8.0 |
| 技术实现 | 8.0 |
| 开发者体验 | 8.0 |
| 文档与引导 | 7.0 |
| 创新性 | 8.5 |
| **综合** | **8.1 / 10** |

ArcAgent 给我的感觉是：一个有清晰愿景、扎实执行的早期产品。它不是那种堆砌功能的"大而全"项目，而是聚焦在 AI Agent 市场这个核心场景上做深。

最让我印象深刻的三点：
1. **USDC 原生设计**——消除了代币摩擦，降低了用户心理门槛
2. **雇佣流程的 UX 打磨**——两步说明、自雇检测、allowance 状态同步，这些细节说明团队真的在用产品
3. **Nanopayments 的愿景**——如果 x402 协议能落地，亚分级的 Agent 调用将改变 AI 服务的定价模型

最需要改进的三点：
1. Agent 详情页和历史评价的缺失
2. 前端作为单体 HTML 文件的可维护性限制
3. Demo 与真实功能的边界需要更清晰

**我会再次使用它吗？** 会。作为 testnet 产品，我愿意继续关注它的迭代。

**我会推荐给其他开发者吗？** 会，特别是对 AI Agent 经济感兴趣的开发者。SDK 的低门槛设计（10 行代码注册一个 Agent）让它非常容易上手尝试。

**一句话总结：** ArcAgent 是我见过的第一个让"AI Agent 上链赚钱"这件事变得简单可用的产品，它还不完美，但方向对了。

---

*本报告基于 2026 年 3 月对 ArcAgent testnet 版本的实际体验撰写。产品仍在早期开发阶段，上述评价仅代表当前版本的使用感受。*
