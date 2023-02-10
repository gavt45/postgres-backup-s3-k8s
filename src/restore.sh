#!/bin/bash

set -u # `-e` omitted intentionally, but i can't remember why exactly :'(
set -o pipefail

source ./env.sh

s3_uri_base="s3://${S3_BUCKET}/${S3_PREFIX}/${POSTGRES_INSTALLATION}"

if [ -z "$PASSPHRASE" ]; then
  echo "PASSPHRASE is required!" 1>&2
  exit 1
fi


# DB
restore_db(){
  echo "Finding latest backup..."

  key_suffix=$(
    aws $aws_args s3 ls "${s3_uri_base}/$1/" \
      | sort \
      | tail -n 1 \
      | awk '{ print $4 }'
  )


  # database=$(
  #   aws s3api $aws_args head-object --bucket ${S3_BUCKET} --key ${key_suffix} | jq -r ".Metadata.\"x-backup-database\""
  # )

  echo "Restoring database $1"
  echo "Creating db $1..."
  psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -c "create database $1;" || echo "Exists!"
  echo "OK"

  aws $aws_args s3 cp "${s3_uri_base}/$1/${key_suffix}" - | \
    aespipe -d -P <( echo "$PASSPHRASE" ) | \
    gzip -d | \
    grep -wvx "CREATE ROLE postgres;" | \
    grep -wvx "ALTER ROLE postgres WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS PASSWORD .*" | \
    psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER $1
  echo "Restored $1!"
}


for DB in $(aws $aws_args s3 ls "${s3_uri_base}/" | grep PRE | sort | awk '{ print $2 }' | tr -d '/'); do
  restore_db $DB &
done

wait


# if [ -n "$PASSPHRASE" ]; then
#   echo "Decrypting backup..."
#   gpg --decrypt --batch --passphrase "$PASSPHRASE" db.dump.gpg > db.dump
#   rm db.dump.gpg
# fi

# tar xvf db.dump
# rm db.dump

# # Skip postgres, repmgr and pgpool_adm roles alter and creation
# cat db | \
#   grep -wvx "CREATE ROLE postgres;" | \
#   grep -wvx "ALTER ROLE postgres WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS PASSWORD .*" | \
#   grep -wvx "CREATE ROLE repmgr;" | \
#   grep -wvx "ALTER ROLE repmgr WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS PASSWORD .*" | \
#   grep -wvx "CREATE ROLE pgpool_adm;" | \
#   grep -wvx "ALTER ROLE pgpool_adm WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS PASSWORD .*" \
#   > db.nopg

# rm db

# conn_opts="-h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER"

# echo "Restoring from backup..."
# psql $conn_opts -f db.nopg postgres
# rm db.nopg

echo "Restore complete."
