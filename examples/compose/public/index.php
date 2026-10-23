<?php

declare(strict_types=1);

header('Content-Type: application/json');

echo json_encode([
    'message' => 'Your PHP application is running.',
    'path' => parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH),
], JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES), "\n";
