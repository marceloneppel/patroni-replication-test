# Patroni Replication Test

This repository aims to show a difference on executing [patroni](https://github.com/zalando/patroni) directly inside a docker container and another situation where it's started by [pebble](https://github.com/canonical/pebble).

## Dependencies

The command below will install `curl`, `gettext-base` package (in order to use `envsubst`) and `microk8s` snap (you will also need Docker installed in your system).
```sh
make dependencies
```

## Building the images

Build the docker images (`test-patroni` and `test-pebble`) using the following command:
```sh
make build
```

## Testing Patroni being the entrypoint

Firstly you run the command to deploy the pods with patroni being the entrypoint:

```sh
make patroni
```

Then you run the command `make logs` to see the logs and check that we have the first pod as the replication leader (it's the Postgres instance which accept both reads and writes).

```sh
kubectl exec pod/patronidemo-0 -- tail -2 patroni.log
2022-01-14 20:59:54,813 INFO: no action. I am (patronidemo-0), the leader with the lock
2022-01-14 21:00:04,776 INFO: no action. I am (patronidemo-0), the leader with the lock

kubectl exec pod/patronidemo-1 -- tail -2 patroni.log
2022-01-14 20:59:54,819 INFO: no action. I am (patronidemo-1), a secondary, and following a leader (patronidemo-0)
2022-01-14 21:00:04,794 INFO: no action. I am (patronidemo-1), a secondary, and following a leader (patronidemo-0)

kubectl exec pod/patronidemo-2 -- tail -2 patroni.log
2022-01-14 20:59:54,821 INFO: no action. I am (patronidemo-2), a secondary, and following a leader (patronidemo-0)
2022-01-14 21:00:04,797 INFO: no action. I am (patronidemo-2), a secondary, and following a leader (patronidemo-0)
```

So, you can run the command `make crash-leader` to delete the pod of the leader and trigger a failover. Then you can check again the logs with `make logs`. After some time, we will have another instance as the leader and the other ones as replicas following the leader.

```
kubectl exec pod/patronidemo-0 -- tail -2 patroni.log
2022-01-14 21:05:21,263 INFO: no action. I am (patronidemo-0), a secondary, and following a leader (patronidemo-1)
2022-01-14 21:05:31,313 INFO: no action. I am (patronidemo-0), a secondary, and following a leader (patronidemo-1)

kubectl exec pod/patronidemo-1 -- tail -2 patroni.log
2022-01-14 21:05:21,248 INFO: no action. I am (patronidemo-1), the leader with the lock
2022-01-14 21:05:31,295 INFO: no action. I am (patronidemo-1), the leader with the lock

kubectl exec pod/patronidemo-2 -- tail -2 patroni.log
2022-01-14 21:05:21,259 INFO: no action. I am (patronidemo-2), a secondary, and following a leader (patronidemo-1)
2022-01-14 21:05:31,314 INFO: no action. I am (patronidemo-2), a secondary, and following a leader (patronidemo-1)
```

You can also check that there are no zombie processes using the command `make zombies`:
```
kubectl exec pod/patronidemo-0 -- ps aux | grep defunct || true

kubectl exec pod/patronidemo-1 -- ps aux | grep defunct || true

kubectl exec pod/patronidemo-2 -- ps aux | grep defunct || true
```

## Testing Patroni with Pebble starting it

Firstly you run the command to deploy the pods with pebble being the entrypoint. This time pebble starts patroni (we run `make clean` first in order to remove the previous deployment):

```sh
make clean
make pebble
```

You can check the logs with `make logs`:

```
kubectl exec pod/patronidemo-0 -- tail -2 patroni.log
2022-01-14 21:12:15,644 INFO: no action. I am (patronidemo-0), the leader with the lock
2022-01-14 21:12:25,752 INFO: no action. I am (patronidemo-0), the leader with the lock

kubectl exec pod/patronidemo-1 -- tail -2 patroni.log
2022-01-14 21:12:15,651 INFO: no action. I am (patronidemo-1), a secondary, and following a leader (patronidemo-0)
2022-01-14 21:12:25,759 INFO: no action. I am (patronidemo-1), a secondary, and following a leader (patronidemo-0)

kubectl exec pod/patronidemo-2 -- tail -2 patroni.log
2022-01-14 21:12:15,651 INFO: no action. I am (patronidemo-2), a secondary, and following a leader (patronidemo-0)
2022-01-14 21:12:25,758 INFO: no action. I am (patronidemo-2), a secondary, and following a leader (patronidemo-0)
```

Then crash the leader with `make crash-leader` and see the logs again with `make logs` after some time:

```
kubectl exec pod/patronidemo-0 -- tail -2 patroni.log
2022-01-14 21:14:22,696 INFO: no action. I am (patronidemo-0), a secondary, and following a leader (patronidemo-1)
2022-01-14 21:14:32,849 INFO: no action. I am (patronidemo-0), a secondary, and following a leader (patronidemo-1)

kubectl exec pod/patronidemo-1 -- tail -2 patroni.log
2022-01-14 21:14:22,690 INFO: no action. I am (patronidemo-1), the leader with the lock
2022-01-14 21:14:32,891 INFO: no action. I am (patronidemo-1), the leader with the lock

kubectl exec pod/patronidemo-2 -- tail -2 patroni.log
2022-01-14 21:14:32,768 INFO: Lock owner: patronidemo-1; I am patronidemo-2
2022-01-14 21:14:32,768 INFO: changing primary_conninfo and restarting in progress
```

This time we see one of the replicas (the one that was not elected as a leader after the failover) stuck in the process of restarting Postgres. This happens because patroni is waiting for the Postgres process (which became a zombie process) to completely stop (it never happens). The following is the output of the command `make zombies`:

```
kubectl exec pod/patronidemo-0 -- ps aux | grep defunct || true
postgres      29  0.0  0.0      0     0 ?        Z    21:14   0:00 [pg_basebackup] <defunct>

kubectl exec pod/patronidemo-1 -- ps aux | grep defunct || true

kubectl exec pod/patronidemo-2 -- ps aux | grep defunct || true
postgres      35  0.0  0.0      0     0 ?        Z    21:11   0:00 [postgres] <defunct>
```

## Testing Patroni with Supervisord starting it

Firstly you run the command to deploy the pods with supervisord being the entrypoint. This time supervisord starts patroni (we run `make clean` first in order to remove the previous deployment):

```sh
make clean
make supervisord
```

Then, we can check the logs the same way the other times and we'll see that this time the automatic failover will be done correctly as the first time.

## Known issues

If you see a message like the one below when running `make patroni` or `make pebble`, just run `make clean` and rerun the original command.

```
Warning: resource endpoints/patronidemo is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
```

Also, we are using `host replication standby 0.0.0.0/0 md5` in the Postgres authentication rules just to make this example work the way we need. It's more secure to use the pod's IP.