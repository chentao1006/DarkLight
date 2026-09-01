# 暗光

**以网页外观控制为核心，实验性拓展为没有自动适配深浅色主题的 Mac 应用提供主题。**

[English](./README.md) | **简体中文**

---

暗光是一个轻量浏览器扩展，让你决定每个网页呈现的外观。可为网站选择跟随系统、维持网站设计、强制深色或强制浅色。macOS 上的应用主题控制作为实验性功能，也能为没有自动适配深浅色主题的选定应用设置显示主题。

## 为什么选择暗光？

* **为网页而生：** 不改变网页原有内容，直接掌控每个网站的显示外观。
* **按你的习惯切换：** 为全局或单个网站选择跟随系统、维持网站设计、强制深色或强制浅色。
* **每个网站独立规则：** 每个网站都能有自己的规则，并可选择是否匹配子域名。
* **深色和浅色同样重要：** 夜间让亮色网页更舒适，白天也能让深色网页恢复清晰的浅色外观。
* **实验性 macOS 拓展：** 应用主题控制可为没有自动适配深浅色主题的选定 Mac 应用设置显示主题。
* **本地且隐私友好：** 规则和显示处理都留在你的设备上；暗光不收集浏览数据，也不保存屏幕内容。

## 核心功能

* **网页外观规则：** 为全局或单个网站设置跟随系统、维持网站设计、强制深色或强制浅色。
* **网页快速控制：** 在弹出窗口中立即修改当前网站，或在规则页统一管理全部网站规则。
* **应用主题控制（macOS，实验性功能）：** 为没有自动适配深浅色主题的选定 Mac 应用设置显示主题：跟随系统、固定深色、固定浅色，或按时间自动切换。
* **原生 Safari App：** `safari/` 内的 macOS 宿主 App 提供 Safari Web Extension 设置和实验性的应用主题控制。
* **从设计上保护隐私：** 工具栏角标显示当前网页模式；设置和显示处理始终留在本地设备。

## 安装方法

[![Download on the App Store](assets/app_store.png)](https://apps.apple.com/us/app/dark-light-for-webpages/id6781749180)
[![Available in the Chrome Web Store](assets/chrome-web-store-badge.png)](https://chromewebstore.google.com/detail/dark-light/jmckaadolajjpcmlciacmdenlfkolnhf)
[![Get the Firefox Add-on](assets/firefox.png)](https://addons.mozilla.org/zh-CN/firefox/addon/dark-light-web-mode/)

## 截图预览

### Safari（iOS / iPadOS）

| 弹出面板 | 规则管理页 | App 设置引导 |
|---------|-----------|-------------|
| ![Safari iOS 弹出面板](assets/000001.jpg) | ![Safari iOS 规则管理](assets/000004.jpg) | ![Safari iPhone App](assets/000003.jpg) |

| iPad App |
|----------|
| ![Safari iPad App](assets/000002.jpg) |

### Chrome

| 弹出面板（小视口） | 弹出面板（大视口） | 选项页 |
|-------------------|-------------------|-------|
| ![Chrome 弹出面板小](assets/000007.jpg) | ![Chrome 弹出面板大](assets/000008.jpg) | ![Chrome 选项页](assets/000010.jpg) |

| 选项页（完整桌面视图） |
|----------------------|
| ![Chrome 选项页完整](assets/000009.jpg) |

### 实际效果

| 强制深色 | 强制浅色 |
|---------|----------|
| ![强制深色效果 – Safari](assets/000005.jpg) | ![强制浅色效果 – Safari](assets/000006.jpg) |


### Chrome 扩展程序（开发者模式）

1. 克隆或下载本仓库到本地。
2. 打开 Chrome，进入 `chrome://extensions/`。
3. 开启 **开发者模式**。
4. 点击 **加载已解压的扩展程序**。
5. 选择本项目中的 `extension` 目录。

### Safari App（Xcode）

1. 用 Xcode 打开 `safari/Dark Light/Dark Light.xcodeproj`。
2. macOS 选择 `Dark Light` scheme 并在 `My Mac` 上运行；iPhone 和 iPad（iOS 15+）选择 `Dark Light iOS` scheme。
3. 宿主 App 提供 Safari 扩展设置，并在 macOS 上为没有自动适配深浅色主题的应用提供应用主题控制。
4. 在 Safari 中启用 `Dark Light` 后可使用网页控制；也可以打开**应用主题控制**来配置没有自动适配深浅色主题的选定 Mac 应用。

### 应用主题控制（macOS，实验性功能）

内置的 macOS App 可以为没有自动适配深浅色主题的选定应用设置显示主题。在暗光中打开**应用主题控制**，授予 macOS 屏幕录制权限后，添加应用并选择**跟随系统**、**强制深色**、**强制浅色**或按时间切换。规则会自动应用到该应用的所有可见窗口。

此功能需要 macOS 12.3 或更高版本。暗光仅使用该权限来转换所选应用的屏幕显示效果，不会保存或上传屏幕内容。

用户脚本版本不再维护。

## 技术细节

暗光使用 `chrome.storage.sync` 保存网页设置 `darkLightSettings`；macOS 宿主 App 会在本地 `UserDefaults` 中保存选定应用的规则和时间表。

强制深色由内置的 `darkreader` 包提供能力，代码位于 `extension/vendor/darkreader/`，许可证为 MIT。

当前配置结构：

```ts
type ConfiguredMode = 'followSystem' | 'preserveSite' | 'forceDark' | 'forceLight';

type SiteRule = {
  id: string;
  pattern: string;
  mode: ConfiguredMode;
  enabled: boolean;
  matchSubdomains: boolean;
};

type Settings = {
  version: 2;
  defaultMode: ConfiguredMode;
  siteRules: SiteRule[];
};
```

内容脚本会先解析当前域名命中的规则，再把 `followSystem` 转换成当前系统实际外观；`preserveSite` 会清除本扩展注入的外观改动并维持网站自己的设计；其他模式会运行强制深色或强制浅色策略。

使用权限：

- `storage`: 保存默认模式和网站规则。
- `activeTab`: 让弹出窗口读取当前标签页。
- `<all_urls>` 内容脚本: 在匹配页面应用外观规则。

## 隐私声明

暗光不收集或传输个人数据、浏览历史、按键记录、网页内容或屏幕内容。它会向 Aptabase 发送匿名的启动与宿主 App 每日打卡事件，内容仅限语言地区、平台、操作系统、App 版本和调试状态。
