# SwiftColor

功能强大的 macOS 屏幕取色软件，基于 **Swift / SwiftUI / SPM** 构建。

## 功能

### 1. 屏幕取色
- **系统取色器**（`NSColorSampler`）— 无需额外权限，快捷键 `⌘⇧C`
- **放大镜取色** — 实时像素级放大预览（需屏幕录制权限）
- HSB 手动调节、HEX 输入、预设色板
- 多格式一键复制：HEX / RGB / HSL / HSB / CMYK / SwiftUI / NSColor / CSS

### 2. 图片颜色分析
- 拖放或打开图片（PNG / JPEG / TIFF / HEIC / WebP）
- K-Means 主色提取（3–16 色可调）
- 占比条 + 平均色
- 点击图片任意位置取色

### 3. 颜色漫步
10 种漫步模式，在色彩空间中自动游走：
| 模式 | 说明 |
|------|------|
| 色相旋转 | 沿色相环匀速旋转 |
| 互补跃迁 | 互补色之间摆动 |
| 邻近和谐 | 邻近色相轻柔游走 |
| 三角节奏 | 三角配色节奏切换 |
| 柔彩漂流 | 低饱和柔和漂流 |
| 霓虹脉冲 | 高饱和霓虹脉冲 |
| 单色深浅 | 固定色相明度起伏 |
| 随机漫步 | 带惯性的随机游走 |
| 渐变路径 | 两端颜色往复插值 |
| 冷暖交替 | 冷暖色温交替推进 |

可调速度 / 步幅，轨迹可写入历史。

### 4. 前景 / 背景对比度（WCAG）
- 独立设置前景色与背景色（均可屏幕取色、放大镜取色、色板、HEX、HSB）
- 实时文字 / 按钮预览，可调字号与粗体
- 对比度比值 + 进度条（标注 3 / 4.5 / 7 阈值）
- WCAG 2.x 清单：AAA 正文、AA 正文、AAA/AA 大字、AA 控件
- 支持半透明前景相对背景的合成计算

### 5. 历史
本地持久化最多 80 条颜色，支持搜索、右键菜单、网格浏览。

## 环境要求

- macOS 14.0+
- Xcode 15+ / Swift 5.9+

## 构建与运行

### SPM（命令行）

```bash
cd SwiftColor
swift build -c release
swift run
```

也可 `open Package.swift` 用 Xcode 以 Package 方式打开。

### Xcode 工程（推荐调试 / 签名 / 权限）

```bash
open SwiftColor.xcodeproj
```

选择 **SwiftColor** scheme → Run（⌘R）。

若修改了 `project.yml`，重新生成工程：

```bash
xcodegen generate
```

源码位于 `Sources/SwiftColor/`，**SPM 与 Xcode 工程共用同一套源文件**。

## 权限说明

| 功能 | 权限 |
|------|------|
| 系统取色 | 无 |
| 放大镜取色 | 屏幕录制（系统设置 → 隐私与安全性 → 屏幕录制） |

## 项目结构

```
SwiftColor/
├── Package.swift              # SPM（swift build / swift run）
├── project.yml                # XcodeGen 工程定义
├── SwiftColor.xcodeproj       # Xcode 应用工程
└── Sources/SwiftColor/        # 共用源码
    ├── App/
    ├── Models/
    ├── Services/
    ├── Views/
    │   └── Components/
    └── Resources/
        └── Assets.xcassets    # App Icon（Xcode 使用）
```

## 快捷键

| 快捷键 | 动作 |
|--------|------|
| `⌘⇧C` | 系统取色 |
| `⌘C` | 复制当前颜色（默认格式） |
| `Esc` | 取消放大镜取色 |

## License

MIT
