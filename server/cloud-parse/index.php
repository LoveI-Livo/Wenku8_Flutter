<?php
/**
 * 轻小说文库改版 · 云端解析接口
 *
 * 部署在 PHP 虚拟主机上，例如：
 *   /www/wwwroot/站点目录/cloud-parse/index.php
 * 同目录放 config.php（可从 config.php.example 复制），填写自己的 token。
 *
 * App 请求 JSON：token、url、name、cookie、authorization、metaOnly，
 * 可选 userAgent、headers；返回 api_version 供客户端做兼容性检查。
 * 接口契约从 0.8.0 起固定为 API v1，后续升级不得删除旧字段。
 */
declare(strict_types=1);

const CLOUD_PARSE_API_VERSION = '1';
const CLOUD_PARSE_VERSION = '0.8.0';

header('Content-Type: application/json; charset=utf-8');
header('X-Cloud-Parse-Api: ' . CLOUD_PARSE_API_VERSION);
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    fail('只接受 POST 请求', 405);
}

$configFile = __DIR__ . '/config.php';
$config = is_file($configFile) ? require $configFile : [];
$token = (string)($config['token'] ?? getenv('CLOUD_PARSE_TOKEN') ?: '');
$maxBytes = (int)($config['max_bytes'] ?? 64 * 1024 * 1024);
$allowPrivate = (bool)($config['allow_private'] ?? false);
if ($maxBytes < 1 || $maxBytes > 128 * 1024 * 1024) {
    $maxBytes = 64 * 1024 * 1024;
}

$raw = file_get_contents('php://input');
if ($raw === false || strlen($raw) > 1024 * 1024) {
    fail('请求内容无效');
}
$input = json_decode($raw, true);
if (!is_array($input)) {
    fail('请求 JSON 无效');
}
if ($token === '' || !hash_equals($token, (string)($input['token'] ?? ''))) {
    fail('解析密钥不正确', 401);
}

// App 的“测试接口”只验证地址、token、PHP 和 JSON 返回，不拉取任何文件。
if (($input['test'] ?? false) === true) {
    echo json_encode(
        [
            'ok' => true,
            'test' => true,
            'version' => CLOUD_PARSE_VERSION,
            'api_version' => CLOUD_PARSE_API_VERSION,
            'capabilities' => ['epub', 'text', 'docx', 'html', 'fb2', 'cover', 'media', 'cookie', 'authorization', 'userAgent', 'headers'],
            'time' => time(),
        ],
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
    );
    exit;
}

$url = trim((string)($input['url'] ?? ''));
$name = trim((string)($input['name'] ?? ''));
$cookie = trim((string)($input['cookie'] ?? ''));
$authorization = trim((string)($input['authorization'] ?? ''));
$metaOnly = (bool)($input['metaOnly'] ?? false);
$userAgent = trim((string)($input['userAgent'] ?? ''));
$extraHeaders = $input['headers'] ?? [];
if ($url === '' || $name === '') {
    fail('缺少网盘地址或文件名');
}
if (strlen($name) > 512 || preg_match('/[\r\n\x00]/', $name)) {
    fail('文件名无效');
}
if (strlen($cookie) > 16384 || strlen($authorization) > 8192 ||
    preg_match('/[\r\n\x00]/', $cookie) || preg_match('/[\r\n\x00]/', $authorization)) {
    fail('登录凭证格式无效');
}
if (strlen($userAgent) > 512 || preg_match('/[\r\n\x00]/', $userAgent)) {
    fail('下载 User-Agent 格式无效');
}
$allowedHeaders = ['accept', 'accept-language', 'referer', 'origin', 'user-agent'];
$cleanHeaders = [];
if (is_array($extraHeaders)) {
    foreach ($extraHeaders as $key => $value) {
        $key = strtolower(trim((string)$key));
        $value = trim((string)$value);
        if (!in_array($key, $allowedHeaders, true)) {
            continue;
        }
        if ($value === '' || strlen($value) > 1024 || preg_match('/[\r\n\x00]/', $value)) {
            continue;
        }
        $cleanHeaders[$key] = $value;
    }
}
$uri = parse_url($url);
if (!is_array($uri) || empty($uri['host']) ||
    !in_array(strtolower((string)($uri['scheme'] ?? '')), ['http', 'https'], true)) {
    fail('只支持 HTTP/HTTPS 文件直链');
}
$host = strtolower((string)$uri['host']);
if (!$allowPrivate && preg_match('/^(localhost|127\.|10\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|\[?::1\]?)/i', $host)) {
    fail('不允许访问本机或内网地址');
}

$bytes = fetchRemote($url, $cookie, $authorization, $userAgent, $cleanHeaders, $maxBytes);
$document = parseBook($bytes, $name, $metaOnly);
$document['ok'] = true;
$document['name'] = $name;
$document['url'] = $url;
$document['metaOnly'] = $metaOnly;
$document['api_version'] = CLOUD_PARSE_API_VERSION;
$document['server_version'] = CLOUD_PARSE_VERSION;

$json = json_encode(
    $document,
    JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE
);
if ($json === false) {
    fail('结果编码失败');
}
if (strlen($json) > 64 * 1024 * 1024) {
    fail('解析结果超过 64 MiB，请改用本机解析或较小的文件');
}
echo $json;
exit;

function fail(string $message, int $status = 400): void
{
    http_response_code($status);
    echo json_encode(
        ['ok' => false, 'error' => $message],
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
    );
    exit;
}

function fetchRemote(string $url, string $cookie, string $authorization, string $userAgent, array $extraHeaders, int $maxBytes): string
{
    $buffer = '';
    $tooLarge = false;
    $headers = ['Accept: */*'];
    if ($cookie !== '') {
        $headers[] = 'Cookie: ' . $cookie;
    }
    if ($authorization !== '') {
        $headers[] = 'Authorization: ' . $authorization;
    }
    foreach ($extraHeaders as $key => $value) {
        $headers[] = ucfirst($key) . ': ' . $value;
    }
    $ch = curl_init($url);
    if ($ch === false) {
        fail('无法初始化网络请求');
    }
    curl_setopt_array($ch, [
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_MAXREDIRS => 6,
        CURLOPT_CONNECTTIMEOUT => 20,
        CURLOPT_TIMEOUT => 90,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_SSL_VERIFYHOST => 2,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_USERAGENT => $userAgent !== ''
            ? $userAgent
            : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
        CURLOPT_WRITEFUNCTION => function ($curl, $chunk) use (&$buffer, &$tooLarge, $maxBytes): int {
            if ($tooLarge) {
                return 0;
            }
            $buffer .= $chunk;
            if (strlen($buffer) > $maxBytes) {
                $tooLarge = true;
                return 0;
            }
            return strlen($chunk);
        },
    ]);
    $ok = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $error = curl_error($ch);
    curl_close($ch);
    if ($tooLarge) {
        fail('原文件超过解析上限，请改用本机解析或较小的文件');
    }
    if ($ok === false || $status !== 200) {
        fail('网盘读取失败' . ($status > 0 ? '（HTTP ' . $status . '）' : '：' . $error));
    }
    if ($buffer === '') {
        fail('网盘返回了空文件');
    }
    return $buffer;
}

function parseBook(string $bytes, string $name, bool $metaOnly): array
{
    $ext = strtolower(pathinfo(parse_url($name, PHP_URL_PATH) ?: $name, PATHINFO_EXTENSION));
    if ($ext === '') {
        $pathExt = strtolower(pathinfo(parse_url($name, PHP_URL_PATH) ?: '', PATHINFO_EXTENSION));
        if ($pathExt !== '') {
            $ext = $pathExt;
        }
    }
    $isZip = strlen($bytes) > 4 && substr($bytes, 0, 2) === 'PK';
    if ($ext === 'pdf' || substr($bytes, 0, 4) === '%PDF') {
        fail('该格式暂不支持服务器解析，请让 App 回退本机解析');
    }
    if ($isZip) {
        $zip = openZip($bytes);
        if ($zip !== null) {
            // 即使文件名被清理成“书名”没有扩展名，也按压缩包内部结构识别。
            $hasEpub = $zip->locateName('META-INF/container.xml') !== false;
            $hasDocx = $zip->locateName('word/document.xml') !== false;
            $hasOdt = $zip->locateName('content.xml') !== false;
            if ($hasEpub) {
                $result = parseEpub($zip, $metaOnly);
                $zip->close();
                if ($result !== null) return $result;
            }
            if ($hasDocx) {
                $zip->close();
                return parseDocx($bytes, $metaOnly);
            }
            if ($hasOdt) {
                $zip->close();
                return parseOdt($bytes, $metaOnly);
            }
            $inner = detectZipBook($zip);
            if ($inner !== null) {
                $innerBytes = $zip->getFromName($inner);
                if (is_string($innerBytes) && $innerBytes !== '') {
                    $zip->close();
                    return parseBook($innerBytes, $inner, $metaOnly);
                }
            }
            $zip->close();
        }
    }
    if ($ext === 'docx') {
        return parseDocx($bytes, $metaOnly);
    }
    if ($ext === 'odt') {
        return parseOdt($bytes, $metaOnly);
    }
    if ($ext === 'fb2') {
        return parseFb2($bytes, $metaOnly);
    }
    if ($ext === 'html' || $ext === 'htm' || $ext === 'xhtml') {
        return parseHtml($bytes, $metaOnly);
    }
    if (in_array($ext, ['mobi', 'prc', 'azw', 'azw3', 'pdf'], true)) {
        fail('该格式暂不支持服务器解析，请让 App 回退本机解析');
    }
    if (preg_match('/<\s*FictionBook\b/i', substr($bytes, 0, 8192))) {
        return parseFb2($bytes, $metaOnly);
    }
    $head = ltrim(substr($bytes, 0, 512));
    if (preg_match('/^<\s*(?:!doctype\s+html|html)\b/i', $head)) {
        return parseHtml($bytes, $metaOnly);
    }
    return parseText($bytes, $name, $metaOnly);
}

function openZip(string $bytes): ?ZipArchive
{
    if (!class_exists('ZipArchive')) {
        fail('主机缺少 ZIP 扩展');
    }
    $tmp = tempnam(sys_get_temp_dir(), 'wenku-parse-');
    if ($tmp === false) {
        fail('主机无法创建临时文件');
    }
    file_put_contents($tmp, $bytes);
    $zip = new ZipArchive();
    if ($zip->open($tmp) !== true) {
        @unlink($tmp);
        return null;
    }
    register_shutdown_function(static function () use ($tmp): void {
        @unlink($tmp);
    });
    return $zip;
}

function detectZipBook(ZipArchive $zip): ?string
{
    $names = [];
    for ($i = 0; $i < $zip->numFiles; $i++) {
        $name = $zip->getNameIndex($i);
        if (is_string($name)) {
            $names[] = str_replace('\\', '/', $name);
        }
    }
    if (in_array('META-INF/container.xml', $names, true)) {
        return null;
    }
    foreach ($names as $name) {
        if (preg_match('/\.(epub|docx|odt|fb2|txt|md|html?|xhtml)$/i', $name)) {
            return $name;
        }
    }
    return null;
}

function zipMeta(ZipArchive $zip, string $metaName, array $coverNames): array
{
    $title = $author = $summary = null;
    $cover = null;
    $xmlText = $zip->getFromName($metaName);
    if (is_string($xmlText) && $xmlText !== '') {
        $dom = loadXmlDocument($xmlText);
        if ($dom !== null) {
            $xpath = new DOMXPath($dom);
            foreach (['title', 'creator', 'description'] as $tag) {
                $nodes = $xpath->query("//*[local-name()='" . $tag . "']");
                if ($nodes !== false && $nodes->length > 0) {
                    $value = trim($nodes->item(0)?->textContent ?? '');
                    if ($value !== '') {
                        if ($tag === 'title') $title = $value;
                        if ($tag === 'creator') $author = $value;
                        if ($tag === 'description') $summary = $value;
                    }
                }
            }
        }
    }
    foreach ($coverNames as $coverName) {
        $data = $zip->getFromName($coverName);
        if (is_string($data) && $data !== '' && strlen($data) <= 4 * 1024 * 1024) {
            $cover = $data;
            break;
        }
    }
    return ['title' => $title, 'author' => $author, 'summary' => $summary, 'cover' => $cover];
}

function parseEpub(ZipArchive $zip, bool $metaOnly): ?array
{
    $container = $zip->getFromName('META-INF/container.xml');
    $opfPath = '';
    if (is_string($container) && preg_match('/full-path=["\']([^"\']+)["\']/', $container, $match)) {
        $opfPath = html_entity_decode($match[1], ENT_QUOTES | ENT_HTML5, 'UTF-8');
    }
    if ($opfPath === '') {
        for ($i = 0; $i < $zip->numFiles; $i++) {
            $name = $zip->getNameIndex($i);
            if (is_string($name) && preg_match('/\.opf$/i', $name)) {
                $opfPath = $name;
                break;
            }
        }
    }
    if ($opfPath === '') {
        return null;
    }
    $opf = $zip->getFromName($opfPath);
    if (!is_string($opf) || $opf === '') {
        return null;
    }
    $base = '';
    $slash = strrpos($opfPath, '/');
    if ($slash !== false) {
        $base = substr($opfPath, 0, $slash + 1);
    }
    $title = $author = $summary = null;
    $dom = loadXmlDocument($opf);
    if ($dom !== null) {
        $xpath = new DOMXPath($dom);
        $titleNode = $xpath->query("//*[local-name()='title']")->item(0);
        if ($titleNode !== null) {
            $title = trim($titleNode->textContent);
        }
        $authors = [];
        foreach ($xpath->query("//*[local-name()='creator']") as $node) {
            $value = trim($node->textContent);
            if ($value !== '') {
                $authors[] = $value;
            }
        }
        if ($authors !== []) {
            $author = implode('、', $authors);
        }
        $descNode = $xpath->query("//*[local-name()='description']")->item(0);
        if ($descNode !== null) {
            $summary = trim(strip_tags($descNode->textContent));
        }
    }
    $manifest = [];
    preg_match_all('/<item\b[^>]*>/i', $opf, $items);
    foreach ($items[0] as $tag) {
        if (!preg_match('/\bid=["\']([^"\']+)["\']/i', $tag, $idMatch)) {
            continue;
        }
        if (!preg_match('/\bhref=["\']([^"\']+)["\']/i', $tag, $hrefMatch)) {
            continue;
        }
        $manifest[$idMatch[1]] = [
            'href' => html_entity_decode($hrefMatch[1], ENT_QUOTES | ENT_HTML5, 'UTF-8'),
            'type' => preg_match('/\bmedia-type=["\']([^"\']+)["\']/i', $tag, $m) ? $m[1] : '',
            'properties' => preg_match('/\bproperties=["\']([^"\']+)["\']/i', $tag, $m) ? $m[1] : '',
        ];
    }
    $coverHref = null;
    if (preg_match('/<meta[^>]+name=["\']cover["\'][^>]+content=["\']([^"\']+)["\']/i', $opf, $m) && isset($manifest[$m[1]])) {
        $coverHref = $manifest[$m[1]]['href'];
    }
    if ($coverHref === null) {
        foreach ($manifest as $item) {
            if (str_contains($item['properties'], 'cover-image')) {
                $coverHref = $item['href'];
                break;
            }
        }
    }
    if ($coverHref === null) {
        foreach ($manifest as $item) {
            if (str_starts_with($item['type'], 'image/') && stripos($item['href'], 'cover') !== false) {
                $coverHref = $item['href'];
                break;
            }
        }
    }
    $cover = null;
    if ($coverHref !== null) {
        $data = $zip->getFromName(normalizePath($base . rawurldecode($coverHref)));
        if (is_string($data) && $data !== '' && strlen($data) <= 4 * 1024 * 1024) {
            $cover = $data;
        }
    }
    $ordered = [];
    preg_match_all('/<itemref\b[^>]*>/i', $opf, $refs);
    foreach ($refs[0] as $tag) {
        if (preg_match('/\bidref=["\']([^"\']+)["\']/i', $tag, $m) && isset($manifest[$m[1]])) {
            $ordered[] = rawurldecode($manifest[$m[1]]['href']);
        }
    }
    if ($ordered === []) {
        foreach ($manifest as $item) {
            if (str_contains($item['type'], 'xhtml') || str_ends_with(strtolower($item['href']), '.html')) {
                $ordered[] = rawurldecode($item['href']);
            }
        }
    }
    $result = [
        'format' => 'epub',
        'title' => $title ?: null,
        'author' => $author ?: null,
        'summary' => $summary ?: null,
        'cover' => $cover,
        'chapters' => [],
        'media' => [],
    ];
    if ($metaOnly) {
        return $result;
    }
    $seen = [];
    $mediaBytes = 0;
    foreach ($ordered as $href) {
        $path = normalizePath($base . $href);
        $markup = $zip->getFromName($path);
        if (!is_string($markup) || trim($markup) === '') {
            continue;
        }
        $chapterDom = loadHtmlDocument($markup);
        if ($chapterDom === null) {
            continue;
        };
        $chapterTitle = '';
        foreach (['h1', 'h2', 'title'] as $tag) {
            $nodes = $chapterDom->getElementsByTagName($tag);
            if ($nodes->length > 0) {
                $chapterTitle = trim($nodes->item(0)?->textContent ?? '');
                if ($chapterTitle !== '') break;
            }
        }
        $blocks = [];
        $xpath = new DOMXPath($chapterDom);
        foreach ($xpath->query('//body//p | //body//img') as $node) {
            if (strtolower($node->nodeName) === 'img') {
                $src = trim($node->getAttribute('src'));
                if ($src === '') continue;
                $imagePath = normalizePath(dirname($path) . '/' . rawurldecode($src));
                $data = $zip->getFromName($imagePath);
                if (!is_string($data) || $data === '' || strlen($data) > 4 * 1024 * 1024) continue;
                $key = sha1($data);
                if (!isset($seen[$key])) {
                    $seen[$key] = true;
                    $mediaBytes += strlen($data);
                    if ($mediaBytes <= 16 * 1024 * 1024) {
                        $result['media'][] = ['key' => $key, 'data' => base64_encode($data)];
                    }
                }
                $blocks[] = '[[CLOUD_MEDIA:' . $key . ']]';
                continue;
            }
            $text = trim(preg_replace('/\s+/u', ' ', $node->textContent) ?? '');
            if ($text !== '') {
                $blocks[] = $text;
            }
        }
        if ($blocks === []) {
            $body = trim(preg_replace('/\s+/u', ' ', $chapterDom->textContent) ?? '');
            if ($body !== '') $blocks[] = $body;
        }
        $body = trim(implode("\n\n", $blocks));
        if ($body === '') continue;
        $result['chapters'][] = [
            'title' => limitText($chapterTitle !== '' ? $chapterTitle : '第 ' . (count($result['chapters']) + 1) . ' 章', 100),
            'content' => $body,
        ];
    }
    if ($result['chapters'] === []) {
        return null;
    }
    return $result;
}

function parseDocx(string $bytes, bool $metaOnly): array
{
    $zip = openZip($bytes);
    if ($zip === null) fail('DOCX 无法打开');
    $meta = zipMeta($zip, 'docProps/core.xml', [
        'docProps/thumbnail.jpeg',
        'docProps/thumbnail.jpg',
        'docProps/thumbnail.png',
    ]);
    $xml = $zip->getFromName('word/document.xml');
    $zip->close();
    if (!is_string($xml) || $xml === '') fail('DOCX 正文不存在');
    $dom = loadXmlDocument($xml);
    if ($dom === null) fail('DOCX 正文格式无效');
    $xpath = new DOMXPath($dom);
    $chapters = [];
    $paragraphs = [];
    $chapterTitle = '';
    foreach ($xpath->query('//*[local-name()="p"]') as $p) {
        $text = '';
        foreach ($xpath->query('.//*[local-name()="t"]', $p) as $t) {
            $text .= $t->textContent;
        }
        $text = trim(preg_replace('/\s+/u', ' ', $text) ?? '');
        if ($text === '') continue;
        $style = '';
        $styleNode = $xpath->query('.//*[local-name()="pStyle"]', $p)->item(0);
        if ($styleNode !== null) {
            $style = strtolower($styleNode->getAttribute('w:val') ?: $styleNode->getAttribute('val') ?: '');
        }
        if (str_starts_with($style, 'heading') || str_starts_with($style, '标题')) {
            if ($paragraphs !== []) {
                $chapters[] = [
                    'title' => $chapterTitle !== '' ? $chapterTitle : '第 ' . (count($chapters) + 1) . ' 节',
                    'content' => implode("\n\n", $paragraphs),
                ];
                $paragraphs = [];
            }
            $chapterTitle = $text;
            continue;
        }
        $paragraphs[] = $text;
    }
    if ($paragraphs !== []) {
        $chapters[] = [
            'title' => $chapterTitle !== '' ? $chapterTitle : '第 ' . (count($chapters) + 1) . ' 节',
            'content' => implode("\n\n", $paragraphs),
        ];
    }
    if ($chapters === []) fail('DOCX 没有可读文字');
    return [
        'format' => 'docx',
        'title' => $meta['title'],
        'author' => $meta['author'],
        'summary' => $meta['summary'] ?: limitText($chapters[0]['content'], 300),
        'cover' => $meta['cover'],
        'chapters' => $metaOnly ? [] : $chapters,
        'media' => [],
    ];
}

function parseOdt(string $bytes, bool $metaOnly): array
{
    $zip = openZip($bytes);
    if ($zip === null) fail('ODT 无法打开');
    $meta = zipMeta($zip, 'meta.xml', ['Thumbnails/thumbnail.png']);
    $xml = $zip->getFromName('content.xml');
    $zip->close();
    if (!is_string($xml) || $xml === '') fail('ODT 正文不存在');
    $dom = loadXmlDocument($xml);
    if ($dom === null) fail('ODT 正文格式无效');
    $xpath = new DOMXPath($dom);
    $chapters = [];
    $paragraphs = [];
    $chapterTitle = '';
    foreach ($xpath->query('//*[local-name()="h" or local-name()="p"]') as $node) {
        $text = trim(preg_replace('/\s+/u', ' ', $node->textContent) ?? '');
        if ($text === '') continue;
        if (strtolower($node->localName) === 'h') {
            if ($paragraphs !== []) {
                $chapters[] = [
                    'title' => $chapterTitle !== '' ? $chapterTitle : '第 ' . (count($chapters) + 1) . ' 节',
                    'content' => implode("\n\n", $paragraphs),
                ];
                $paragraphs = [];
            }
            $chapterTitle = $text;
            continue;
        }
        $paragraphs[] = $text;
    }
    if ($paragraphs !== []) {
        $chapters[] = [
            'title' => $chapterTitle !== '' ? $chapterTitle : '第 ' . (count($chapters) + 1) . ' 节',
            'content' => implode("\n\n", $paragraphs),
        ];
    }
    if ($chapters === []) fail('ODT 没有可读文字');
    return [
        'format' => 'odt',
        'title' => $meta['title'],
        'author' => $meta['author'],
        'summary' => $meta['summary'] ?: limitText($chapters[0]['content'], 300),
        'cover' => $meta['cover'],
        'chapters' => $metaOnly ? [] : $chapters,
        'media' => [],
    ];
}

function parseFb2(string $bytes, bool $metaOnly): array
{
    $dom = loadXmlDocument($bytes);
    if ($dom === null) fail('FB2 格式无效');
    $xpath = new DOMXPath($dom);
    $titleNode = $xpath->query("//*[local-name()='title-info']/*[local-name()='book-title']")->item(0);
    $title = $titleNode ? trim($titleNode->textContent) : null;
    $authors = [];
    foreach ($xpath->query("//*[local-name()='title-info']//*[local-name()='author']") as $authorNode) {
        $parts = [];
        foreach (['first-name', 'middle-name', 'last-name'] as $tag) {
            $node = $xpath->query("./*[local-name()='" . $tag . "']", $authorNode)->item(0);
            if ($node !== null) {
                $parts[] = trim($node->textContent);
            }
        }
        $name = trim(implode(' ', array_filter($parts)));
        if ($name !== '') $authors[] = $name;
    }
    $author = $authors === [] ? null : implode('、', $authors);
    $annotation = $xpath->query("//*[local-name()='title-info']/*[local-name()='annotation']")->item(0);
    $summary = $annotation ? trim(preg_replace('/\s+/u', ' ', $annotation->textContent) ?? '') : null;
    $cover = null;
    $coverHref = $xpath->query("//*[local-name()='coverpage']//*[local-name()='image']")->item(0);
    if ($coverHref !== null) {
        $href = $coverHref->getAttribute('l:href') ?: $coverHref->getAttribute('href') ?: '';
        $id = str_contains($href, '#') ? substr($href, strrpos($href, '#') + 1) : '';
        if ($id !== '') {
            $binary = $xpath->query("//*[local-name()='binary' and @id='" . $id . "']")->item(0);
            if ($binary !== null) {
                $data = base64_decode(preg_replace('/\s+/', '', $binary->textContent), true);
                if (is_string($data) && $data !== '' && strlen($data) <= 4 * 1024 * 1024) {
                    $cover = $data;
                }
            }
        }
    }
    $chapters = [];
    $paragraphs = [];
    $chapterTitle = '';
    foreach ($xpath->query("//*[local-name()='body']//*[local-name()='section']") as $section) {
        $sectionTitle = $xpath->query("./*[local-name()='title']", $section)->item(0);
        $titleText = $sectionTitle ? trim(preg_replace('/\s+/u', ' ', $sectionTitle->textContent) ?? '') : '';
        $body = '';
        foreach ($xpath->query("./*[local-name()='p']", $section) as $p) {
            $text = trim(preg_replace('/\s+/u', ' ', $p->textContent) ?? '');
            if ($text !== '') $body .= ($body === '' ? '' : "\n\n") . $text;
        }
        if ($body === '') continue;
        $chapters[] = [
            'title' => $titleText !== '' ? limitText($titleText, 100) : '第 ' . (count($chapters) + 1) . ' 章',
            'content' => $body,
        ];
    }
    if ($chapters === []) fail('FB2 没有可读章节');
    return [
        'format' => 'fb2',
        'title' => $title ?: null,
        'author' => $author,
        'summary' => $summary,
        'cover' => $cover,
        'chapters' => $metaOnly ? [] : $chapters,
        'media' => [],
    ];
}

function parseHtml(string $bytes, bool $metaOnly): array
{
    $dom = loadHtmlDocument($bytes);
    if ($dom === null) fail('HTML 格式无效');
    $xpath = new DOMXPath($dom);
    $title = null;
    $author = null;
    $summary = null;
    foreach ([
        "//*[local-name()='meta' and translate(@property,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='og:title']",
        "//*[local-name()='meta' and translate(@name,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='author']",
        "//*[local-name()='meta' and translate(@property,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='og:description']",
        "//*[local-name()='meta' and translate(@name,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='description']",
    ] as $query) {
        $node = $xpath->query($query)->item(0);
        if ($node !== null) {
            $value = trim($node->getAttribute('content'));
            if ($value !== '') {
                if (str_contains($query, 'og:title')) $title = $value;
                elseif (str_contains($query, 'author')) $author = $value;
                elseif ($summary === null) $summary = $value;
            }
        }
    }
    if ($title === null) {
        $h1 = $xpath->query('//h1')->item(0);
        $titleText = trim($h1 ? $h1->textContent : '');
        if ($titleText !== '') $title = $titleText;
    }
    $paragraphs = [];
    foreach ($xpath->query('//body//p') as $p) {
        $text = trim(preg_replace('/\s+/u', ' ', $p->textContent) ?? '');
        if ($text !== '') $paragraphs[] = $text;
    }
    $body = implode("\n\n", $paragraphs);
    if ($body === '') {
        $body = trim(preg_replace('/\s+/u', ' ', $dom->textContent) ?? '');
    }
    if ($body === '') fail('HTML 没有可读文字');
    return [
        'format' => 'html',
        'title' => $title,
        'author' => $author,
        'summary' => $summary ?: limitText($body, 300),
        'cover' => null,
        'chapters' => $metaOnly ? [] : [[
            'title' => $title ?: '正文',
            'content' => $body,
        ]],
        'media' => [],
    ];
}

function parseText(string $bytes, string $name, bool $metaOnly): array
{
    $text = decodeText($bytes);
    if (trim($text) === '') fail('文件没有可读文字');
    $author = null;
    if (preg_match('/(?:作者|作\s*者|Author)\s*[:：]\s*([^\r\n]{1,40})/iu', substr($text, 0, 4000), $m)) {
        $author = trim($m[1]);
    }
    $lines = preg_split('/\r\n|\r|\n/', $text);
    $title = null;
    foreach (array_slice($lines, 0, 12) as $line) {
        $line = trim($line);
        if ($line === '' || mb_strlen($line) > 80) continue;
        if (preg_match('/^(作者|作\s*者|Author|书名|简介|内容简介)\s*[:：]/iu', $line)) continue;
        if (preg_match('/^第[0-9零一二三四五六七八九十百千万〇两]+[章节回卷篇]/u', $line)) continue;
        $title = preg_replace('/^(书名|Title)\s*[:：]\s*/iu', '', $line);
        if ($title !== '') break;
    }
    $text = str_replace(["\r\n", "\r"], "\n", $text);
    $chapters = [];
    if (!$metaOnly) {
        preg_match_all('/第[0-9零一二三四五六七八九十百千万〇两]+[章节回卷篇][^\n]{0,40}/u', $text, $matches, PREG_OFFSET_CAPTURE);
        if (count($matches[0]) >= 3) {
            $starts = array_map(static fn ($m) => $m[1], $matches[0]);
            $starts[] = strlen($text);
            for ($i = 0; $i < count($starts) - 1; $i++) {
                $chunk = trim(substr($text, $starts[$i], $starts[$i + 1] - $starts[$i]));
                if ($chunk === '') continue;
                $first = preg_split('/\n/', $chunk)[0] ?? '';
                $chapters[] = ['title' => limitText(trim($first), 100), 'content' => $chunk];
            }
        } else {
            $paragraphs = preg_split('/\n\s*\n/', $text);
            $buffer = '';
            $index = 1;
            foreach ($paragraphs as $paragraph) {
                $paragraph = trim($paragraph);
                if ($paragraph === '') continue;
                $buffer .= ($buffer === '' ? '' : "\n\n") . $paragraph;
                if (mb_strlen($buffer) > 60000) {
                    $chapters[] = ['title' => '第 ' . $index . ' 节', 'content' => $buffer];
                    $index++;
                    $buffer = '';
                }
            }
            if ($buffer !== '') {
                $chapters[] = ['title' => '第 ' . $index . ' 节', 'content' => $buffer];
            }
        }
        if ($chapters === []) {
            $chapters[] = ['title' => '正文', 'content' => $text];
        }
    }
    return [
        'format' => 'text',
        'title' => $title,
        'author' => $author,
        'summary' => limitText(trim(preg_replace('/\s+/u', ' ', $text) ?? ''), 300),
        'cover' => null,
        'chapters' => $chapters,
        'media' => [],
    ];
}

function decodeText(string $bytes): string
{
    if (str_starts_with($bytes, "\xEF\xBB\xBF")) {
        $bytes = substr($bytes, 3);
    }
    $encoding = mb_detect_encoding($bytes, ['UTF-8', 'GB18030', 'GBK', 'BIG5'], true) ?: 'UTF-8';
    if ($encoding !== 'UTF-8') {
        $converted = @mb_convert_encoding($bytes, 'UTF-8', $encoding);
        if (is_string($converted)) return $converted;
    }
    return $bytes;
}

function loadXmlDocument(string $xml): ?DOMDocument
{
    $dom = new DOMDocument();
    $previous = libxml_use_internal_errors(true);
    $ok = $dom->loadXML($xml, LIBXML_NONET | LIBXML_NOERROR | LIBXML_NOWARNING);
    libxml_clear_errors();
    libxml_use_internal_errors($previous);
    return $ok ? $dom : null;
}

function loadHtmlDocument(string $html): ?DOMDocument
{
    $dom = new DOMDocument();
    $previous = libxml_use_internal_errors(true);
    $ok = $dom->loadHTML('<?xml encoding="UTF-8">' . $html, LIBXML_NONET | LIBXML_NOERROR | LIBXML_NOWARNING);
    libxml_clear_errors();
    libxml_use_internal_errors($previous);
    return $ok ? $dom : null;
}

function normalizePath(string $path): string
{
    $parts = [];
    foreach (explode('/', str_replace('\\', '/', $path)) as $part) {
        if ($part === '..') {
            array_pop($parts);
        } elseif ($part !== '.' && $part !== '') {
            $parts[] = $part;
        }
    }
    return implode('/', $parts);
}

function limitText(string $value, int $length): string
{
    $value = trim($value);
    return mb_strlen($value) <= $length ? $value : mb_substr($value, 0, $length) . '…';
}
?>