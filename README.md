# Auto Wi-Fi Connect

基于 Playwright 的校园/企业网关自动登录脚本，支持掉线探测、自动重连、开机自启与周期性保活。适用于 macOS。

## 功能
- 联网探测：多探针判定，已在线时静默退出。
- 自动登录：填写账号/密码并点击登录，成功后再次探测外网。
- 保活巡检：默认每 5 分钟一次（launchd），掉线自动重登。
- 自启：launchd 支持开机即运行。
- 排障：日志 + 异常截图/HTML。

## 目录
```
Auto_Wifi_Connect/
├─ portal-login.sh          # bash 入口，探测/调度 Playwright 登录
├─ portal-login.mjs         # Playwright 脚本（登录逻辑）
├─ package.json / lock      # 依赖声明（playwright）
├─ .env.example             # 环境变量模板（账号、密码、门户地址）
├─ deploy.sh                # 一键部署（写 plist+启动 launchd）
├─ undeploy.sh              # 一键卸载（停止并移除 plist）
├─ .gitignore               # Git 忽略配置
├─ LICENSE                  # ISC 许可证
├─ ms-playwright/ (可选)    # Playwright 浏览器缓存，拷贝可省下载
├─ node_modules/ (可选)     # 依赖目录，拷贝可省 npm install
└─ README.md
```

## 环境要求
- macOS（Apple Silicon/Intel）
- Node.js ≥ 18
- 可访问 npm（如未拷贝 `ms-playwright/`/`node_modules/`）

## 安装 & 准备
1) 将本目录放到目标机，推荐路径：`~/Library/AutoWiFi/Auto_Wifi_Connect`。  
2) 确保脚本可执行（首次执行前运行一次）：  
   ```bash
   cd ~/Library/AutoWiFi/Auto_Wifi_Connect
   chmod +x portal-login.sh deploy.sh undeploy.sh
   ```
3) 安装 Node.js（如缺失）：`HOMEBREW_NO_AUTO_UPDATE=1 brew install node`（或用 nvm 安装，需 ≥18）。  
4) 安装依赖（如未拷贝 `node_modules/`）：  
   ```bash
   cd ~/Library/AutoWiFi/Auto_Wifi_Connect
   npm install
   ```
5) 浏览器内核：若未拷贝 `ms-playwright/`，`deploy.sh` 会自动运行 `npx playwright install chromium`（需联网，安装目录固定为 `./ms-playwright`）。

## 配置方式（推荐用 .env）
1) 复制模板并填写：
   ```bash
   cd ~/Library/AutoWiFi/Auto_Wifi_Connect
   cp .env.example .env
   # 编辑 .env 写入你的账号/密码/门户地址
   ```
   `.env` 字段说明：
   - `PORTAL_ACCOUNT`：账号（建议用引号包裹）  
   - `PORTAL_PASSWORD`：密码（建议用引号；含 `$` 时务必用单引号或转义）  
   - `PORTAL_LOGIN_CANDIDATES`：门户地址，逗号分隔多个 URL（建议用引号包裹；不同公司网关请填真实地址）。  
   - `AUTO_WIFI_PROJ`：可选，自定义工作目录（默认 `~/Library/AutoWiFi`）。  
   - `AUTO_WIFI_ENV`：可选，自定义 .env 路径。
   **如密码包含 `$` 等特殊字符，请用单引号包裹：** `PORTAL_PASSWORD='p@ss$word'`

2) 也可直接导出环境变量（无需 .env）：  
   ```bash
   export PORTAL_ACCOUNT=xxx
   export PORTAL_PASSWORD=yyy
   export PORTAL_LOGIN_CANDIDATES="https://portal.xx.com/,https://portal.xx.com/login"
   ```

3) 或直接修改 `portal-login.mjs` 内的占位值（仓库默认已清空）。

## 运行
- 手动测试：  
  ```bash
  cd ~/Library/AutoWiFi/Auto_Wifi_Connect
  ./portal-login.sh
  tail -n 50 portal-login.log
  ```
- `DEBUG=1 ./portal-login.sh` 可打开 bash -x 追踪。

## 一键部署 / 解除（macOS）
- 部署（安装依赖、校验 .env、写入并启动 launchd，默认 120 秒巡检）：  
  ```bash
  cd ~/Library/AutoWiFi/Auto_Wifi_Connect
  ./deploy.sh
  ```
  如果首次生成 `.env` 但未填写账号/密码，脚本会提示并退出。

- 解除（停止并移除 plist）：  
  ```bash
  cd ~/Library/AutoWiFi/Auto_Wifi_Connect
  ./undeploy.sh
  ```

### 手工 launchd（可选方案）
如需手工配置，可参照下列 plist（与 deploy.sh 生成内容一致）：
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key><string>com.autowifi.portal-login</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/zsh</string>
      <string>-lc</string>
      <string>cd ~/Library/AutoWiFi/Auto_Wifi_Connect && ./portal-login.sh</string>
    </array>
    <key>StartInterval</key><integer>120</integer>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>/Users/$(whoami)/Library/AutoWiFi/Auto_Wifi_Connect/launchd.out.log</string>
    <key>StandardErrorPath</key><string>/Users/$(whoami)/Library/AutoWiFi/Auto_Wifi_Connect/launchd.err.log</string>
  </dict>
</plist>
```
加载/启动：
```bash
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.autowifi.portal-login.plist
launchctl enable gui/$UID/com.autowifi.portal-login
launchctl kickstart -k gui/$UID/com.autowifi.portal-login
```
停止/卸载：
```bash
launchctl bootout gui/$UID ~/Library/LaunchAgents/com.autowifi.portal-login.plist
```

## 通用性说明
- 门户 URL：通过 `PORTAL_LOGIN_CANDIDATES` 配置，适配不同公司网关。
- 表单匹配：脚本尝试常见字段（`textbox`、`input[name=username]`、`input[type=text]`、`input[type=password]`、`input[name=pwd]` 等）；若仍不兼容，可在 `portal-login.mjs` 中微调选择器。

## 日志与排障
- 日志：`portal-login.log`，实时查看 `tail -f portal-login.log`。
- 异常调试：自动生成 `debug-*.png` / `debug-*.html`。
- bash 追踪：`DEBUG=1 ./portal-login.sh`。
- 如出现 “Executable doesn't exist ... npx playwright install”：
  ```bash
  cd ~/Library/AutoWiFi/Auto_Wifi_Connect
  PLAYWRIGHT_BROWSERS_PATH=$PWD/ms-playwright npx playwright install chromium
  ```
  确保目录 `ms-playwright` 存在且包含下载的 chromium。
- 若提示 “missing account or password”：确保 `.env` 放在项目目录 `Auto_Wifi_Connect/.env`，或设置 `AUTO_WIFI_PROJ` 指向该目录。

## 安全提示
- 建议使用 `.env` / 环境变量存放账号密码，不要将真实凭据提交到公开仓库。
- `.gitignore` 已忽略 `.env`、日志与调试文件。

## 许可
ISC License（见 `LICENSE`）。

