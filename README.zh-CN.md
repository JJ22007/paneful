<h1 align="center">Paneful</h1>

<p align="center">
  <b>不折腾的 macOS 分屏工具。</b><br>
  小到一口气能读完,生来就是让你 Fork 和改造的。
</p>

<p align="center">
  <a href="README.md">English</a>
</p>

<p align="center">
  <img src="docs/demo.gif" width="100%" alt="AI agent 一句话整理杂乱的桌面">
</p>
<p align="center"><sub>对 Claude Code 说一句话,杂乱的桌面瞬间归位。真实录屏,agent 思考的几秒做了加速。</sub></p>

Paneful 是一个菜单栏 App,用键盘把窗口摆到位。全部代码约 1700 行 Swift,没有第三方依赖,也不需要 Xcode 工程。想改的东西基本都在一份 JSON 里;JSON 改不了的,自己或者让 AI 编程助手改几行代码就行。

> 界面是英文的。想要中文界面?这正好是一个很适合交给 AI 助手的改造任务,见下文「做一个属于你自己的」。

## 功能

- **键盘分屏**:半屏、四分之一、三分之一、三分之二、最大化、居中、还原、跨显示器。默认快捷键与 [Rectangle](https://github.com/rxhanson/Rectangle) 一致。
- **一键排列**:按 `⌃⌥A`,桌面上所有窗口自动铺开。2 个左右分,3 个三等分,4 个田字格,5 个上三下二,6 个 3×2。规则可以自己改。
- **自定义位置**:用屏幕比例描述任意位置,绑上快捷键。
- **可以交给 agent**:自带 `paneful` 命令行,脚本和 AI agent 可以列出、摆放、排列窗口。
- **一份配置,保存即生效**:改完保存,一两秒内自动应用。写错了会在菜单里提示,不会把 App 搞坏。
- **拖边吸附**:可选,带实时预览。
- **首次启动引导**:四步完成授权、认识快捷键、学会定制。

## 安装

需要 macOS 13 或更新版本,以及 Swift 编译器。没装过的话先运行 `xcode-select --install`。

```bash
git clone https://github.com/JJ22007/paneful.git
cd paneful
bash build.sh install
```

脚本会编译、跑自测、把 `Paneful.app` 装到 `~/Applications` 并启动。之后按欢迎引导,在 系统设置 → 隐私与安全性 → 辅助功能 里打开 Paneful。

### 打算反复编译?先运行一次这个

macOS 把辅助功能权限绑定在 App 的代码签名上。直接从源码编译用的是临时签名,每次重新编译系统都会把它当成新 App:权限失效,而系统设置里的开关可能看起来还是开着的。

```bash
bash scripts/setup-signing.sh
```

这个脚本会在你的登录钥匙串里创建一个自签名证书(只用来给你自己的构建签名),然后重新编译并安装。再授权一次,之后无论怎么重新编译都不会失效。`build.sh` 会自动使用这个证书。

## 默认快捷键

| 快捷键 | 动作 | 配置里的名字 |
|---|---|---|
| `⌃⌥A` | 一键排列所有窗口 | `tileAll` |
| `⌃⌥←` `⌃⌥→` `⌃⌥↑` `⌃⌥↓` | 左 / 右 / 上 / 下半屏 | `leftHalf` `rightHalf` `topHalf` `bottomHalf` |
| `⌃⌥U` `⌃⌥I` `⌃⌥J` `⌃⌥K` | 左上 / 右上 / 左下 / 右下 | `topLeft` `topRight` `bottomLeft` `bottomRight` |
| `⌃⌥D` `⌃⌥F` `⌃⌥G` | 左 / 中 / 右三分之一 | `firstThird` `centerThird` `lastThird` |
| `⌃⌥E` `⌃⌥T` | 左 / 右三分之二 | `firstTwoThirds` `lastTwoThirds` |
| `⌃⌥↩` | 最大化 | `maximize` |
| `⌃⌥M` | 接近最大化(90%) | `almostMaximize` |
| `⌃⌥C` | 居中 | `center` |
| `⌃⌥⌫` | 还原到之前的位置 | `restore` |
| `⌃⌥⌘→` `⌃⌥⌘←` | 向右走 / 向左走:每次半屏,可跨所有显示器 | `nextDisplay` `prevDisplay` |

左半屏或右半屏连按,宽度在 1/2 → 2/3 → 1/3 之间切换。

**跨屏行走。** `⌃⌥⌘→` 每按一次把窗口向右挪半屏:左半屏、右半屏,然后是下一块显示器的左半屏、右半屏,依此类推。`⌃⌥⌘←` 反向走回来。显示器按从左到右排序并首尾相接,所以上下摆放的两块屏也一样能用。如果更想用普通的半屏键做这件事并放弃宽度切换,把 `crossDisplays` 设为 `true`。

## 定制

配置文件在 `~/.config/paneful/config.json`,菜单栏里点 **Edit Config File…** 可以直接打开。只需要写想改的部分,其余沿用默认值。

```json
{
  "gap": 8,
  "dragSnap": false,
  "shortcuts": {
    "maximize": "ctrl+alt+m",
    "center": ""
  },
  "custom": [
    { "name": "Code", "key": "ctrl+alt+1", "x": 0, "y": 0, "w": 0.62, "h": 1 },
    { "name": "Docs", "key": "ctrl+alt+2", "x": 0.62, "y": 0, "w": 0.38, "h": 1 }
  ],
  "tile": {
    "max": 6,
    "rows": { "5": [2, 3] }
  }
}
```

| 字段 | 含义 |
|---|---|
| `gap` | 窗口之间、窗口与屏幕边缘之间的间距,单位 pt。 |
| `dragSnap` | 拖边吸附。开启前建议先关掉系统自带的拖边平铺(系统设置 → 桌面与程序坞),否则会出现两个预览框。 |
| `crossDisplays` | 默认关闭。开启且接了多个显示器时,左 / 右半屏连按会把窗口移到下一块显示器,不再切换宽度。 |
| `shortcuts` | 动作名 → 快捷键。写成 `""` 表示去掉这个快捷键。 |
| `custom` | 自定义位置。`x` `y` `w` `h` 是 0~1 的屏幕比例,原点在左上角。`key` 可以不写。 |
| `tile.max` | 一键排列最多排几个窗口。其余保持不动,优先排最近用过的。 |
| `tile.rows` | 窗口数 → 每行放几个。`"5": [2, 3]` 表示上排 2 个、下排 3 个。没写的数量用默认规则。 |

**快捷键写法**:修饰键加一个按键,用 `+` 连接,不分大小写。修饰键有 `ctrl` `alt` `shift` `cmd`;按键可以是字母、数字、`left` `right` `up` `down`、`return`、`delete`、`space`、`tab`、`escape`、`f1`~`f12` 和常见符号。

**写错了怎么办**:菜单里会出现 "Config Problems",点开能看到具体哪一项有问题。那一项会被跳过,其余照常工作。

[`examples/`](examples) 里有几份可以直接抄的配置:极简、写代码、带鱼屏、Vim 键位、只排四个。

## 让 agent 来操作

Paneful 自带命令行接口。任何能执行 shell 命令的东西都可以替你摆窗口:脚本、启动器,或者 AI agent。

```bash
# 只需一次:把命令放进 PATH
ln -s ~/Applications/Paneful.app/Contents/MacOS/Paneful /usr/local/bin/paneful
```

| 命令 | 作用 |
|---|---|
| `paneful list` | 列出所有窗口:App、标题、位置(屏幕比例) |
| `paneful tile` | 把所有窗口排成网格 |
| `paneful place 0 0 0.6 1 --app Safari` | 把窗口放到任意位置,四个数字是 `x y w h`,范围 0~1 |
| `paneful run leftHalf --title notes` | 对指定窗口执行内置动作 |
| `paneful fullscreen off --app Keynote` | 进入或退出系统全屏 |
| `paneful actions` | 列出动作名 |

`--app` 匹配 App 名或 bundle id,`--title` 匹配窗口标题,都是不分大小写的子串匹配;都不写就作用于当前窗口。用 `&&` 串起来可以一次摆好整个布局。

给你的 agent 几行说明(写进 `CLAUDE.md`、系统提示词,或者直接粘贴),之后正常说话就行:

```markdown
You arrange windows on this Mac with the `paneful` command line tool.
Run `paneful help` to see the commands. Act right away, then reply in one short sentence.
```

命令行是和正在运行的 App 通信的,所以 Paneful 需要开着并且已有辅助功能权限;agent 本身不需要任何特殊权限。

## 做一个属于你自己的

配置不够用,就改代码。这个项目是按「方便人和 AI 读懂、修改」来写的。

1. **Fork** 仓库并 clone 你的 fork。
2. 用你的 AI 编程助手(Claude Code、Cursor、Codex 等)打开它。[`AGENTS.md`](AGENTS.md) 已经写清楚了代码结构、怎么编译、怎么验证。
3. **用大白话说你想要什么**,比如:
   - 「加一个快捷键,把窗口居中并占 60% 宽度,连按在 60% / 80% / 100% 之间切换」
   - 「一键排列时,让当前窗口占左边一半,其余的在右边竖着排」
   - 「拖到屏幕底边时吸附成三等分」
   - 「把界面翻译成中文」
4. 运行 `bash build.sh install` 看效果。

各源文件的分工见[英文 README](README.md#build-your-own) 里的表格。

## 已知限制

- **不能把窗口移到别的桌面(Space)**,也不能新建桌面。macOS 没有公开的接口。
- 全屏、最小化、在其他桌面上的窗口不参与一键排列。
- 有些 App 的窗口有最小尺寸,可能比分到的格子大。
- 快捷键在配置文件里改,没有图形化的录制界面。

## 致谢

快捷键和整体手感参考了 [Rectangle](https://github.com/rxhanson/Rectangle)。如果你想要一个成熟、开箱即用的分屏工具,直接用它就很好。Paneful 的目标不一样:小到你可以把它完全变成自己的。

菜单栏图标来自 [Lucide](https://lucide.dev)(ISC 许可,见 [LICENSES/lucide.txt](LICENSES/lucide.txt))。

## License

[MIT](LICENSE)
