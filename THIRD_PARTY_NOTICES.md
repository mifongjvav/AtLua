# 第三方资源与许可证

本项目代码以 **MIT** 许可发布（见仓库根目录 `LICENSE`）。
以下第三方资源**不属于** MIT 授权，各自保留原有许可。

## 字体

| 文件 | 字体 | 版本 | 版权方 | 许可 | 许可全文 |
| --- | --- | --- | --- | --- | --- |
| `At/font/font.ttf` | Noto Sans SC Bold | 2.004 | © 2014-2021 Adobe（保留字体名 "Source"）；© Google LLC | SIL Open Font License 1.1 | [`LICENSES/OFL-1.1.txt`](LICENSES/OFL-1.1.txt)、[`LICENSES/Noto-Sans-SC.txt`](LICENSES/Noto-Sans-SC.txt) |
| `At/font/emoji.ttf` | Noto Emoji Regular | 3.005 | © 2013 Google LLC | SIL Open Font License 1.1 | [`LICENSES/OFL-1.1.txt`](LICENSES/OFL-1.1.txt)、[`LICENSES/Noto-Emoji.txt`](LICENSES/Noto-Emoji.txt) |

字体名称、版本与版权信息取自字体文件自身的 `name` 表（nameID 0/4/5/13/14），
可用 `python3 -c` 或 `fc-scan` 复核，不需要猜测。

### OFL 1.1 的关键义务（摘要，以全文为准）

- 分发字体时必须**同时携带版权声明与 OFL 许可全文**（本项目放在 `LICENSES/`，
  字体文件内部的 `name` 表也保留了许可声明）。
- 字体**不能单独售卖**，但可以随软件一起分发（本项目即随 `.love` 包分发）。
- 修改版**不得使用保留字体名**（Noto Sans SC 的保留名是 "Source"）；本项目按原样分发，
  未改名，也未声明为修改版。
- 不得用版权方/作者名义为修改版背书。

## 运行环境

- 引擎：[LÖVE](https://love2d.org/)（zlib 许可）。本项目不打包引擎，由使用者自行安装。
- Lua：LÖVE 内置 LuaJIT / Lua 5.1，本项目不额外分发 Lua 运行时。

## 没有其它第三方代码

`At/` 下的模块、`main.lua`、`test_smoke.lua`、`pack.sh` 全部为本项目原创，
没有引入第三方 Lua 库、shader 或构建工具。

## 新增第三方资源时

1. 记录文件路径、名称、版本、版权方、许可名称与许可全文链接。
2. 许可全文放到 `LICENSES/`，并在本文件中登记（`.txt` 会被打进 `.love` 包）。
3. 不要删除或改写资源内部的版权/许可元数据（字体的 `name` 表等）。
4. 若资源是 OFL 字体并被修改/子集化，必须改名以避开保留字体名，并更新版权说明。
