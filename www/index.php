<?php
declare(strict_types=1);

$projects = [];
$root = __DIR__;

foreach (new DirectoryIterator($root) as $entry) {
    if ($entry->isDot() || !$entry->isDir() || str_starts_with($entry->getFilename(), '.')) {
        continue;
    }

    $name = $entry->getFilename();
    $projects[] = [
        'name' => $name,
        'url' => rawurlencode($name) . '/',
        'hasIndex' => is_file($entry->getPathname() . DIRECTORY_SEPARATOR . 'index.php') ||
            is_file($entry->getPathname() . DIRECTORY_SEPARATOR . 'index.html'),
    ];
}

usort($projects, static fn(array $left, array $right): int => strcasecmp($left['name'], $right['name']));
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>PHP DevStack Server</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <header>
        <a class="logo">
            <h2>PHP DevStack Server</h2>
        </a>
        <p class="subtitle">Local PHP development projects</p>
    </header>

    <main>
        <section class="intro">
            <h1>Projects</h1>
            <p>Place each project in its own directory under <code>www/</code>.</p>
        </section>

        <?php if ($projects === []): ?>
            <div class="empty-state">
                <p>No project directories found yet.</p>
                <p>Create a folder inside <code>C:\PHPDevStack\www</code> to get started.</p>
            </div>
        <?php else: ?>
            <div class="project-grid">
                <?php foreach ($projects as $project): ?>
                    <a class="project-card" href="<?= htmlspecialchars($project['url'], ENT_QUOTES, 'UTF-8') ?>">
                        <span class="project-icon">&lt;/&gt;</span>
                        <span class="project-details">
                            <strong><?= htmlspecialchars($project['name'], ENT_QUOTES, 'UTF-8') ?></strong>
                            <small><?= $project['hasIndex'] ? 'Open project' : 'Open directory' ?></small>
                        </span>
                        <span class="arrow" aria-hidden="true">&rarr;</span>
                    </a>
                <?php endforeach; ?>
            </div>
        <?php endif; ?>
    </main>

    <footer>
        PHP <?= htmlspecialchars(PHP_VERSION, ENT_QUOTES, 'UTF-8') ?> · Apache · MariaDB
    </footer>
</body>
</html>
