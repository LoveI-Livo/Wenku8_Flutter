<?php
declare(strict_types=1);

/**
 * 云端解析接口 · 密钥入口
 *
 * 通过 ?token=... 打开。页面展示 App 需要填写的接口地址和密钥，
 * 带复制按钮与接口连通性测试，不写入任何日志。
 */
$configFile = __DIR__ . '/config.php';
$config = is_file($configFile) ? require $configFile : [];
$token = (string)($config['token'] ?? '');
$given = (string)($_GET['token'] ?? '');
if ($token === '' || !hash_equals($token, $given)) {
    http_response_code(403);
    header('Content-Type: text/plain; charset=utf-8');
    echo '需要有效的接口密钥才能打开此页';
    exit;
}

$https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
    || ((int)($_SERVER['SERVER_PORT'] ?? 0) === 443)
    || strtolower((string)($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https';
$origin = ($https ? 'https' : 'http') . '://' . ($_SERVER['HTTP_HOST'] ?? 'localhost');
$dir = rtrim(str_replace('\\', '/', dirname((string)($_SERVER['SCRIPT_NAME'] ?? '/cloud-parse/key.php'))), '/');
$endpoint = $origin . $dir . '/index.php';
$manageUrl = $origin . $dir . '/manage.php?token=' . rawurlencode($token);
$version = (string)($config['public_version'] ?? '0.8.2');

function h(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES, 'UTF-8');
}
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');
header('X-Robots-Tag: noindex, nofollow, noarchive');
header('Referrer-Policy: no-referrer');
?>
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#101418">
<title>云端解析接口 · 密钥</title>
<style>
:root{color-scheme:dark;--bg:#101418;--card:#1a2027;--line:#2b343d;--text:#eef3f7;--muted:#9aa8b5;--accent:#59c3a3;--warn:#ffbf69}
*{box-sizing:border-box}body{margin:0;background:radial-gradient(1200px 600px at 10% -10%,#1d3a35 0,transparent 60%),var(--bg);color:var(--text);font:15px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif}
.wrap{max-width:920px;margin:0 auto;padding:34px 18px 64px}
.hero{display:flex;gap:16px;align-items:flex-end;justify-content:space-between;flex-wrap:wrap;margin-bottom:22px}
h1{font-size:26px;margin:0 0 6px;letter-spacing:.02em}.sub{color:var(--muted);margin:0}
.badge{display:inline-flex;gap:8px;align-items:center;padding:8px 12px;border:1px solid var(--line);border-radius:999px;background:#151b21;color:var(--accent);font-size:13px}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:18px;margin:14px 0}
.label{color:var(--muted);font-size:12px;letter-spacing:.08em;text-transform:uppercase;margin-bottom:8px}
.row{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
.code{flex:1;min-width:220px;background:#0d1116;border:1px solid var(--line);border-radius:10px;padding:11px 13px;font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;color:#d9f5eb;word-break:break-all}
.btn{border:1px solid #356256;background:#173b34;color:#c8f7e8;border-radius:10px;padding:10px 14px;font:inherit;cursor:pointer}
.btn:hover{background:#1c4a40}.btn.ghost{background:#151b21;border-color:var(--line);color:var(--text)}
.note{background:#141c22;border:1px solid var(--line);border-left:3px solid var(--accent);border-radius:12px;padding:13px 15px;color:var(--muted);margin:16px 0}
.warn{border-left-color:var(--warn);color:#ffd9a3}
.steps{margin:0;padding-left:20px;color:var(--muted)}.steps li{margin:7px 0}.steps b{color:var(--text)}
.links{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}.links a{color:var(--accent);text-decoration:none;border-bottom:1px dashed #3a665b}
#testResult{white-space:pre-wrap;font:12px/1.5 ui-monospace,monospace;color:var(--muted);margin-top:10px}
footer{margin-top:26px;color:#6f7d89;font-size:12px}
</style>
</head>
<body>
<div class="wrap">
  <div class="hero">
    <div><h1>云端解析接口</h1><p class="sub">把这个地址和密钥填进 App，网盘书解析、搜索和封面都会走这里。</p></div>
    <div class="badge">API v1 · <?= h($version) ?></div>
  </div>

  <div class="card">
    <div class="label">接口地址</div>
    <div class="row">
      <div class="code" id="endpoint"><?= h($endpoint) ?></div>
      <button class="btn" data-copy="#endpoint">复制地址</button>
    </div>
  </div>

  <div class="card">
    <div class="label">接口密钥</div>
    <div class="row">
      <div class="code" id="key"><?= h($token) ?></div>
      <button class="btn" data-copy="#key">复制密钥</button>
    </div>
  </div>

  <div class="card">
    <div class="row">
      <button class="btn" id="testBtn">测试接口连通</button>
      <a class="btn ghost" href="<?= h($manageUrl) ?>">打开封面管理</a>
    </div>
    <div id="testResult"></div>
  </div>

  <div class="note">
    <b>App 里填这里：</b>「网盘在线阅读 → 云端主机解析」<br>
    接口地址填上面的地址，密钥填上面那一串，保存后点“测试接口”。
  </div>

  <div class="note warn">
    这个页面带密钥，等于主机接口的钥匙。不要截图发群、不要贴到公开仓库；换密钥后旧链接会立即失效。页面不记录访问日志。
  </div>

  <div class="card">
    <div class="label">这组接口负责什么</div>
    <ul class="steps">
      <li><b>解析网盘书</b>：EPUB、TXT、DOCX、HTML、FB2 转成 App 可读章节。</li>
      <li><b>搜索与详情</b>：网页书源、目录、正文请求都走这里。</li>
      <li><b>封面托管</b>：图片直接写进可道云 <b>个人空间 / 云端封面</b>，App 只保存图片地址。</li>
      <li><b>密钥校验</b>：所有请求都在 JSON body 的 token 字段里校验，不走 URL 明文。</li>
    </ul>
    <div class="links">
      <a href="<?= h($manageUrl) ?>">封面管理页</a>
      <a href="<?= h($origin . '/hub.php') ?>">应用中心</a>
    </div>
  </div>

  <footer>云端解析接口 · <?= h($endpoint) ?> · 可道云封面目录已接通</footer>
</div>
<script>
document.querySelectorAll('[data-copy]').forEach(function (button) {
  button.addEventListener('click', async function () {
    var target = document.querySelector(button.dataset.copy);
    if (!target) return;
    try {
      await navigator.clipboard.writeText(target.textContent.trim());
      var old = button.textContent;
      button.textContent = '已复制';
      setTimeout(function () { button.textContent = old; }, 1400);
    } catch (e) {
      var range = document.createRange();
      range.selectNodeContents(target);
      var selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      button.textContent = '已选中，请手动复制';
    }
  });
});
document.getElementById('testBtn').addEventListener('click', async function () {
  var out = document.getElementById('testResult');
  out.textContent = '正在请求…';
  try {
    var response = await fetch(<?= json_encode($endpoint, JSON_UNESCAPED_SLASHES) ?>, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: <?= json_encode($token) ?>, test: true })
    });
    var data = await response.json();
    out.textContent = response.status + ' · ' + JSON.stringify(data, null, 2);
  } catch (e) {
    out.textContent = '请求失败：' + (e && e.message ? e.message : e);
  }
});
</script>
</body>
</html>
