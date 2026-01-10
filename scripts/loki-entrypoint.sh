#!/bin/sh
# Don't use set -e here, we want to handle errors gracefully

# Create required directories with proper permissions
mkdir -p /loki/chunks /loki/index /loki/cache /loki/compactor /loki/rules /loki/rules-temp 2>/dev/null || true

# Set proper ownership (only if running as root)
# On macOS Docker Desktop, volumes may have permission restrictions
if [ "$(id -u)" = "0" ]; then
    # Redirect stderr to suppress permission errors if volume has restrictions
    chown -R 65534:65534 /loki 2>/dev/null || true
    
    # Ensure directories are at least writable
    chmod -R 755 /loki 2>/dev/null || true
fi

# Determine current user ID
CURRENT_UID=$(id -u)

# If we're root, switch to non-root user; otherwise run as current user
if [ "$CURRENT_UID" = "0" ]; then
    # Switch to non-root user and execute Loki
    # Try su-exec first (common in Alpine), then runuser (util-linux), then su (fallback)
    if command -v su-exec >/dev/null 2>&1; then
        exec su-exec 65534:65534 /usr/bin/loki "$@"
    elif command -v runuser >/dev/null 2>&1; then
        exec runuser -u 65534 -- /usr/bin/loki "$@"
    else
        exec su -s /bin/sh 65534 -c "exec /usr/bin/loki $*"
    fi
else
    # Already running as non-root, execute directly
    exec /usr/bin/loki "$@"
fi
