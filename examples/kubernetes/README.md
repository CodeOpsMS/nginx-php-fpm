# Run a PHP application on Kubernetes

This example serves a small PHP application from a read-only ConfigMap using the pinned
0.5.0 release digest. It runs as UID/GID 82, drops all capabilities, keeps the container
root filesystem read-only, and provides separate temporary and application-data volumes.
`fsGroup: 82` assigns the demo's temporary volumes to the runtime group. All volumes in
this manifest belong to the example; it does not mount an existing PVC.
The Service stays inside the cluster. TLS belongs at your ingress or reverse proxy.

Requirements: `kubectl`, a Kubernetes cluster, and permission to create a namespace,
ConfigMap, Deployment, and Service. Confirm the intended context with
`kubectl config current-context`. Use an unused namespace name for this example.

## Start and check the application

From the repository root:

```console
kubectl create namespace php-example
kubectl --namespace php-example apply --file examples/kubernetes/application.yaml
kubectl --namespace php-example rollout status deployment/php-example --timeout=120s
kubectl --namespace php-example port-forward service/php-example 8080:80
```

In a second terminal:

```console
curl --fail http://localhost:8080/healthz
curl --fail http://localhost:8080/hello
curl --fail http://localhost:8080/example.txt
```

`/healthz` exercises PHP-FPM and returns `ok`. `/hello` reaches `index.php` through
front-controller routing. `/example.txt` is served directly by nginx. The Service port
is `80`, but its `targetPort: http` resolves to the container's port `8080`; use that
container port for ingress backends that bypass the Service.

Inspect the workload and its writable data directory:

```console
kubectl --namespace php-example logs deployment/php-example
kubectl --namespace php-example exec deployment/php-example -- id
kubectl --namespace php-example exec deployment/php-example -- test -w /srv/application-data
```

The `emptyDir` data in `/tmp` and `/srv/application-data` disappears when the Pod is
replaced. This example does not configure persistent sessions or uploads. Its manifest
is a deployment starting point; the container's Compose integration tests do not
constitute an end-to-end Kubernetes application test.

## Use your application and storage

Replace the demonstration ConfigMap with a read-only application image or populated
volume that already contains dependencies. `DOCUMENT_ROOT` must name the application
directory inside the container. Point the application at `/srv/application-data`, or
mount a separate writable volume where the application expects its uploads/cache.
Use persistent storage for data that must survive a Pod replacement and grant the
runtime identity the required access before mounting it.

Review the Pod's `fsGroup` setting before adding an existing PVC: depending on the
volume driver, it can cause ownership/permission changes on that volume. The demo's
setting is not a recommendation to change the ownership of a shared application tree.

The image does not change the owner or mode of mounted files. For a tree already owned
by `100:101`, use that non-root identity in `runAsUser`/`runAsGroup` if its permissions
fit the application, or prepare targeted access for `82:82`. Verify the permissions of
both directories and files rather than relying on ownership alone.

If an additional read-only share belongs to group `1000` and has group read/search
permission, add `supplementalGroups: [1000]` under
`spec.template.spec.securityContext`. Keep the share's mount read-only. Use the real
numeric group for your share. This grants process group membership without changing
the PVC's ownership. Remove the demo's `fsGroup` setting when using prepared shared
storage, unless its behavior is explicitly required. A recursive ownership change is
not needed for this read-only access case.

For legacy GD code that loads a font by bare filename, set an explicit search directory
in the container's environment when needed:

```yaml
- name: GDFONTPATH
  value: /var/www/html
```

The font must exist there and be readable by the runtime identity. A code change to use
an absolute font path is also suitable. Validate the returned image or JSON, including
captchas, rather than checking only the HTTP status.

The default front controller routes unknown URLs to `index.php`. To preserve a legacy
file-based application's HTTP 404 behavior, builds after 0.5.0 support
`NGINX_FRONT_CONTROLLER=0`. The pinned example image does not have that setting: first
select and test a newer image digest. Keep the default `1` for applications relying on
front-controller routes such as `/hello`.

See the [migration guide](../../docs/migrating-from-richarvey.md) for environment
settings, PHP compatibility, permissions, and the traffic-switch procedure.

## Remove the example

```console
kubectl --namespace php-example delete --file examples/kubernetes/application.yaml
```

This removes only the three named example resources. If the namespace was created for
this example and still contains no other resources, it can then be removed separately.
