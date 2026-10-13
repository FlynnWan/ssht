## SSHT v0.0.1

原生 macOS SSH 端口转发工具，支持 Apple Silicon（ARM64），要求 macOS 14 或更新版本。

- 从 SSH config 选择主机，支持本地、远程和 SOCKS 转发。
- 规则分组、折叠和一键启停，支持全部开启／停止。
- 关闭窗口后继续在菜单栏后台运行。
- 自动识别已有外部 SSH 转发和端口占用，避免重复启动。
- 支持自动启动、日志和浅色／深色外观。

下载 `SSHT-v0.0.1-macos-arm64.zip`，解压后将 `SSHT.app` 放入「应用程序」。安装包由本仓库的 GitHub Actions 构建、测试和上传，可使用 `SHA256SUMS.txt` 校验。

应用使用临时签名，尚未进行 Apple Developer ID 签名及公证；首次打开可能需要在 macOS「系统设置 → 隐私与安全性」中允许打开。
