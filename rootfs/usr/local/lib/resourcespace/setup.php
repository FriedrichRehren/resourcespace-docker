<?php

/**
 * Non-interactive counterpart of ResourceSpace's pages/setup.php.
 *
 * The file is deliberately called "setup.php": ResourceSpace derives the page
 * name from the script name and skips its automatic upgrade routine for the
 * "setup" page, exactly like the web installer does.
 *
 * Usage (as www-data, config.php must already exist):
 *   php setup.php install          initialise an empty database + create admin
 *   php setup.php admin-password   (re)set the admin password from the environment
 */

if (PHP_SAPI !== 'cli') {
    exit(1);
}

$mode = $argv[1] ?? '';
if (!in_array($mode, ['install', 'admin-password'], true)) {
    fwrite(STDERR, "Usage: php setup.php install|admin-password\n");
    exit(1);
}

$webroot = getenv('RS_WEBROOT') ?: '/var/www/html';

$admin_username = getenv('RS_ADMIN_USERNAME') ?: 'admin';
$admin_password = getenv('RS_ADMIN_PASSWORD') ?: '';
$admin_fullname = getenv('RS_ADMIN_FULLNAME') ?: 'Admin user';
$admin_email    = getenv('RS_ADMIN_EMAIL') ?: '';

if ($admin_password === '') {
    fwrite(STDERR, "FEHLER: RS_ADMIN_PASSWORD ist nicht gesetzt.\n");
    exit(1);
}

$suppress_headers = true;
$show_detailed_errors = true;
include_once $webroot . '/include/boot.php';
include_once $webroot . '/include/slideshow_functions.php';

// ResourceSpace refuses logins with passwords of exactly 32 or 64 characters,
// because they look like MD5/SHA-256 hashes (see rs_password_verify()).
if (in_array(mb_strlen($admin_password), [32, 64], true)) {
    fwrite(STDERR, "FEHLER: RS_ADMIN_PASSWORD darf nicht genau 32 oder 64 Zeichen lang sein – "
        . "ResourceSpace hält solche Passwörter für Hashes und verweigert den Login.\n");
    exit(1);
}

$password_check = check_password($admin_password);
if ($password_check !== true) {
    fwrite(STDERR, "FEHLER: RS_ADMIN_PASSWORD erfüllt die Passwortregeln nicht: {$password_check}\n");
    exit(1);
}

if ($mode === 'install') {
    if (!filter_var($admin_email, FILTER_VALIDATE_EMAIL)) {
        fwrite(STDERR, "FEHLER: RS_ADMIN_EMAIL fehlt oder ist keine gültige E-Mail-Adresse.\n");
        exit(1);
    }

    echo "Lege Datenbankstruktur an ...\n";
    check_db_structs();

    // Same as the web installer: a fresh database is at the current upgrade level
    if (!get_sysvar('upgrade_system_level')) {
        set_sysvar('upgrade_system_level', SYSTEM_UPGRADE_LEVEL);
    }

    // Sign field specific PHP code shipped with the default metadata fields
    resign_all_code(false, false);

    // Slideshow / login background images
    $homeanim_folder_name = basename($homeanim_folder);
    $to_folder = "{$storagedir}/system/{$homeanim_folder_name}";
    if (!is_dir($to_folder)) {
        mkdir($to_folder, 0777, true);
    }

    $source_folder = $webroot . '/gfx/homeanim';
    $found_files = [];
    foreach (new DirectoryIterator($source_folder) as $file) {
        if (!$file->isDot() && $file->isFile()) {
            $found_files[] = $file->getFilename();
        }
    }
    natsort($found_files);
    $found_files = array_values($found_files);

    foreach ($found_files as $index => $file) {
        $filename = pathinfo($file, PATHINFO_FILENAME);
        set_slideshow($filename, null, 1, $index === 0 ? 1 : 0);
        if (!copy("{$source_folder}/{$file}", "{$to_folder}/{$file}")) {
            fwrite(STDERR, "WARNUNG: Slideshow-Bild {$file} konnte nicht kopiert werden.\n");
        }
    }
}

// Create or update the super admin (user group 3), as the web installer does
$password_hash = rs_password_hash("RS{$admin_username}{$admin_password}");
$exists = (int) ps_value('SELECT count(*) value FROM user WHERE username = ?', ['s', $admin_username], 0);

if ($exists === 0) {
    if ($mode !== 'install') {
        fwrite(STDERR, "FEHLER: Benutzer '{$admin_username}' existiert nicht.\n");
        exit(1);
    }
    ps_query(
        'INSERT INTO user (username, password, fullname, email, usergroup, approved) VALUES (?, ?, ?, ?, 3, 1)',
        ['s', $admin_username, 's', $password_hash, 's', $admin_fullname, 's', $admin_email]
    );
    echo "Admin-Benutzer '{$admin_username}' angelegt.\n";
} else {
    ps_query(
        'UPDATE user SET password = ?, login_tries = 0 WHERE username = ?',
        ['s', $password_hash, 's', $admin_username]
    );
    echo "Passwort für '{$admin_username}' gesetzt.\n";
}

exit(0);
