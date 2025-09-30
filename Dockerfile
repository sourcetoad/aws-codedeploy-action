FROM amazon/aws-cli:2.31.4

# Move files in for deployment & cleanup
COPY deploy.sh /deploy.sh
COPY cleanup.sh /cleanup.sh

# Get tools needed for packaging
RUN yum install -y zip unzip jq tar gzip && \
    yum clean all && \
    rm -rf /var/cache/yum
