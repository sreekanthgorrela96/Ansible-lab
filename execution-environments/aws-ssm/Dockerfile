FROM quay.io/ansible/awx-ee:24.6.1

USER root

COPY requirements.yml /tmp/requirements.yml

RUN ansible-galaxy collection install --force -p /usr/share/ansible/collections -r /tmp/requirements.yml

RUN python3 -m pip install --no-cache-dir --upgrade boto3 botocore

RUN curl -fsSL https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm -o /tmp/session-manager-plugin.rpm \
    && rpm -ivh --nodeps /tmp/session-manager-plugin.rpm \
    && ln -s /usr/local/sessionmanagerplugin/bin/session-manager-plugin /usr/local/bin/session-manager-plugin \
    && rm -f /tmp/session-manager-plugin.rpm

USER 1000
