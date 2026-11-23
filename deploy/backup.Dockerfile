# The backup job needs pg_dump plus the AWS CLI for R2 (02 §9).
FROM alpine:3.20
RUN apk add --no-cache postgresql16-client aws-cli gzip tzdata
COPY backup.sh /backup/backup.sh
RUN chmod +x /backup/backup.sh
CMD ["/backup/backup.sh"]
