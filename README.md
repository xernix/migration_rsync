# migration_rsync
Bash script using rsync &amp; GNU parallel to sync between two directories

#USAGE
1. Run nightly_migration.sh wrapper script. This will call migration_core.sh

The cut off for migration is 6AM. The migration will stop at 6AM. Cut off time can be editted in nightly_migration
