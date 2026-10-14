<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>DevStack</title>
    <style>
        body { font-family: system-ui, sans-serif; max-width: 760px; margin: 10vh auto; padding: 0 24px; color: #182230; }
        code { background: #f2f4f7; border-radius: 4px; padding: 2px 6px; }
    </style>
</head>
<body>
    <h1>DevStack is running</h1>
    <p>Apache and PHP are serving files from <code>www/</code>.</p>
    <p>PHP version: <?= htmlspecialchars(PHP_VERSION, ENT_QUOTES, 'UTF-8') ?></p>
</body>
</html>
