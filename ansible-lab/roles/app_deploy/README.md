# app_deploy

Downloads a `.zip` build or executable `.jar` from Amazon S3, deploys it under
`/opt/app`, writes `application.yml`, restarts a systemd service, and fails the
play when the configured health endpoint does not return HTTP 200.

The managed node needs AWS credentials with `s3:GetObject`; when using AWX,
attach an Amazon Web Services credential to the job template.

```yaml
- hosts: app_servers
  become: true
  roles:
    - role: app_deploy
      vars:
        app_s3_bucket: company-builds
        app_s3_key: simple-app/1.2.0/simple-app.zip
        app_artifact_type: zip
        app_service_name: simple-app
        app_healthcheck_url: http://127.0.0.1:8080/actuator/health
```
