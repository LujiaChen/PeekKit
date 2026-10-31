# PeekKit

**选中，按空格，预览。**

在 Finder 中浏览文件夹、了解空间占用、阅读 Markdown。

[English](README.md) · [安装说明](docs/INSTALL.md) · [构建说明](docs/BUILDING.md)

![PeekKit 文件夹分析](docs/images/folder-analysis.jpg)

## 1.2.0 更新

- 新增按需展开的树形视图，列表增加类型列，支持名称、大小、日期、类型排序。
- 聚焦浏览区域后用方向键和 Return 浏览；Quick Look 宿主可能截获命令快捷键，可用可见按钮操作。⌘[ 返回，⌘F 筛选，⌘R 刷新，⇧⌘. 切换隐藏文件。
- 右键可定位到 Finder、复制路径、用默认应用打开或选择应用。
- 新增大文件夹排名、容量比例图，支持复制 JSON 和防公式注入的 CSV 摘要。
- Markdown 统一安全渲染，增加有大小上限的词法代码高亮，改善表格及引用，HTML 预览支持可点击目录。
- 排序、读取、解码放到后台；加强导航、取消及缩略图缓存管理。

[更新详情、键盘及限制](docs/UPGRADE-1.2.md)

## 功能

- 文件夹网格和列表视图、子目录浏览、名称/日期/大小排序、名称筛选及隐藏文件开关。
- 后台递归统计逻辑大小和磁盘分配大小，逐步显示结果，可停止和重新扫描。
- 按扩展名显示文件数量和容量；列出两种大小口径各自的前 20 个文件，支持预览和在 Finder 中定位。
- 文件夹内预览图片、PDF、文本和 Markdown；也可直接选中 Markdown 按空格，查看标题、表格、代码、任务列表及原文。
- 日常 Finder 预览无需主应用常驻。Markdown 资源本地提供，预览扩展没有网络权限。

| 浏览文件夹 | 定位大文件 |
| --- | --- |
| ![网格视图](docs/images/folder-grid.jpg) | ![递归大文件列表](docs/images/largest-files.jpg) |

![Markdown 预览](docs/images/markdown-preview.jpg)

上方截图记录 1.1.0，1.2.0 新界面见[升级说明](docs/UPGRADE-1.2.md)。以上为真实应用截图，使用专门制作的示例文件。网格图来自 Finder Quick Look，分析和 Markdown 图来自独立预览窗口，没有展示私人文件夹。

## 安装

要求 **Apple Silicon、macOS 14 或更新版本，以及 Xcode**。当前源码预览版以源码构建为主：

```sh
git clone https://github.com/LujiaChen/PeekKit.git
cd PeekKit
./build.sh
```

将 `.build/PeekKit.app` 放进“应用程序”，打开一次，并启用 Quick Look 中的 **PeekKit Folder** 和 **PeekKit Markdown**。在 Finder 选中文件夹或 Markdown，按空格；点击 **Analysis** 展开统计。

默认构建使用临时签名。本次不提供经过 Developer ID 签名和公证的安装包，其他 Mac 上的安装和扩展启用仍需验证。详见[安装及排障说明](docs/INSTALL.md)。

## 统计范围与限制

统计当前目录及后代，包括应用包内部。隐藏文件跟随开关，名称筛选不改变总量。Size 是文件逻辑长度；On disk 是分配给文件的磁盘块，不等于 APFS 独占或删除后可回收空间。

不跟随符号链接；硬链接只计一次；跳过其他卷、云端未下载或无法确认驻留状态的项目。只为统计读取元数据，不请求云文件下载。权限不足、主动停止或达到上限时，明确显示部分结果及遗漏说明。

上限为 100 万条目、128 层、60 秒；浏览列表保留 20,000 项显示上限，分析统计独立进行。详见[统计定义](docs/ANALYSIS.md)。

## 测试

1.2 已通过 102 项检查：28 项分析、26 项浏览/预览、20 项内容/导出安全、28 项渲染/生命周期测试。手动检查覆盖已安装扩展的系统 Quick Look 宿主，以及独立窗口的浅色和深色界面。本次 Finder 空格键操作因自动化窗口连接问题未能完整验证。25,000 个文件的单次本地扫描测量为修改前 1.095 秒、修改后 0.949 秒，不代表统计意义上的性能提升。[测量及验证边界](docs/UPGRADE-1.2.md)

真实云端占位文件、网络及跨卷挂载、Intel 和其他 macOS 版本尚未完整实测。GitHub Actions 已在 macOS arm64 上构建主程序和两个扩展，并通过全部四组测试。[CI 结果](https://github.com/LujiaChen/PeekKit/actions/workflows/ci.yml)。[测试说明](docs/TESTING.md)

## 许可证与致谢

PeekKit 原创源码使用 [MIT](LICENSE)。Marked、DOMPurify 保留原有许可和署名。文件夹分析以 [PeekX](https://github.com/altic-dev/PeekX) 为功能参考，独立实现；详见[第三方说明](THIRD_PARTY_NOTICES.md)。
