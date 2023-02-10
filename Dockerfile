ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION} as build

RUN apk update && apk add build-base

RUN wget https://loop-aes.sourceforge.net/aespipe-latest.tar.bz2
RUN tar xvf aespipe-latest.tar.bz2
RUN cd aespipe-v2.4f && ./configure && make && cp aespipe /usr/bin

ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION}
ARG TARGETARCH

COPY --from=build /usr/bin/aespipe /usr/bin/aespipe

ADD src/install.sh install.sh
RUN sh install.sh && rm install.sh

ENV POSTGRES_INSTALLATION ''
ENV POSTGRES_HOST ''
ENV POSTGRES_PORT 5432
ENV POSTGRES_USER ''
ENV POSTGRES_PASSWORD ''
ENV PGDUMP_EXTRA_OPTS ''
ENV S3_ACCESS_KEY_ID ''
ENV S3_SECRET_ACCESS_KEY ''
ENV S3_BUCKET ''
ENV S3_REGION 'us-west-1'
ENV S3_PATH 'backup'
ENV S3_ENDPOINT ''
ENV S3_S3V4 'no'
ENV SCHEDULE ''
ENV PASSPHRASE ''
ENV BACKUP_KEEP_DAYS ''
ENV PGDUMP_EXTRA_OPTS ''

ADD src/run.sh run.sh
ADD src/env.sh env.sh
ADD src/backup.sh backup.sh
ADD src/restore.sh restore.sh
ADD src/schedule.sh schedule.sh
ADD src/schedule_test.sh schedule_test.sh

CMD ["sh", "run.sh"]
