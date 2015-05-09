#!/bin/bash

set -e

if [ -n "$MYSQL_PORT_3306_TCP" ]; then
	if [ -z "$MANTISBT_DB_HOST" ]; then
		MANTISBT_DB_HOST='mysql'
	else
		echo >&2 'warning: both MANTISBT_DB_HOST and MYSQL_PORT_3306_TCP found'
		echo >&2 "  Connecting to MANTISBT_DB_HOST ($MANTISBT_DB_HOST)"
		echo >&2 '  instead of the linked mysql container'
	fi
fi

if [ -z "$MANTISBT_DB_HOST" ]; then
	echo >&2 'error: missing MANTISBT_DB_HOST and MYSQL_PORT_3306_TCP environment variables'
	echo >&2 '  Did you forget to --link some_mysql_container:mysql or set an external db'
	echo >&2 '  with -e MANTISBT_DB_HOST=hostname:port?'
	exit 1
fi

# if we're linked to MySQL, and we're using the root user, and our linked
# container has a default "root" password set up and passed through... :)
: ${MANTISBT_DB_USER:=root}
if [ "$MANTISBT_DB_USER" = 'root' ]; then
	: ${MANTISBT_DB_PASSWORD:=$MYSQL_ENV_MYSQL_ROOT_PASSWORD}
fi
: ${MANTISBT_DB_NAME:=mantisBT}

if [ -z "$MANTISBT_DB_PASSWORD" ]; then
	echo >&2 'error: missing required MANTISBT_DB_PASSWORD environment variable'
	echo >&2 '  Did you forget to -e MANTISBT_DB_PASSWORD=... ?'
	echo >&2
	echo >&2 '  (Also of interest might be MANTISBT_DB_USER and MANTISBT_DB_NAME.)'
	exit 1
fi

#if ! [ -e index.php -a -e wp-includes/version.php ]; then
#	echo >&2 "MantisBT not found in $(pwd) - copying now..."
#	if [ "$(ls -A)" ]; then
#		echo >&2 "WARNING: $(pwd) is not empty - press Ctrl+C now if this is an error!"
#		( set -x; ls -A; sleep 10 )
#	fi
#	tar cf - --one-file-system -C /usr/src/wordpress . | tar xf -
#	echo >&2 "Complete! WordPress has been successfully copied to $(pwd)"
#	if [ ! -e .htaccess ]; then
#		# NOTE: The "Indexes" option is disabled in the php:apache base image
#		cat > .htaccess <<-'EOF'
#			# BEGIN WordPress
#			<IfModule mod_rewrite.c>
#			RewriteEngine On
#			RewriteBase /
#			RewriteRule ^index\.php$ - [L]
#			RewriteCond %{REQUEST_FILENAME} !-f
#			RewriteCond %{REQUEST_FILENAME} !-d
#			RewriteRule . /index.php [L]
#			</IfModule>
#			# END WordPress
#		EOF
#		chown www-data:www-data .htaccess
#	fi
#fi
#
# TODO handle WordPress upgrades magically in the same way, but only if wp-includes/version.php's $wp_version is less than /usr/src/wordpress/wp-includes/version.php's $wp_version


set_config() {
	key="$1"
	value="$2"
	php_escaped_value="$(php -r 'var_export($argv[1]);' "$value")"
	sed_escaped_value="$(echo "$php_escaped_value" | sed 's/[\/&]/\\&/g')"
	sed -ri "s/((['\"])$key\2\s*,\s*)(['\"]).*\3/\1$sed_escaped_value/" wp-config.php
}

#set_config 'DB_HOST' "$MANTISBT_DB_HOST"
#set_config 'DB_USER' "$MANTISBT_DB_USER"
#set_config 'DB_PASSWORD' "$MANTISBT_DB_PASSWORD"
#set_config 'DB_NAME' "$MANTISBT_DB_NAME"

# allow any of these "Authentication Unique Keys and Salts." to be specified via
# environment variables with a "MANTISBT_" prefix (ie, "MANTISBT_AUTH_KEY")
#UNIQUES=(
#	AUTH_KEY
#	SECURE_AUTH_KEY
#	LOGGED_IN_KEY
#	NONCE_KEY
#	AUTH_SALT
#	SECURE_AUTH_SALT
#	LOGGED_IN_SALT
#	NONCE_SALT
#)
#for unique in "${UNIQUES[@]}"; do
#	eval unique_value=\$MANTISBT_$unique
#	if [ "$unique_value" ]; then
#		set_config "$unique" "$unique_value"
#	else
#		# if not specified, let's generate a random value
#		current_set="$(sed -rn "s/define\((([\'\"])$unique\2\s*,\s*)(['\"])(.*)\3\);/\4/p" wp-config.php)"
#		if [ "$current_set" = 'put your unique phrase here' ]; then
#			set_config "$unique" "$(head -c1M /dev/urandom | sha1sum | cut -d' ' -f1)"
#		fi
#	fi
#done
set -x

TERM=dumb php -- "$MANTISBT_DB_HOST" "$MANTISBT_DB_USER" "$MANTISBT_DB_PASSWORD" "$MANTISBT_DB_NAME" <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)
$stderr = fopen('php://stderr', 'w');
list($host, $port) = explode(':', $argv[1], 2);



$maxTries = 2;
do {
	$mysql = new mysqli($host, $argv[2], $argv[3], '', (int)$port);
	if ($mysql->connect_error) {
		fwrite($stderr, "\n" . 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
		--$maxTries;
		if ($maxTries <= 0) {
			exit(1);
		}
		sleep(3);
	}
} while ($mysql->connect_error);
if (!$mysql->query('CREATE DATABASE IF NOT EXISTS `' . $mysql->real_escape_string($argv[4]) . '`')) {
	fwrite($stderr, "\n" . 'MySQL "CREATE DATABASE" Error: ' . $mysql->error . "\n");
	$mysql->close();
	exit(1);
}
if (!$mysql->query('GRANT ALL PRIVILEGES ON '. $argv[4] . '.* TO \''.$argv[2]. '\'@\'%\'')) {
        fwrite($stderr, "\n" . 'MySQL "GRANT ALL PRIVILEGES" Error: ' . $mysql->error . "\n");
        $mysql->close();
        exit(1);
}
$mysql->close();
EOPHP

exec "$@"
