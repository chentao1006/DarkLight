# Dark Light

**按网站控制网页外观。**

[English](./README.md) | **简体中文**

---

Dark Light 是一个轻量浏览器扩展，用来决定每个网站最终应该显示成什么外观。你可以设置一个全局默认模式，再为单独域名配置自己的规则。

## 为什么使用 Dark Light?

* **尊重你的真实偏好：** 默认模式支持跟随系统外观、维持网站设计、强制深色、强制浅色。
* **每个网站独立规则：** 任意域名都可以单独设置模式，并可选择是否匹配子域名。
* **更好用的深色模式：** Dark Light 会优先触发网站原生深色主题，再对顽固的浅色区域做保守修正。
* **保留可靠的浅色能力：** 旧版强制浅色能力已作为 Force Light 策略保留。
* **本地且隐私友好：** 设置和样式处理都只发生在浏览器本地。

## 核心功能

* **全局默认模式：** 跟随系统外观、维持网站设计、强制深色、强制浅色。
* **当前网站快速控制：** 在弹出窗口里直接修改当前域名规则。
* **规则管理页面：** 集中新增、编辑、停用和删除全部网站规则。
* **工具栏状态反馈：** 当前标签页会显示 `DARK` 或 `LITE` 状态。
* **Manifest V3：** 目前作为 Chrome 扩展运行，代码结构已为后续 Safari Web Extension 做准备。

## 安装方法

### Chrome 扩展程序 (开发者模式)

1. 克隆或下载本仓库到本地。
2. 打开 Chrome，进入 `chrome://extensions/`。
3. 开启 **开发者模式**。
4. 点击 **加载已解压的扩展程序**。
5. 选择本项目中的 `extension` 目录。

用户脚本版本不再维护。

## 技术细节

Dark Light 使用 `chrome.storage.sync` 保存 `darkLightSettings`。

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

Dark Light 不收集、不追踪、不传输个人数据、浏览历史、按键记录或网页内容。所有处理都在你的浏览器本地完成。
