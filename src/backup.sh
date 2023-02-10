#!/bin/bash

set -eu
set -o pipefail

trap 'rm /tmp/.backup.lck' ERR

if [ -f "/tmp/.backup.lck" ]; then 
  echo "Lock file exists!"
  exit 0
fi

touch /tmp/.backup.lck

# source ./env.sh

echo "Creating backup of $POSTGRES_INSTALLATION database..."

timestamp=$(date +%Y-%m-%dT%H:%M:%S)

local_file="db.dump"
s3_uri_base="s3://${S3_BUCKET}/${S3_PREFIX}/${POSTGRES_INSTALLATION}"
s3_uri="$s3_uri_base"

# dbname
dump_one() {
  echo "Dumping database $1"
  pg_dump -Z0 -h $POSTGRES_HOST \
        -d $1 \
        -p $POSTGRES_PORT \
        -U $POSTGRES_USER \
        -v -c | gzip -9 | aespipe -P <( echo $PASSPHRASE ) | aws $aws_args s3 cp - "$s3_uri/$1/${timestamp}.sql.aes" --metadata "{\"backup-database\":\"$1\"}"
  echo "Database $1 backup is done!"
}


for DB in $(psql -h $POSTGRES_HOST -U $POSTGRES_USER -p $POSTGRES_PORT -t -A -F"," -c "select datname from pg_database where datname <> ALL ('{template0,template1}')"); do
    dump_one $DB &
done

wait
# pg_dumpall -h $POSTGRES_HOST \
#         -p $POSTGRES_PORT \
#         -U $POSTGRES_USER \
#         $PGDUMP_EXTRA_OPTS \
#         -v -c | gzip -9 | /usr/bin/aespipe -P <(echo $PASSPHRASE) | aws $aws_args s3 cp - "$s3_uri"

# echo "Uploading backup to $S3_BUCKET..."
# aws $aws_args s3 cp "$local_file" "$s3_uri"
# rm "$local_file"

echo "Backup complete."

if [ -z "$S3_PREFIX" ] || [ "$S3_PREFIX" == "" ] || [ "$S3_PREFIX" == "/" ]; then
  echo "S3_PREFIX must be set and not equal to '' or '/'\!" 1>&2
  exit 1
fi

if [ -n "$BACKUP_KEEP_DAYS" ]; then
  sec=$((86400*BACKUP_KEEP_DAYS))
  date_from_remove=$(date -d @$(($(date +%s) - sec)) +%Y-%m-%d)
  backups_query="Contents[?LastModified<='${date_from_remove} 00:00:00'].{Key: Key}"

  echo "Removing old backups from $S3_BUCKET..."
  old_backups=$(aws $aws_args s3api list-objects \
    --bucket "${S3_BUCKET}" \
    --prefix "${S3_PREFIX}" \
    --query "${backups_query}" \
    --output text)
  echo "Old backup list: $old_backups"
  echo $old_backups | xargs -n1 -t -I 'KEY' aws $aws_args s3 rm s3://"${S3_BUCKET}"/'KEY'
  echo "Removal complete."
fi

rm /tmp/.backup.lck
