<?php
declare(strict_types=1);
$configFile = __DIR__ . '/config.php';
$config = is_file($configFile) ? require $configFile : [];
$token = (string)($config['token'] ?? '');
if ($token === '' || !hash_equals($token, (string)($_GET['token'] ?? ''))) {
    http_response_code(403);
    header('Content-Type: text/plain; charset=utf-8');
    echo '封面管理需要有效的接口密钥';
    exit;
}
$dav = rtrim((string)($config['kodbox_dav'] ?? ''), '/') . '/';
$dir = trim((string)($config['kodbox_cover_dir'] ?? '个人空间/云端封面'), '/');
$dirUrl = $dav;
foreach ($dir === '' ? [] : explode('/', $dir) as $part) {
    $dirUrl .= rawurlencode($part) . '/';
}
$items = [];
$error = '';
if ($dav === '/') {
    $error = 'config.php 尚未填写可道云 WebDAV 地址';
} else {
    $headers = [
        'Accept: application/xml,text/xml,*/*',
        'Depth: 1',
        'Authorization: Basic ' . base64_encode(
            (string)($config['kodbox_user'] ?? '') . ':' . (string)($config['kodbox_password'] ?? '')
        ),
    ];
    $xml = '';
    $status = 0;
    if (function_exists('curl_init')) {
        $ch = curl_init($dirUrl);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CUSTOMREQUEST => 'PROPFIND',
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_TIMEOUT => 30,
        ]);
        $xml = (string)curl_exec($ch);
        $status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);
    } else {
        $context = stream_context_create([
            'http' => [
                'method' => 'PROPFIND',
                'header' => implode("\r\n", $headers),
                'timeout' => 30,
                'ignore_errors' => true,
            ],
        ]);
        $xml = (string)@file_get_contents($dirUrl, false, $context);
        if (isset($http_response_header[0]) && preg_match('/\s(\d{3})\s/', $http_response_header[0], $m)) {
            $status = (int)$m[1];
        }
    }
    if ($status < 200 || $status >= 300 || $xml === '') {
        $error = '暂时读取不到可道云封面目录，HTTP ' . $status;
    } else {
        preg_match_all('#<D:response>(.*?)</D:response>#si', $xml, $blocks);
        foreach ($blocks[1] ?? [] as $block) {
            if (!preg_match('#<D:href>(.*?)</D:href>#i', $block, $hrefMatch)) continue;
            $href = html_entity_decode(rawurldecode($hrefMatch[1]), ENT_QUOTES, 'UTF-8');
            $name = basename($href);
            if (!preg_match('/^[a-f0-9]{32}\.(?:jpg|png|gif|webp|bmp)$/', $name)) continue;
            $size = 0;
            if (preg_match('#<D:getcontentlength>(\d+)</D:getcontentlength>#i', $block, $sizeMatch)) {
                $size = (int)$sizeMatch[1];
            }
            $items[$name] = $size;
        }
    }
}
$count = count($items);
$total = array_sum($items);
function h(string $value): string { return htmlspecialchars($value, ENT_QUOTES, 'UTF-8'); }
function bytesText(int $bytes): string {
    if ($bytes < 1024) return $bytes . ' B';
    if ($bytes < 1048576) return round($bytes / 1024, 1) . ' KB';
    return round($bytes / 1048576, 2) . ' MB';
}
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');
?>
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#101418">
<title>云端封面 · 可道云</title>
<style>
:root{color-scheme:dark;--bg:#101418;--card:#1a2027;--line:#2b343d;--text:#eef3f7;--muted:#9aa8b5;--accent:#59c3a3}
*{box-sizing:border-box}body{margin:0;background:radial-gradient(1200px 600px at 10% -10%,#1d3a35 0,transparent 60%),var(--bg);color:var(--text);font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif}
.wrap{max-width:1100px;margin:0 auto;padding:34px 18px 60px}
.hero{display:flex;gap:18px;align-items:flex-end;justify-content:space-between;flex-wrap:wrap;margin-bottom:24px}
h1{font-size:26px;margin:0 0 6px;letter-spacing:.02em}.sub{color:var(--muted);margin:0}
.badge{display:inline-flex;gap:8px;align-items:center;padding:8px 12px;border:1px solid var(--line);border-radius:999px;background:#151b21;color:var(--accent);font-size:13px}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin:22px 0}
.stat{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px 18px}
.stat b{display:block;font-size:22px;margin-top:4px}.stat span{color:var(--muted);font-size:13px}
.note{background:#141c22;border:1px solid var(--line);border-left:3px solid var(--accent);border-radius:12px;padding:14px 16px;color:var(--muted);margin:18px 0}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(132px,1fr));gap:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;overflow:hidden}
.card img{display:block;width:100%;aspect-ratio:3/4;object-fit:cover;background:#0d1116}
.meta{padding:9px 11px;font-size:12px;color:var(--muted);display:flex;justify-content:space-between;gap:6px}
.empty{padding:48px 16px;text-align:center;color:var(--muted);border:1px dashed var(--line);border-radius:18px}
.err{color:#ff9a9a;background:#2a1717;border-color:#452525;padding:14px 16px;border-radius:12px}
footer{margin-top:30px;color:#6f7d89;font-size:12px}
</style>
</head>
<body>
<div class="wrap">
  <div class="hero">
    <div><h1>云端封面</h1><p class="sub">App 上传的网盘封面直接保存在可道云，本机不落一份图片。</p></div>
    <div class="badge">可道云 WebDAV · 已接通</div>
  </div>
  <?php if ($error !== ''): ?><div class="err"><?= h($error) ?></div><?php endif; ?>
  <div class="stats">
    <div class="stat"><span>封面数量</span><b><?= $count ?></b></div>
    <div class="stat"><span>占用空间</span><b><?= h(bytesText($total)) ?></b></div>
    <div class="stat"><span>保存位置</span><b style="font-size:15px;word-break:break-all"><?= h($dir) ?></b></div>
  </div>
  <div class="note">这些文件同时出现在可道云「个人空间 / 云端封面」，你可以直接在可道云里重命名、移动或删除；App 只保存图片地址，删掉文件后对应封面会失效。</div>
  <?php if ($count === 0): ?>
    <div class="empty">还没有云端封面。到 App 的网盘书籍详情里更换封面，图片会自动写到这里。</div>
  <?php else: ?>
    <div class="grid">
      <?php foreach ($items as $name => $size): ?>
        <div class="card"><img loading="lazy" src="cover.php?f=<?= rawurlencode($name) ?>" alt=""><div class="meta"><span><?= h(substr($name, 0, 8)) ?></span><span><?= h(bytesText($size)) ?></span></div></div>
      <?php endforeach; ?>
    </div>
  <?php endif; ?>
  <footer>云端解析接口 · <?= h((string)($config['kodbox_dav'] ?? '')) ?></footer>
</div>
</body>
</html>
