# 触屏键盘

手机使用 **GNOME Shell 自带的屏幕键盘**（已处理好 Wayland 文本输入、长按弹出、表情和锁屏），再加上我们自己的两套布局，以一个小的 GNOME Shell 扩展 `sky-osk`（`rootfs/sky-osk/`）提供：

| 方向 | 布局 | 说明 |
|---|---|---|
| 竖屏 | `sky` | **正交（ortholinear）** 10 x 5 网格，按键上下对齐成直列，左右贴齐屏幕边缘。最上面一行是功能条：Esc、Tab、Ctrl、Alt、四个方向键、Hm（Home）、End；接着是 `q-p`、`a-l` 和 `'`、Shift + `z-m` + 退格，底行 `?123`、表情、`,`、空格、`.`、收起、回车。长按字母输入重音字符。 |
| 横屏 | `sky-split` | **Planck 风格的分体键盘**：4 行，每行左 6 + 右 6 个键，同一个正交网格。左半 `Tab q w e r t` / `Esc a s d f g` / `Shift z x c v b` / `收起 Ctrl Alt Super Lower 空格`；右半 `y u i o p 退格` / `h j k l ; '` / `n m , . / 回车` / `空格 Raise` + 方向键。两半贴齐屏幕左右边缘，**中间的空隙可穿透点击**（该处键盘透明，点击直达下面的应用）。占屏幕高度的 50 %。 |

分体布局的拇指键与 Planck 相同：**Lower** 给出数字和符号，**Raise** 给出 F1–F12、Home/End、PgUp/PgDn、Del、方向键、括号、表情和语言键。Ctrl、Alt、Super 是单次锁定（先点修饰键，再点字母）。

数字、电话、邮箱、网址、终端输入框，以及 `us` 以外的输入法，仍使用 GNOME 自带键盘。布局随显示器方向切换（没有传感器，请在设置 > 显示 里手动旋转）。

## 何时出现
触摸文本框且最近一次输入来自触摸屏时，GNOME 会弹出键盘；用（扩展坞的）实体键盘打字时不会。要强制显示：顶栏辅助功能菜单 > 屏幕键盘（即 `org.gnome.desktop.a11y.applications screen-keyboard-enabled`）。从屏幕底边上滑也能打开。

## 安装
根文件系统构建（`tools/push-debian.sh`）会安装并启用。已在运行的手机上：

```sh
tools/build-sky-osk.sh install      # 生成布局，在手机上编译，复制扩展（会在手机上装 libglib2.0-dev-bin）
# 注销再登录一次（Wayland 只在新会话里加载新扩展），然后
gnome-extensions enable sky-osk@redmi-12-5g.local
```

## 自定义
| 想改什么 | 在哪里 | 如何生效 |
|---|---|---|
| 按键、宽度、间隔、长按候选、分体布局的几何尺寸 | `tools/gen-sky-osk-layouts.py`（普通 Python，`portrait()` 与 `split()`） | `tools/build-sky-osk.sh install`，然后 `gnome-extensions disable` 再 `enable` |
| 键盘高度（占屏幕比例） | `rootfs/sky-osk/config.json`：`portraitHeight`、`landscapeHeight` | 同上 |
| 字号、间距、圆角 | `rootfs/sky-osk/stylesheet.css` | 同上 |
| 行为（何时用哪套布局） | `rootfs/sky-osk/extension.js` | 安装后注销再登录（JavaScript 模块有缓存） |

布局格式是 GNOME Shell 自己的 JSON（见 GNOME Shell 的 `js/ui/keyboard.js`）：`levels`（`default`、`shift`、`opt` = Lower/符号、`opt+shift` = Raise），每层是网格上的若干 `rows`。按键有 `strings`（第一个是输入内容，其余长按时出现），可选 `width`（列数，默认 1）、`leftOffset`，或 `action`（`levelSwitch`、`delete`、`emoji`、`languageMenu`、`hide`、`modifier`）加 `iconName` 或 `label`；Esc、方向键等用 `keyval`。竖屏布局 10 列宽；分体布局 19.5 列（左半 6 列、间隔 7.5 列、右半 6 列），生成器里的 `check()` 会打印每一行的宽度，改动时能立刻发现不齐。宽间隔需要隐形占位键，因为 GNOME 的网格会丢弃没有任何按键占用的列（生成器已处理：`spacers=True`）。扩展随后隐藏占位键，把分体键盘的容器设为不响应输入（Wayland 下 GNOME 不使用 chrome 输入区域，这是间隔可穿透点击的实现方式），并把网格拉伸到整个宽度。

适合这种格式的想法：字母上方加数字行（加一行）、偏向一侧的单手布局（行首加占位）、更宽的间隔或更矮的分体键盘、拇指层里换别的标点、竖屏功能条里加语言键（`lang()`）。

## 限制
- 只替换 `us` 输入法。其他输入法（如中文输入法）保持 GNOME 自带布局（含语言键）；竖屏布局没有语言键，可用分体布局的 Raise 层，或在 `portrait()` 里加上 `lang()`。
- 没有触觉反馈、滑行输入，也没有我们自己的候选词（输入法引擎提供时 GNOME 会显示 IBus 候选）。
- 在 GNOME Shell 48.7（Debian trixie）上测试，用 shell 内部截图核对：横屏默认层和 Raise 层，竖屏默认层和符号层（符号层是竖屏布局的早期版本，10 x 5 版本只截了默认层）。可穿透的间隔通过询问 shell「间隔处某点下是哪个对象」验证（不是键盘），按键处则是按钮。**真实触摸打字、长按弹出、修饰键（尤其是 Super）、表情/收起/语言键、锁屏和扩展坞尚未测试。**

## 为什么不用别的键盘
Squeekboard（Phosh）和 wvkbd 需要 GNOME 合成器不提供的 `input-method-v2` / layer-shell 协议；Onboard 只能通过 XWayland 工作；GJS OSK 扩展用自己的实现替换整个键盘（没有真正的分体布局，设置很多）。扩展自带键盘保留了文本输入集成，只需要约 200 行代码。
