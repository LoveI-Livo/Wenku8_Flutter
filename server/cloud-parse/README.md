# 云端解析接口

把网盘书的拉取和解析放到自己的 PHP 虚拟主机，App 只接收解析结果。仓库里的
说明只使用占位域名和占位密钥；部署时请换成自己的实际地址和随机密钥，不要把
自己的接口地址、密钥或 `config.php` 提交到仓库。

## 环境要求

- PHP 8.0 或更高版本。
- 启用 `curl`、`zip`、`dom`、`mbstring`、`openssl` 扩展。
- 网站目录可写（用于 PHP 临时文件；接口不会把原书永久保存到主机）。
- 建议使用 HTTPS。App 允许用户填写自己的 HTTP 接口，未在安装包里硬编码任何
  私人域名；仍建议给自己的主机配置 HTTPS，避免直链和凭证走明文。
- 共享虚拟主机能同时处理多少请求由主机套餐的 PHP-FPM 进程数决定，PHP
  脚本本身无法超过这个上限。需要几十路以上并发时，请换 VPS 或更高并发套餐。

## 部署步骤

1. 在网站根目录下新建目录，例如 `cloud-parse`。
2. 上传两个文件：
   - `cloud-parse/index.php`
   - `cloud-parse/config.php.example`
3. 复制 `config.php.example` 为同目录的 `config.php`，只修改 `config.php`，
   给 `token` 写一段至少 32 位的随机字符串。可以用下面的命令生成：
   ```bash
   php -r "echo bin2hex(random_bytes(32)), PHP_EOL;"
   ```
4. 确认文件权限允许 Web 服务器读取 PHP 文件；不要给 `config.php` 可执行权限，
   也不要让目录列表暴露它。
5. 访问接口地址时必须是 `POST`。用浏览器直接打开通常返回 405，这是正常的。

接口地址格式：

```text
https://你的域名/cloud-parse/index.php
```

App 里进入「网盘在线阅读 → 云端主机解析」，填写这个地址和同一个 token。

## Nginx 示例

如果站点使用 Nginx + PHP-FPM，只需要保证 `.php` 交给 PHP 处理，例如：

```nginx
location ~ \.php$ {
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_pass unix:/run/php/php8.1-fpm.sock;
}
```

Apache 主机一般不需要额外改写；确认 `mod_php` 或 PHP-FPM 已启用即可。

## 自测

把下面的域名和 token 换成自己的值。先测非 POST 请求：

```bash
curl -i https://你的域名/cloud-parse/index.php
```

应返回 `405` 和类似 `{"ok":false,"error":"只接受 POST 请求"}` 的 JSON。

先在 App 里打开「云端主机解析」，填好地址和密钥后点“测试接口”。测试请求不会
拉取任何文件，只验证地址、token、PHP 和 JSON 返回；成功会提示“接口连接正常”。

如果需要用命令行验证同一个测试请求：

```bash
curl -sS -X POST https://你的域名/cloud-parse/index.php \
  -H 'Content-Type: application/json' \
  -d '{"token":"你的 config.php 里的 token","test":true}'
```

应返回 `{"ok":true,"test":true,...}`。

再用一个公开的 TXT/EPUB 直链测试：

```bash
curl -sS -X POST https://你的域名/cloud-parse/index.php \
  -H 'Content-Type: application/json' \
  -d '{
    "token": "你的 config.php 里的 token",
    "url": "https://example.com/book.epub",
    "name": "book.epub",
    "metaOnly": true
  }'
```

返回 `"ok": true`、`"format": "epub"` 和书名/作者/简介即表示部署成功。

## 协议

App 向接口发送 `POST application/json`：

```json
{
  "token": "与 config.php 一致",
  "url": "网盘临时直链",
  "name": "文件名.epub",
  "cookie": "本次阅读需要的 Cookie",
  "authorization": "Basic ...",
  "metaOnly": false
}
```

服务器拉取直链并在服务器解析，返回：

```json
{
  "ok": true,
  "format": "epub",
  "title": "书名",
  "author": "作者",
  "summary": "简介",
  "cover": "base64 图片",
  "chapters": [{"title": "第一章", "content": "正文"}],
  "media": [{"key": "sha1", "data": "base64 图片"}]
}
```

正文中的 `[[CLOUD_MEDIA:key]]` 会由 App 替换成正文插图缓存标记。

`metaOnly=true` 时只返回书名、作者、简介和封面，用于加入书架或搜索时识别
信息；App 的「网盘搜索」在文件名没有命中时会对小文件做一次 `metaOnly`
识别。解析失败或格式不支持时 App 仍会保留原有记录，并按自身策略回退。

## 支持格式

- EPUB：书名、作者、简介、封面、章节、正文插图。
- DOCX / ODT：书名、作者、简介、封面、章节。
- FB2：书名、作者、简介、封面、章节。
- TXT / Markdown / HTML：书名、作者、简介、章节。
- ZIP：自动寻找内部第一本书并解析。
- PDF、MOBI、PRC、AZW、AZW3：接口返回不支持，App 按自身策略处理。

## 安全

- 必须设置 token；不要公开 `config.php`，不要把真实 token 写进 README、
  Issue、日志或截图。
- 接口会按 App 请求拉取网盘直链，因此 token 泄露可能被滥用；建议使用长随机值，
  并定期轮换。
- 默认拒绝 `127.*`、`10.*`、`192.168.*` 等内网地址，防止 SSRF；只应在本地
  调试时临时打开 `allow_private`。
- 单文件默认上限 64 MiB；超过上限会返回错误。
- 建议在反向代理层再加请求体大小、超时和频率限制。

## 常见问题

- **405 只接受 POST**：这是正常保护；用 `curl -X POST` 测试。
- **返回 401/密钥错误**：`config.php` 里的 token 和 App 里填写的不一致。
- **curl 超时**：主机出口到目标网盘被限制，换一个可访问的直链测试。
- **HTTP 200 但内容为空**：`config.php` 没有加载，检查 PHP 错误日志和文件路径。
- **并发不够**：先测 5 路并发；如果主机排队或 502，升级 PHP-FPM 进程数或换 VPS。
