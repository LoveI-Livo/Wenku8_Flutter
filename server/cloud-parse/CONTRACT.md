# 云端解析固定契约

从 0.8.0 起，App 与主机接口共用 API v1。接口地址和 token 由部署方固定保存，
不在每次发版时更换；仓库和安装包里不写入真实地址或密钥。

## 请求字段

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `token` | 是 | 与主机 `config.php` 的 `token` 完全一致 |
| `url` | 解析时是 | 网盘临时直链，仅支持 HTTP/HTTPS |
| `name` | 解析时是 | 文件名，用于识别 EPUB/TXT/DOCX/HTML/FB2 |
| `cookie` | 否 | 本次阅读所需的 Cookie |
| `authorization` | 否 | 本次阅读所需的 Authorization |
| `metaOnly` | 否 | 只取书名、作者、简介、封面 |
| `userAgent` | 否 | 主机拉取文件时使用的 UA |
| `headers` | 否 | 仅允许 `accept`、`accept-language`、`referer`、`origin`、`user-agent` |
| `test` | 否 | `true` 时只验证地址、token、PHP 和 JSON，不拉取文件 |
| `apiVersion` | 否 | 固定 `1`；旧客户端不传也必须继续可用 |
| `bookId` | 否 | App 侧书籍 ID，主机可忽略 |

## 响应字段

成功解析必须包含：

- `ok: true`
- `api_version: "1"`
- `server_version`: 主机接口版本，例如 `0.8.0`
- `format`、`title`、`author`、`summary`
- `chapters`: `{title, content}` 数组
- 可选 `cover`、`media`

测试模式返回：

```json
{"ok":true,"test":true,"version":"0.8.0","api_version":"1"}
```

失败返回 `{"ok":false,"error":"..."}`，HTTP 状态为 4xx/5xx。

## 发布检查表

每个 App 版本发布前：

1. 确认主机 `index.php` 与仓库 `server/cloud-parse/index.php` 字节一致。
2. 用 App「云端主机解析 → 测试接口」验证 `ok/test/api_version`。
3. 用同一固定地址和 token 解析一个真实 EPUB，确认章节、封面和插图。
4. 不改 `config.php`、不换接口地址；旧版 App 仍能调用同一接口。
5. 若新增字段，只做可选字段，并在本文件记录版本。
