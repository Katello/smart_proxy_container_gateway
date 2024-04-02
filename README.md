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

# Database information

SQLite and PostgreSQL are supported, with SQLite being the default for development and testing.
Use PostgreSQL in production for improved performance by adding the following settings:
```
# Example PostgreSQL connection settings
:database_backend: postgres
:postgres_host: localhost
:postgres_user: foreman-proxy
:postgres_database: container_gateway
:postgres_password: changeme
```

Database migrations are completely automated.  The plugin checks if the database is up-to-date at initialization time.

# Katello interaction

Auth information is retrieved from the Katello server during smart proxy sync time and cached in the database.

Logging in with a container client will cause the Container Gateway to fetch a token from Katello using the login information.

# Testing

```
bundle exec rubocop

bundle exec rake test
```
