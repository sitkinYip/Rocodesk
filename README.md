# Rocodesk

**Rocodesk**（`ROCO` + `desk`）是《洛克王国：世界》的**配队工作台** ——
一个放配队相关工具的地方，而不是某一个功能。

## 已经能用的

### 一图流生成阵容码

上传阵容截图，自动识别精灵、性格、个体资质、技能、血脉，
生成可直接在游戏里导入的**官方阵容码**，以及给官方 AI 助手用的配队描述。

游戏里手动复刻一支队伍要逐只抄 6×4 个技能名，很容易抄错且很费时间。
这个功能让你**截一张图就够了**。

### 阵容码解析

粘贴一串阵容码，反查出这 6 只精灵、它们的性格、个体资质、技能与血脉。

两条路径**共用同一个结果页**，所以解析出来的内容同样可以逐项手改，
改完会重新生成一串码 —— 「解析 → 微调 → 出码」是一个完整闭环。

## 规划中的

工具清单会越来越长，所以导航按「分区 → 功能卡片」组织：
加功能只是卡片变多，不用新增 tab。

| 工具 | 状态 | 数据是否就绪 |
|---|---|---|
| 属性克制查询 | 计划中 | 18×18 矩阵已在本地 |
| 性格与个体资质对照 | 计划中 | 30 个性格的六维修正在本地 |
| 技能查询与筛选 | 计划中 | 579 个技能的数据已在本地 |
| 精灵图鉴 | 计划中 | 621 只精灵的六维/特性/可学技能已在本地 |
| 伤害估算器 | 暂不做 | 需要先确认官方伤害公式，目前没有可靠来源 |

## 三种用法

| 平台 | 方式 |
|---|---|
| **浏览器** | `flutter build web --release`，把 `build/web` 静态托管即可 |
| **Windows** | `flutter build windows --release` |
| **Android** | `flutter build apk --release` |

> iOS / HarmonyOS 未验证。iOS 需要 macOS 构建；HarmonyOS 需要社区版 Flutter 分支 + DevEco Studio。

### 应用标识

```
Flutter 包名        rocodesk
Android applicationId   com.rocodesk.app
iOS bundle id           com.rocodesk.app
Dart import             package:rocodesk/...
```

> ⚠️ 改这些会让平台把应用当成**另一个应用**（用户升级时本地数据丢失）。
> 定下来之后就别再改了。

## 快速开始

```bash
flutter pub get
flutter run                        # 调试
flutter test                       # 219 条测试
flutter build web --release
```

Windows 上还可以用附带的脚本，它会**构建 + 起静态服务 + 打开浏览器**：

```powershell
powershell -ExecutionPolicy Bypass -File run_web.ps1
```

> ⚠️ `flutter run -d chrome` 在部分环境会因为建不起 WebSocket 调试通道而**白屏**
> （见下面「已知坑」）。所以脚本默认走「构建一次 + 静态服务」这条路，
> 代价是没有热重载。

## 需要自己填的东西

**API Key 由使用者自己填，代码里没有任何硬编码密钥。**

第一次使用请到 **设置 → 模型服务** 填一个支持视觉的模型服务和 Key。

* Key **只存在本机**（Web 用 localStorage，桌面/移动用 shared_preferences），不会上传到任何地方
* 支持 DashScope（通义千问）/ OpenAI / 智谱 / 硅基流动 / Moonshot / 自定义
* 使用过的模型：`qwen3.5-omni-plus`（需要视觉能力）

> 纯前端填 Key 有两个已知限制，请自行判断是否接受：
> 1. **Web 端可能遇到 CORS** —— 取决于服务商是否允许浏览器直连
> 2. Key 以明文存在本地存储里，共用电脑时请注意

## 项目结构

```
lib/
  core/                  纯逻辑，不依赖 Flutter
    teamcodec.dart       阵容码编解码（Python 实现的移植，593 条真实码逐字段一致）
    codec_tables.dart    数据表装载
    pipeline.dart        模型输出 -> 可编码队伍
    skill_matcher.dart   技能名 OCR 纠错（候选只限这只精灵能学的技能）
    variant_hints.dart   形态消歧（按系别自动判定）
    icon_assets.dart     界面图标索引
  features/
    generator/           一图流生成
    parser/              阵容码解析（与生成共用结果页）
    tools/               功能入口容器
    settings/            Key / 模型 / 主题 / 资料库
  theme/                 设计 token（颜色/字号/圆角/动效），UI 层不写死色值
  widgets/               共用组件
test/                    209 条，覆盖编解码等价性、纠错、血脉联动、全字段编辑、解析、UI
tool/                    开发期小工具（不在发布产物里）
assets/
  data/                  编解码器数据表
  icons/                 界面图标 1453 张（技能 579 / 精灵 593 / 特性 242 / 属性 18 / 血脉 21）
  golden/                编解码等价性测试夹具（**不打包进应用**）
```

### 技能图标：官方图鉴缺 92 个，已从 biligame WIKI 补齐

官方图鉴（`compendium/a/s/<技能名>.png`）只给了 487/579 个技能配图，
另外 92 个**在官方 CDN 上根本不存在**。这个结论核对过四个独立来源：

| 检查 | 结果 |
|---|---|
| 官方 CDN 裸 URL / `?v=` / `?t=` | 有图的 200，缺图的一律 404 |
| 官方图鉴的其他目录（12 个候选） | 全 404，只有 `a/s/` 存在 |
| 小程序（洛克工具箱）自己的 `_skm` 表 | 正好 487 条，与"有图标的 487"完全重合，缺的 92 个一个没有 |
| 两个 GitHub 镜像仓库（6 月 / 5 月快照） | 更旧，同样没有 |

但**图标本身是存在的**。游戏客户端的 `SKILL_CONF.json` 指向图集坐标：

```
冰爪 -> Texture2D'.../Atlas/SkillIcon/108020.108020'
贪婪 -> Texture2D'.../Atlas/SkillIcon/718014.718014'
```

而 biligame《洛克王国世界》WIKI 正好按这个编号存图标（`文件:Skill 108020.png`），
并且每个技能页都在 `<meta property="og:image">` 里给出图标地址
（`og:image:alt` 明确写着"…技能图标"）—— MediaWiki 的 `pageimages` API
**不返回**这个，所以只能抓 meta 标签。

补齐结果：**92/97 取到**，剩 5 个（愿力冲击 / 指指点点 / 泥沼 / 甜心护盾 / 聚能）
WIKI 上也没有对应页面，保留退化显示首字。

> 复核与补齐脚本：
> ```
> python tools/analyze_missing_icons.py       # 缺口清单与成因
> python tools/fetch_missing_skill_icons.py   # 从 biligame WIKI 补图
> python tools/export_app_icons.py            # 导出到 app/assets/icons
> ```

### 特性（talent）：精灵固有，只展示不可改

特性是精灵自带的被动 —— **一只是 1 个、不在阵容码里、改不了**。
这和血脉是两件事：血脉 24 选 1 可改，特性天生固定。

数据分两处（都是为了不撑大 `pets.json`）：

```
pets.json.ability_by_code   精灵码 -> 特性名（542 只）
traits.json.by_name         特性名 -> {name, desc, icon}
```

图标 242/242 齐全：官方图鉴 `a/t/<特性名>.png` 给了 175 个，
缺的 67 个从 biligame WIKI 补齐（同一套 `og:image` 抓法）。

界面上是系别/血脉那一行里的一个芯片，**没有编辑入口** ——
点开看完整描述，标题旁明确写「精灵固有 · 不可改」，
免得用户去找"怎么改特性"。

> 补齐脚本：`python tools/fetch_trait_icons.py`

### 精灵头像：官方图鉴缺 81 个，已从 WIKI 补 51 个

阵容码表（teamcode 的 `PETS`）有 623 只，但官方图鉴 `d.json` 只有 621 条，
而且**有 81 个码的全名在 d.json 里根本不存在**
（海盔虫 / 刺盔虫 / 千棘盔 / 波波螺 / 雪绒鸟 …），所以既没有知识库 id
也没有 `image_url`，导出脚本自然拿不到图。

和技能图标同一类问题、同一套解法：**biligame WIKI 有**。
精灵页的 `og:image` 就是形象图（`og:image:alt` = "海盔虫形象"）。

```
542（知识库有图）+ 51（WIKI 补）= 593
仍缺 30 个：云梦豚 / 长江豚 / 棋契陛下 / 钻石蜗 / 鸭吉吉国王 /
            蹦蹦果 / 暮风隐者 / 满月砣 —— 连 WIKI 都没有页面（未实装/新形态）
```

> 补齐脚本：`python tools/fetch_missing_pet_icons.py`
> 缺口核对：`python tools/analyze_missing_pet_icons.py`

#### 这里的文件名规则**和别处不同**，改动前务必看清楚

WIKI 补的图放在 `data/icons2/pet_wiki/`，导出脚本按
`data/icons2/pet_wiki_index.json`（阵容码 -> 文件名）取，**不反解文件名**。

原因是文件名踩了三轮大小写冲突，每次都是静默覆盖：

| 做法 | 结果 |
|---|---|
| 直接用阵容码 | `21` 既是某只的**阵容码**、又是另一只的**知识库 id** → 撞 |
| 加 `w` 前缀 | `wBOj` 与 `wBOJ` 忽略大小写后相同，而 `BOj`/`BOJ` 是两只精灵 → 撞 |
| `u`/`l` 编码大小写 | 解决了源目录内部的覆盖 |
| 导出时 `w`+sha1 前 8 位 | 最终方案，稳定且必不冲突 |

这三轮**全部是被枚举自检抓出来的**，不是我看出来的 —— 所以那两个断言
（`written_files` 冲突检查 + "期望文件名集合 vs 目录实际枚举"）不要删。

### 关于 `assets/golden/`（2.73 MB）
这是 593 条真实阵容码的逐字段快照，`codec_golden_test.dart` 用它做编解码等价性验证。
仓库里带了它，所以 **clone 下来不用先生成就能跑完整测试**。

不想让仓库带这么大的生成物的话，可以删掉这个目录：
那时那 7 个测试会**显式跳过**并提示怎么重新生成（不会静默通过，也不会报错）。
需要用仓库外的知识库跑 `python tools/make_golden_fixture.py` 重新生成。

## 数据来源与重新生成

`assets/data/*.json` 和 `assets/icons/*` 是从一份知识库导出的产物。
**正常情况下你不需要重新生成它们** —— 仓库里已经带了完整的一份。

> ⚠️ **下面这些 `tools/` 脚本不在这个仓库里。** 本仓库只包含 Flutter 应用
> （`app/`）；导出工具链在开发机的上一级目录（`ds/tools/`），因为它还依赖
> 一份体积较大的知识库与图标素材。所以 `python tools/...` 这些命令是
> **开发机上的重建流程**，不是 clone 下来就能跑的。
> 想自己重建的话，照着下面「需要」的三样准备，并使用同名脚本的等价实现。

如果需要更新（例如游戏出了新精灵），需要：

1. 一份知识库（精灵 / 技能 / 属性 / 血脉 / 性格）
2. 图标素材（技能图标 128px、属性图标、血脉徽章、精灵头像、特性图标）
3. Python + Pillow

```bash
python tools/export_data_for_app.py          # 数据表（含 pets/traits）
python tools/fetch_skill_icons.py            # 官方图鉴的图标素材
python tools/fetch_missing_skill_icons.py    # 官方缺的 92 个技能图 -> biligame WIKI
python tools/fetch_missing_pet_icons.py      # 官方缺的 81 个头像 -> 补到 51 个
python tools/fetch_trait_icons.py            # 特性图标（官方 175 + WIKI 67）
python tools/export_app_icons.py             # 生成界面图标
python tools/make_golden_fixture.py          # 等价性测试夹具
```

> ⚠️ `export_app_icons.py` 里有两条硬约束，**不遵守会静默出错**
> （构建成功、不报错，只是图 404）：
> * 文件名必须**全 ASCII**（Flutter Web 对 CJK 文件名资产会 404）
> * 文件名**忽略大小写后必须唯一**（Windows 不区分大小写，而阵容码区分）
>
> 脚本自带自检，违反会直接报错退出。`test/asset_naming_test.dart` 也钉了这两条。

## 已知坑（都实际踩过）

**1. Flutter Web 上 CJK 文件名的资产永远 404**

`flutter build web` 把 `一拳.png` 存成**字面百分号编码**的文件名，
运行时却按原始中文键请求 → 取不到。所以所有资产改用 ASCII 名，
名字到路径的映射放在 `assets/icons/index.json`。

**2. 文件名忽略大小写后必须唯一**

阵容码区分大小写（`0f` 和 `0F` 是两只不同的精灵），而 Windows 文件名不区分。
实测写 542 个头像只能枚举出 385 个，而 Flutter 打包靠遍历目录
→ 157 个静默丢失。

**3. `pubspec.yaml` 的资产目录不递归**

只写 `- assets/icons/` 不会打包子目录。漏声明同样是静默 404。

**4. `flutter run -d chrome` 可能白屏**

它的真代码通过 WebSocket 调试通道下发；通道建不起来时页面上只剩一个
约 7.5 KB 的壳。判断方法：`main.dart.js` 应该约 2.8 MB，
如果只有几 KB，就是这个问题。

## 准确性说明

识别结果**每一项都可以手动修正**（魔法 / 队伍名 / 形态 / 血脉 / 技能），
所以不必担心模型偶尔读错。实测在一张 6 只的阵容图上：

| 字段 | 准确率 | 备注 |
|---|---|---|
| 精灵名 | 6/6 | |
| 性格 | 6/6 | |
| 个体资质 | 6/6 | |
| 技能 | 23/24 | 唯一的错字有候选可一键改 |
| 血脉 | 5/6 | 唯一错的是「恶 / 龙」真歧义，程序会提示 |

技能名纠错会**只在这只精灵能学的技能里找候选**（卡瓦重 46 个，而不是全部 579 个），
所以候选通常只有几条，点一下就能改。

技能选择器给的是**这只精灵能学的全部技能**（level + 技能石 + 全部 18 个血脉技能），
当前血脉下用不了的那些**仍然显示**，只是灰掉并注明「需 X 系血脉」——
因为「改血脉能学什么」正是用户要判断的信息，藏起来反而没法决策。

血脉候选会按本地图标匹配排序，把最可能的 3 个排在最前 ——
实测正确答案进入前 3 的比例是 5/6（**不做自动判定**，只做排序，
因为自动判定实测比模型直接读还差）。

## 测试

```bash
flutter test          # 156 条
```

几个关键的：

* `codec_golden_test.dart` —— **593 条真实阵容码**逐字段解码一致 + 往返逐字节相同
* `asset_naming_test.dart` —— 资产名 ASCII / 大小写唯一（上面两个坑的防线）
* `bloodline_picker_test.dart` —— 24 条血脉一个不漏 + 小屏不溢出
* `knowledge_update_test.dart` —— 更新失败绝不破坏现有数据
* `game_text_test.dart` —— 给助手的描述不含阵容码与队伍名

## 免责声明

非官方工具，与腾讯 / 洛克王国官方无关。数据来自公开图鉴，仅供配队参考。
