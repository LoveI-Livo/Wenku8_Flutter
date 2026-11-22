# 云端解析接口

把网盘书的拉取和解析放到自己的 PHP 虚拟主机，App 只接收解析结果。

## 部署

1. 把 `index.php` 上传到网站可访问目录，例如：
   ```
   /www/wwwroot/你的站点/cloud-parse/index.php
   ```
2. 复制 `config.php.example` 为同目录的 `config.php`，把 `token` 改成一段长随机字符串。
3. 确认主机启用 `curl`、`zip`、`dom`、`mbstring` 扩展。
4. 接口地址示例（以实际域名为准）：
   ```
   https://你的域名/cloud-parse/index.php
   ```
5. 在 App「网盘在线阅读 → 云端主机解析」填接口地址和同一个 token。

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

## 支持格式

- EPUB：书名、作者、简介、封面、章节、正文插图。
- DOCX / ODT：书名、作者、简介、封面、章节。
- FB2：书名、作者、简介、封面、章节。
- TXT / Markdown / HTML：书名、作者、简介、章节。
- ZIP：自动寻找内部第一本书并解析。
- PDF、MOBI、PRC、AZW、AZW3：接口返回不支持，App 自动回退本机解析。

`metaOnly=true` 时只返回书名、作者、简介和封面，用于加入书架时识别信息。

## 安全

- 必须设置 token；不要公开 `config.php`。
- 接口会按 App 请求拉取网盘直链，因此 token 泄露可能被滥用；建议使用长随机值。
- 默认拒绝 `127.*`、`10.*`、`192.168.*` 等内网地址，防止 SSRF。
- 单文件默认上限 64 MiB；超过上限会返回错误，App 回退本机解析。
- iOS 对明文 HTTP 有 ATS 限制，建议给接口配 HTTPS；Android 已允许明文 HTTP。
