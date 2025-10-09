# migration_rsync
Bash script using rsync &amp; GNU parallel to sync between two directories

# USAGE
Run nightly_migration.sh wrapper script. This will call migration_core.sh

The cut off for migration is 6AM. The migration will stop at 6AM. Cut off time can be editted in nightly_migration

migration_core.sh can be run manually without the wrapper but we must supply the parameter:

migration_core.sh path1 path2 path3

weekend_migration.sh - script running from Friday 10PM until Saturday 8PM
