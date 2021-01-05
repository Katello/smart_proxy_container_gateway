# Smart Proxy - Container Gateway

A Foreman smart proxy plugin for Katello.  Implements container registry functions for Pulp 3-enabled smart proxy mirrors.

# Example Apache /etc/httpd/conf.d/05-foreman-ssl.d/docker_proxy.conf

```
<Location /pulpcore_registry/v2/>
   SSLRequire %{SSL_CLIENT_S_DN_CN} eq "admin"
</Location>

SSLProxyCheckPeerCN off
SSLProxyCheckPeerName off

ProxyPass /pulpcore_registry/v2/ http://127.0.0.1:24817/v2/
ProxyPassReverse /pulpcore_registry/v2/ http://127.0.0.1:24817/v2/

ProxyPass /pulp/container/ unix:///run/pulpcore-content.sock|http://centos7-katello-devel.cannolo.example.com/pulp/container/
ProxyPassReverse /pulp/container/ unix:///run/pulpcore-content.sock|http://centos7-katello-devel.cannolo.example.com/pulp/container/

ProxyPass /v2 https://127.0.0.1:9090/container_gateway/v2
ProxyPassReverse https://127.0.0.1:9090/container_gateway/v2 /v2
ProxyPass /v1 https://127.0.0.1:9090/container_gateway/v1
ProxyPassReverse https://127.0.0.1:9090/container_gateway/v1 /v1
```

# Server configuration

The Container Gateway plugin requires a Pulp 3 instance to connect to.  Related configuration options:
```
:pulp_endpoint: 'https://your_pulp_3_server_here.com'
:pulp_client_ssl_cert: 'Path to X509 certificate for authenticating with Pulp'
:pulp_client_ssl_key: 'Path to RSA private key for the Pulp certificate'
```

# Database configuration

The Container Gateway plugin assumes that PostgreSQL is installed on the system since Katello + Pulp 3 is a requirement.

For a manual installation, which is currently the only installation method, a database must be created with the name
`smart_proxy_container_gateway`.  There must also be a PostgreSQL user who has full access to this database. Related configuration options:
```
:postgres_db_hostname: 'localhost'
:postgres_db_username: 'db_user'
:postgres_db_password: 'password'
```

Database migrations are completely automated.  The plugin checks if the database is up-to-date before each query.

# Katello interaction

Auth information is retrieved from the Katello server during smart proxy sync time and cached in the PostgreSQL database.

# Testing

Running the full test suite requires setting up the test PostgreSQL database.  Create the test database with the following configuration:

- Database name: `smart_proxy_container_gateway_test`
- Database user: `smart_proxy_container_gateway_test_user`
- Database user password: `smart_proxy_container_gateway_test_password`

The database user must have full access to the test DB.
