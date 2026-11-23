<?php
declare(strict_types=1);
// 可道云封面代理：文件本体在可道云「个人空间/云端封面」，本机不保存。
$configFile = __DIR__ . '/config.php';
$config = is_file($configFile) ? require $configFile : [];
$name = (string)($_GET['f'] ?? '');
if (!preg_match('/^[a-f0-9]{32}\.(?:jpg|png|gif|webp|bmp)$/', $name)) {
    http_response_code(404);
    exit;
}
$dav = rtrim((string)($config['kodbox_dav'] ?? ''), '/') . '/';
$dir = trim((string)($config['kodbox_cover_dir'] ?? '个人空间/云端封面'), '/');
$user = (string)($config['kodbox_user'] ?? '');
$password = (string)($config['kodbox_password'] ?? '');
$parts = $dir === '' ? [] : explode('/', $dir);
$url = $dav;
foreach ($parts as $part) {
    $url .= rawurlencode($part) . '/';
}
$url .= rawurlencode($name);
$headers = ['Accept: image/*'];
if ($user !== '' || $password !== '') {
    $headers[] = 'Authorization: Basic ' . base64_encode($user . ':' . $password);
}
$body = false;
$status = 0;
$type = 'application/octet-stream';
if (function_exists('curl_init')) {
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT => 25,
        CURLOPT_FOLLOWLOCATION => true,
    ]);
    $body = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $type = (string)curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
    curl_close($ch);
} else {
    $context = stream_context_create([
        'http' => [
            'method' => 'GET',
            'header' => implode("\r\n", $headers),
            'timeout' => 25,
            'ignore_errors' => true,
        ],
    ]);
    $body = @file_get_contents($url, false, $context);
    if (isset($http_response_header[0]) && preg_match('/\s(\d{3})\s/', $http_response_header[0], $m)) {
        $status = (int)$m[1];
    }
}
if ($body === false || $status < 200 || $status >= 300) {
    // 兼容旧版仍保存在主机 covers 目录的封面。
    $legacy = __DIR__ . '/covers/' . $name;
    if (is_file($legacy)) {
        $body = file_get_contents($legacy);
        $type = mime_content_type($legacy) ?: 'image/jpeg';
        $status = 200;
    }
}
if ($body === false || $body === '' || $status < 200 || $status >= 300) {
    http_response_code(404);
    exit;
}
if (!preg_match('#^image/#i', $type)) {
    $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
    $type = $ext === 'png' ? 'image/png' : ($ext === 'gif' ? 'image/gif' : ($ext === 'webp' ? 'image/webp' : 'image/jpeg'));
}
header('Content-Type: ' . $type);
header('Content-Length: ' . strlen($body));
header('Cache-Control: public, max-age=2592000');
header('X-Content-Type-Options: nosniff');
echo $body;
