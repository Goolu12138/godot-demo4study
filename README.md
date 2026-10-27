# dungeon-extraction

用 [0x72 DungeonTileset II v1.7](0x72_DungeonTilesetII_v1.7/) 素材搭的一个 **搜打撤（search · fight · extract）** 垂直切片：

**标题菜单选角色 → 可走动的休息大厅（买卖 / 换装 / 升级 / 出击）→ 限时进图搜箱清怪 → 从撤离点离开 → 战利品结算成金币 → 回大厅。死亡、超时或主动放弃，本局战利品、背包里的装备和身上的装备全部丢失。**

引擎：**Godot 4.7.2 stable**（Forward+ / D3D12），2D 像素风，基础分辨率 640×360，窗口 1280×720。
项目按 **4.7** 的导入格式提交，请统一使用 4.7.x 打开；用旧版本打开会触发重新导入并改写 `.import`。

![标题菜单](screenshots/menu.png)
![休息大厅](screenshots/hall.png)
![商人](screenshots/hall_shop.png)
![能力](screenshots/hall_abilities.png)
![设置 / 退出](screenshots/hall_settings.png)
![出击确认](screenshots/hall_confirm.png)
![设置（中文）](screenshots/menu_settings_zh.png)

![房间](screenshots/shot_room.png)
![背包](screenshots/shot_bag.png)
![战斗](screenshots/shot_combat.png)
![放弃确认](screenshots/shot_abandon.png)

## 操作

**标题菜单**：点击角色格 → `ENTER REST HALL` → `SETTINGS` / `QUIT`。

**休息大厅**：`WASD` 走到商人 / 教官 / 军需官面前按 `E` 交谈，走到大箱子前按 `E` 打开仓库；走到顶墙的大门会弹出「是否出击」；`Esc` 打开设置（可退出游戏）。

| 按键 | 动作 |
| --- | --- |
| `WASD` / 方向键 | 移动（大厅里只能走，不能挥刀） |
| `E` | 大厅：与 NPC 交谈 / 打开仓库；局内：搜索宝箱 / 木箱 |
| `Space` / `J` / 鼠标左键 | 挥剑（朝当前朝向） |
| `Shift` / `K` | 冲刺（短暂无敌） |
| `Tab` | 打开 / 关闭背包（6 格装备，点击格子丢弃） |
| `R` | 结算界面后：再来一局 |
| `Esc` | 局内 = **放弃本局**（先弹二次确认并暂停）；大厅 = 设置面板（含退出游戏） |

## 核心循环

```
标题菜单（选角色）
   ↓ ENTER REST HALL
可走动的休息大厅
   ├─ 商人 NPC：买 / 卖装备、付费扩容仓库
   ├─ 教官 NPC：能力（永久升级）+ 技能入口（开发中）
   ├─ 军需官 NPC / 大箱子：100 格仓库，免费换装
   └─ 顶墙大门：确认「是否出击」
   ↓
进图（限时 2:30）
   ├─ 搜：宝箱 3 次掉落，木箱 1 次，敌人 55% 贵重品 / 29% 装备
   ├─ 打：清空敌人
   └─ 撤：清场后顶墙的门变开 → 走进去结算
   ↓
撤离成功：贵重品 → 金币，背包装备 → 仓库，RAID +1，身上装备保留
死亡 / 超时 / Esc 放弃（二次确认）：背包清空，武器与护甲退回默认
   ↓
回休息大厅：看上一局结果、整理仓库、再出发
```

- **贵重品**只在撤离成功时折算金币，局内 HUD 上的 `LOOT` 是“还没到手”的估值；
- **装备**掉在地上要走过去捡，先进 6 格背包；背包满了必须按 `Tab` 丢掉一件才能拿新的；
- 撤离后背包里的装备全部进仓库；死亡 / 超时 / 放弃时背包直接清空，身上那件武器和护甲也会从仓库删除；
- 每成功撤离一次，`RAID` 递增，下一局敌人更多、更硬、更快，高阶装备掉率也更高；
- 失败不扣已经存进银行的金币，但会失去当前装备。

## 休息大厅（可走动）

独立场景 `scenes/hall.tscn`，撤离 / 死亡后自动回到这里。角色可以自由走动，但 `Player.combat_enabled = false`（不能挥刀 / 冲刺）。

| 交互对象 | 外观 | 作用 |
| --- | --- | --- |
| **商人 MERCHANT** | doc | 买武器 / 护甲、回收装备、仓库扩容 |
| **教官 INSTRUCTOR** | wizard | 「能力」面板：永久升级 + 技能入口（占位） |
| **军需官 QUARTERMASTER** | dwarf | 站在仓库旁，打开 100 格仓库 |
| **大箱子 STASH** | 2.5 倍宝箱贴图 | 同样打开仓库（`E — OPEN STASH`） |

- 靠近时屏幕下方出现 `E — TALK TO ...` / `E — OPEN STASH`，按 `E` 打开面板，关闭后恢复移动；
- **顶墙的大门**是出击入口，走到门前弹出「是否出击？」，取消后需要先走开再靠近才会再次触发；
- `Esc` 打开设置面板（音量 / 语言 / 按键只读），底部 `QUIT` 直接退出游戏，`CLOSE` / 再按 `Esc` 关闭；
- 大厅顶部显示金币、当前装备与上一局结果（几秒后淡出）；
- 大厅里的随机木箱会被 `Dungeon.clear_crates()` 清掉，避免和仓库/NPC 挤在一起。

### 永久升级（教官的「能力」面板）

| 升级 | 效果 | 价格 | 上限 |
| --- | --- | --- | --- |
| VITALITY | +2 最大生命 | 30 / 55 / 85 | 3 |
| SWIFTNESS | +8% 移速 | 25 / 45 / 70 | 3 |
| MIGHT | +1 剑伤害 | 70 / 140 | 2 |

面板下半部分预留 `SKILLS` 区域（`NEW SKILLS — COMING SOON`），后续在这里接主动技能学习。

### 仓库

- 大箱子 = 仓库，**默认 100 格**，按“件”计（同名装备各占一格，身上的装备也占格）；
- 商人商店的 `STORAGE` 可付费扩容：每次 **+20 格**，价格 150 / 300 / 450 / 600 / 750，最多 200 格；
- 仓库满时：商店不能再买装备；撤离结算优先塞满仓库，塞不下的装备丢弃；
- 仓库面板顶部显示当前容量，例如 `STASH 29/100`。

### 出售

商人面板的 `SELL GEAR` 区列出仓库里的备用装备，点 `SELL` 按**买入价的 50%**（最低 10 金）回收：

- 默认装备（RUSTY SWORD / CLOTH）不能出售；
- 身上正穿着且只剩这一件时不能出售；
- 有多把时只卖一件，仓库格随之空出。

### 装备与售价

| 武器 | 伤害 | 买入 | 出售 | 护甲 | 最大生命 | 买入 | 出售 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RUSTY SWORD | +0 | 默认 | — | CLOTH | +0 | 默认 | — |
| KNIGHT SWORD | +1 | 120 | 60 | LEATHER | +2 | 100 | 50 |
| KATANA | +2 | 300 | 150 | CHAIN | +4 | 250 | 125 |
| GOLDEN SWORD | +3 | 600 | 300 | PLATE | +6 | 500 | 250 |

## 房间生成（出击地图）

每次进图 / 换层都会执行 `dungeon.generate(randi(), raid)`，所以**内容随机、地图骨架固定**：

- **随机**：地板磨损变体、墙面破洞、旗帜、石柱数量/位置、木箱 3~6 个及其位置、宝箱位置、敌人类型/数量/出生点、掉落。
- **固定**：房间尺寸 `26×16`、四周墙与顶部 2 格厚墙、顶墙正中大门、左侧出生点；只有一张矩形房间，没有走廊 / 多房间。
- 目前用 `randi()`，**没有记录种子**，无法复现同一张图；做每日挑战 / 分享种子需要先加 seed。

## 战利品与数值

- 单局限时 **150 秒**，超时视为死亡；
- 玩家 3 颗心（6 点血，可被 VITALITY / 护甲提升），挥剑 1 点伤害（可被 MIGHT / 武器提升），攻击冷却 0.34s，受击 0.85s 无敌；
- 敌人：`goblin` 2 血 / `skelet` 3 血 / `chort` 5 血 / `ogre` 9 血（每 3 个 RAID 出现）；
- 每局敌人数 `4 + RAID`（上限 10），血量与速度随 RAID 成长；
- 宝箱 = 3 次抽取，木箱 = 1 次抽取；每次 58% 贵重品、42% 装备；
- 敌人死亡：55% 贵重品、29% 装备、16% 空手；
- 护甲 / 武器掉率随 RAID 向高阶倾斜；
- 背包 6 格，只装装备；贵重品不占格，直接计入本局估值。

| 贵重品 | 价值 | 权重 |
| --- | --- | --- |
| COINS | 5 G | 50 |
| POTION | 15 G | 28 |
| RELIC | 30 G | 15 |
| IDOL | 60 G | 7 |

## 系统与代码结构

- **主循环**：`main.gd` 负责建房、刷怪、计时、搜索、掉落、背包、清场、撤离/失败结算、Esc 二次确认；
- **大厅**：`hall.gd` 生成房间、玩家、NPC / 仓库箱、出击门与 HUD，并把面板请求转给 UI 层；
- **UI 复用**：`menu.gd` 的 `ui_only = true` 模式只构建商店 / 仓库 / 设置面板，由 `hall_ui.tscn` 给大厅复用；标题菜单仍是同一个脚本的完整模式；
- **NPC / 箱子**：`npc.gd` 既支持分帧动画 NPC，也支持单张贴图 + 缩放（仓库箱），名字牌由大厅放在屏幕空间；
- **确认弹窗**：`confirm_dialog.gd` 是通用 CanvasLayer，`process_mode = ALWAYS`，局内暂停时也能操作；
- **存档**：`user://meta.cfg`，分段 `[meta] / [upgrades] / [gear] / [run] / [settings] / [stash]`，包含金币、升级、装备、仓库列表与容量、战绩、音量、语言；
- **本地化**：`loc.gd` 是 en / zh 词条表，`Loc.t("key")`；切换语言会 `reload_current_scene()`；`--zh` / `--en` 只在本次运行生效、不写存档；
- **素材**：`game.gd` 是唯一入口，解析 `tile_list_v1.7`，按需建 TileSet / SpriteFrames 并缓存，没有手动拖资源；
- **中文字体**：`FontVariation` + 系统字体回退（微软雅黑 / Noto Sans CJK / 苹方），不需要额外字体文件。

## 目录结构

```
project.godot          主场景（menu.tscn）、自动加载（Game / Meta / Loc）、输入与窗口设置
scripts/
  game.gd              素材管线 + 输入注册 + 中文字体回退
  meta.gd              金币、升级、装备、仓库容量、战绩、音量/语言，读写 user://meta.cfg
  loc.gd               en / zh 文案表
  menu.gd              标题菜单；ui_only = true 时只构建商店 / 仓库 / 设置面板
  hall.gd              可走动休息大厅：房间、玩家、NPC / 仓库箱、大门、HUD、面板调度
  npc.gd               大厅可交互对象：分帧 NPC 或单张贴图（仓库箱）
  confirm_dialog.gd    通用二次确认弹窗（暂停时可用）
  main.gd              搜打撤循环：建房、刷怪、计时、搜索、掉落、背包、清场、结算、Esc 确认放弃
  dungeon.gd           房间生成：地板/墙体、碰撞、撤离门、宝箱、木箱、装饰、clear_crates()
  player.gd            移动、挥砍、冲刺、无敌、相机抖动；大厅里 combat_enabled = false
  enemy.gd             追逐、分离、接触伤害、受击击退、血条、死亡
  hud.gd               HUD、背包面板、倒计时、结算面板
scenes/
  menu.tscn            标题菜单
  hall.tscn            可走动的休息大厅
  hall_ui.tscn         纯 UI 层（menu.gd + ui_only）
  confirm_dialog.tscn  二次确认弹窗
  npc.tscn             大厅 NPC / 仓库箱
  main.tscn  dungeon.tscn  player.tscn  enemy.tscn  hud.tscn
tests/
  smoke_test.tscn      63 项：Esc 确认、搜索、背包、撤离、死亡/超时
  menu_test.tscn       55 项：标题、面板、商店、仓库、容量、出售、装备生效
  hall_test.tscn       22 项：移动、商人/教官/军需官/仓库箱、出击确认、Esc 设置
screenshots/           运行截图（带 .gdignore，不参与导入）
0x72_DungeonTilesetII_v1.7/   原始素材，未做任何改动
```

## 运行与自测

在 Godot 编辑器里按 `F5` 即可（默认进入标题菜单）。命令行（把路径换成自己的 Godot）：

```powershell
# 导入资源
godot --headless --path . --import

# 三套测试，退出码 0 表示全部通过
godot --headless --path . res://tests/smoke_test.tscn
godot --headless --path . res://tests/menu_test.tscn
godot --headless --path . res://tests/hall_test.tscn

# 截图：标题菜单 / 中文 / 大厅 / 放弃确认 / 游戏内
godot --path . --resolution 1280x720 -- --menu-shot
godot --path . --resolution 1280x720 -- --menu-shot --zh
godot --path . --resolution 1280x720 res://scenes/hall.tscn -- --hall-shot --en
godot --path . --resolution 1280x720 res://scenes/main.tscn -- --abandon-shot --en
godot --path . --resolution 1280x720 res://scenes/main.tscn -- --demo

# 跳过标题直接进大厅（调试）
godot --path . -- --start
```

> `--demo` / `--shot` / `--diag` 会跳过撤离与死亡惩罚，避免截图时污染存档。
> `menu_test` / `hall_test` 会快照并还原 `Meta`，不会留下测试存档。

### 启动黑屏？

- 主场景必须是 `res://scenes/menu.tscn`，或直接在编辑器按 **F5**；
- `scenes/hall.tscn` 可以单独按 **F6** 运行；
- `scenes/dungeon.tscn` 是空容器，房间内容全在运行时生成，直接 F6 黑屏是正常的；
- 编辑器提示脚本冲突时选 **Reload from disk**，或 `Project → Reload Current Project`。

## 已知限制 / 下一步

- 角色选取只有骑士，其他三个是占位；
- 按键绑定只读；音量作用在 Master 总线，但素材包没有音频，暂时听不到声音；
- 大厅没有回标题菜单的入口（只能退出游戏），也没有存档点 / 信箱等点位；
- 装备只有武器 + 护甲两条数值线，没有耐久、词条、稀有度；
- 背包 6 格；仓库有容量上限，但还没有批量丢弃 / 出售全部 / 排序；
- 教官的「技能」只有入口占位，还没有主动技能；
- 只有一张矩形房间、没有走廊 / 多房间 / 小地图；地图随机内容但不支持种子复现；
- 搜索是瞬时完成，没有读条 / 噪音引怪；
- 美术只用了低墙（16×16），高墙图集 `atlas_walls_high-16x32.png` 未接；
- 敌人是直线追逐 + 分离，没有寻路绕墙；没有音效 / 音乐。

比较自然的下一步：教官技能系统、多房间地图与种子、搜索读条与噪音、仓库整理/批量出售、音效、改键。

## 交接给下一次对话

> 交接时间：2026-10-28。当前分支 `dev-gyp`，最后提交 `eef6c9c`。

### 1. 先提交这些新文件（重要）

最后一次提交只包含了“已跟踪文件”的改动，**大厅相关的新文件还是 untracked**，此时新克隆仓库会缺场景、跑不起来：

```
?? scenes/hall.tscn  scenes/hall_ui.tscn  scenes/npc.tscn  scenes/confirm_dialog.tscn
?? scripts/hall.gd  scripts/npc.gd  scripts/confirm_dialog.gd（含 .uid）
?? tests/hall_test.gd / .tscn
?? screenshots/hall*.png  screenshots/shot_abandon.png
```

建议先执行：

```powershell
git add scenes/hall.tscn scenes/hall_ui.tscn scenes/npc.tscn scenes/confirm_dialog.tscn
git add scripts/hall.gd scripts/hall.gd.uid scripts/npc.gd scripts/npc.gd.uid
git add scripts/confirm_dialog.gd scripts/confirm_dialog.gd.uid
git add tests/hall_test.gd tests/hall_test.gd.uid tests/hall_test.tscn
git add screenshots/hall*.png screenshots/shot_abandon.png
git commit -m "feat: add walkable hall scene files"
```

提交前先 `git status` 确认没有把 `.godot/`、`*.import` 的无关改动带进去。

### 2. 先跑一遍验证

```powershell
godot --headless --path . res://tests/smoke_test.tscn   # 63 项
godot --headless --path . res://tests/menu_test.tscn    # 55 项
godot --headless --path . res://tests/hall_test.tscn    # 22 项
```

全部 `0 failure(s)` 再开始改。

### 3. 本机环境

- Godot：`C:\Users\guyangpeng\Desktop\Godot_v4.7.2-stable_win64.exe`（4.7.2.stable）
- 项目根：`D:\godot-program\dungeon-demo\godot-demo4study`（仓库在外层 `dungeon-demo` 里面）
- 存档：`%APPDATA%\Godot\app_userdata\dungeon-demo\meta.cfg`，删掉即可重置进度

### 4. 改动约定（避免踩坑）

- **语言**：所有新文案必须同时加进 `loc.gd` 的 `en` / `zh`，用 `Loc.t("key")`；不要硬编码中文/英文。
- **存档兼容**：`Meta` 新字段要在 `load_data()` 给默认值，老存档才不会崩；改完用 `menu_test` / `hall_test` 的 snapshot/restore 验一下。
- **UI 复用**：大厅的商店 / 仓库 / 设置都走 `hall_ui.tscn`（`menu.gd` + `ui_only`），不要在大厅里复制一套面板逻辑。
- **测试**：新增逻辑尽量在对应 `tests/*_test.gd` 加断言；测试会快照并还原 `Meta`，不要在测试里写死用户存档。
- **素材**：统一从 `Game` 取，不要手动拖资源；`.godot/` 已忽略，`*.import` 要提交。
- **版本**：统一 Godot 4.7.x，别用旧版打开，否则 `.import` 会被反向改写。

### 5. 建议的下一步

1. **教官技能系统**：在 `menu.gd` 的 `SKILLS` 占位处接入主动技能（数据放 `meta.gd`，按键/冷却在 `player.gd`），技能需求先和用户确认。
2. **多房间地图 + 种子**：把 `dungeon.gd` 的固定 26×16 扩展为房间模板 / 走廊，`main.gd` 传入可记录 seed。
3. **仓库整理**：批量出售、按品质排序、容量不足提示。
4. **音效**：素材包没有音频，可用 `AudioStreamGenerator` 或外部音效，音量接口已经接在 Master 总线。
5. **改键**：`game.gd::_setup_input()` 已集中注册，接 `InputMap` 保存即可。
