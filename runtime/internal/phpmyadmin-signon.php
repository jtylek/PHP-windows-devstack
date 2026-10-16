<?php
declare(strict_types=1);

// This endpoint is served only to the local machine by Apache. It supports the
// control panel's one-time token and a local fallback form. It must never log
// passwords or expose token data in a URL.
if (!in_array($_SERVER['REMOTE_ADDR'] ?? '', ['127.0.0.1', '::1'], true)) {
    http_response_code(403);
    exit('Local access only.');
}

$stackRoot = dirname(__DIR__);
$tokensRoot = $stackRoot . DIRECTORY_SEPARATOR . 'data' . DIRECTORY_SEPARATOR . 'secrets' . DIRECTORY_SEPARATOR . 'phpmyadmin-signon';
$portConfig = $stackRoot . DIRECTORY_SEPARATOR . 'data' . DIRECTORY_SEPARATOR . 'config' . DIRECTORY_SEPARATOR . 'ports.json';
$port = 3307;
if (is_file($portConfig)) {
    $settings = json_decode((string)file_get_contents($portConfig), true);
    if (is_array($settings) && isset($settings['MariaDbPort']) && is_int($settings['MariaDbPort'])) {
        $port = $settings['MariaDbPort'];
    }
}

function complete_signon(string $user, string $password, int $port): void {
    session_name('DevStackPhpMyAdmin');
    session_set_cookie_params(['path' => '/', 'httponly' => true, 'samesite' => 'Strict']);
    session_start();
    $_SESSION['PMA_single_signon_user'] = $user;
    $_SESSION['PMA_single_signon_password'] = $password;
    $_SESSION['PMA_single_signon_host'] = '127.0.0.1';
    $_SESSION['PMA_single_signon_port'] = (string)$port;
    session_write_close();
    header('Location: /phpmyadmin/', true, 303);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['token']) && is_string($_POST['token'])) {
    $token = $_POST['token'];
    if (preg_match('/\A[a-f0-9]{64}\z/', $token) !== 1) {
        http_response_code(400); exit('Invalid sign-in request.');
    }
    $recordPath = $tokensRoot . DIRECTORY_SEPARATOR . hash('sha256', $token) . '.json';
    if (!is_file($recordPath)) { http_response_code(410); exit('This sign-in request has expired. Return to the Control Panel and try again.'); }
    $record = json_decode((string)file_get_contents($recordPath), true);
    @unlink($recordPath); // Tokens are single-use, including on a failed request.
    if (!is_array($record) || !isset($record['expires'], $record['user'], $record['password']) ||
        !is_int($record['expires']) || $record['expires'] < time() || $record['user'] !== 'root' || !is_string($record['password'])) {
        http_response_code(410); exit('This sign-in request has expired. Return to the Control Panel and try again.');
    }
    complete_signon('root', $record['password'], $port);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['user'], $_POST['password']) && is_string($_POST['user']) && is_string($_POST['password'])) {
    complete_signon($_POST['user'], $_POST['password'], $port);
}
?>
<!doctype html><html><head><meta charset="utf-8"><title>PHPDevStack phpMyAdmin sign in</title></head>
<body><form method="post"><h1>phpMyAdmin sign in</h1><p>Use your MariaDB credentials.</p>
<label>User <input name="user" value="root" autofocus></label><br>
<label>Password <input name="password" type="password"></label><br>
<button type="submit">Sign in</button></form></body></html>
