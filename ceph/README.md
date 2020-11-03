# ceph

Notes on how I deployed Ceph and configured it for access by OCS.

## Environment

This is the background info on why the ceph cluster is running on the
ospnetwork with IP `192.168.25.222`.

[openstack-k8s-operators/dev-tools](https://github.com/openstack-k8s-operators/dev-tools) 
will configure some of the following networks:
```
[root@hypervisor ~]# ip r
default via 10.1.27.254 dev eno3 proto dhcp metric 100 
10.1.27.0/24 dev eno3 proto kernel scope link src 10.1.27.21 metric 100 
10.88.0.0/16 dev cni-podman0 proto kernel scope link src 10.88.0.1 
169.254.0.0/16 dev ostestpr scope link metric 1116 
172.22.0.0/24 dev ostestpr proto kernel scope link src 172.22.0.1 
192.168.25.0/24 dev ospnetwork proto kernel scope link src 192.168.25.1 
192.168.111.0/24 dev ostestbm proto kernel scope link src 192.168.111.1 
192.168.122.0/24 dev virbr0 proto kernel scope link src 192.168.122.1 
[root@hypervisor ~]# 
```
The worker nodes where the OCS and OSP pods will run are deployed by
[metal3](https://metal3.io) which uses 192.168.111.0/24 (ostestbm) as
its provisioning network. The same pods also have access to the 
network 192.168.25.0/24 (ospnetwork). The csi-rbdplugin-provisioner
deployed by OCS has access to the ospnetwork and so will the CN-OSP
pods. Thus I connected my VM to the same bridge and gave it an IP on
that network.

I found [sookocheff.com](https://sookocheff.com/post/kubernetes/understanding-kubernetes-networking-model/) helpful in figuring this out, though in a production environment I
should probably use [egress IPs](https://www.techbeatly.com/2020/05/openshift-4-egressip-for-egress-connection.html).

## Install Ceph

Run these commands on the ceph vm as per
https://docs.ceph.com/en/latest/cephadm/install

- Install cephadm
```
dnf install python3
curl --silent --remote-name --location https://github.com/ceph/ceph/raw/octopus/src/cephadm/cephadm
chmod +x cephadm
./cephadm add-repo --release octopus
./cephadm install
```
- Bootstrap cluster
```
mkdir -p /etc/ceph
cephadm bootstrap --mon-ip 192.168.25.222
```
- Install Ceph tools
```
cephadm install ceph-common
```
- Add OSDs
```
ceph orch apply osd --all-available-devices
```
- Create Pool for OCS RBD
```
ceph osd pool create ocs
```

Scale the cluster as needed.

## Export Ceph Information for OCS

- Put the extraction script on the VM hosting Ceph

As described in the 
[docs](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.5/html/deploying_openshift_container_storage_in_external_mode/creating-an-openshift-container-storage-cluster-service-for-external-storage_rhocs),
OCS will provide the script
`ceph-external-cluster-details-exporter.py`. Download and `scp`
accordingly.

- Put the extraction script in the ceph container set up by cephadm

On the VM hosting Ceph run `cephadm shell` in one terminal (A) and
determine the name of the container which was started in another
terminal (B). In the example below the container name is
"great_dhawan" and `podman cp` is run in terminal B to make the script
available in the container.

```
[root@ceph ~]# podman ps | grep ceph | head -1
b7e77d3e7490  docker.io/ceph/ceph:v15               /bin/bash             About a minute ago  Up About a minute ago         great_dhawan
[root@ceph ~]# ls
anaconda-ks.cfg  cephadm  ceph-external-cluster-details-exporter.py  original-ks.cfg
[root@ceph ~]# podman cp ceph-external-cluster-details-exporter.py great_dhawan:/
[root@ceph ~]# 
```
- Run the extraction script in terminal A and save the resultant JSON

```
[ceph: root@ceph /]# python3 ceph-external-cluster-details-exporter.py --rbd-data-pool-name ocs
[{"name": "rook-ceph-mon-endpoints", "kind": "ConfigMap", "data": {"data": "ceph=192.168.25.222:6789", "maxMonId": "0", "mapping": "{}"}}, {"name": "rook-ceph-mon", "kind": "Secret", "data": {"admin-secret": "admin-secret", "cluster-name": "openshift-storage", "fsid": "f1ef036c-1566-11eb-a0d6-525400190ce6", "mon-secret": "mon-secret"}}, {"name": "rook-ceph-operator-creds", "kind": "Secret", "data": {"userID": "client.healthchecker", "userKey": "AQBWNJNfA6FuNhAAtPVkw6kCAhHYmAcJex1vZQ=="}}, {"name": "rook-csi-rbd-node", "kind": "Secret", "data": {"userID": "csi-rbd-node", "userKey": "AQBWNJNfke+jNhAAnzXUWL34qGPec1X2pdyqRA=="}}, {"name": "ceph-rbd", "kind": "StorageClass", "data": {"pool": "ocs"}}, {"name": "rook-csi-rbd-provisioner", "kind": "Secret", "data": {"userID": "csi-rbd-provisioner", "userKey": "AQBWNJNflIvWNhAAzlWddIupqNZOdq0meLNfWg=="}}]
[ceph: root@ceph /]# 
```

- Finish

Continue following the 
[docs](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.5/html/deploying_openshift_container_storage_in_external_mode/creating-an-openshift-container-storage-cluster-service-for-external-storage_rhocs)
and upload the extracted JSON when asked.

When finished you should see OCS running and accessing the external
Ceph cluster and you should be able to make persistent volume claims.

```
[root@hypervisor ~]# oc get cephcluster -n openshift-storage
NAME                                      DATADIRHOSTPATH   MONCOUNT   AGE     PHASE       MESSAGE                          HEALTH
ocs-external-storagecluster-cephcluster                                7m19s   Connected   Cluster connected successfully   HEALTH_WARN
[root@hypervisor ~]# 
```

```
[root@hypervisor ~]# oc get storagecluster -n openshift-storage
NAME                          AGE     PHASE   EXTERNAL   CREATED AT             VERSION
ocs-external-storagecluster   7m49s   Ready   true       2020-11-02T22:56:11Z   4.5.0
[root@hypervisor ~]# 
```

```
[root@hypervisor ~]# oc get pods -n openshift-storage
NAME                                         READY   STATUS    RESTARTS   AGE
csi-rbdplugin-chldl                          3/3     Running   0          13m
csi-rbdplugin-dxhj5                          3/3     Running   0          13m
csi-rbdplugin-hszfw                          3/3     Running   0          13m
csi-rbdplugin-njb7g                          3/3     Running   0          13m
csi-rbdplugin-njm8j                          3/3     Running   0          13m
csi-rbdplugin-provisioner-66f66699c8-4f8kz   5/5     Running   0          13m
csi-rbdplugin-provisioner-66f66699c8-sl9xm   5/5     Running   0          13m
noobaa-core-0                                1/1     Running   2          13m
noobaa-db-0                                  0/1     Pending   0          13m
noobaa-operator-65599fc7c4-g42qn             1/1     Running   0          14m
ocs-operator-7b9d696577-5mwmg                1/1     Running   0          14m
rook-ceph-operator-796c69d4c7-p7djr          1/1     Running   0          14m
[root@hypervisor ~]# 
```

## Export Ceph Information for OSP

- Connect to the ceph vm and run `cephadm shell`
- Create pools for openstack
```
for POOL in vms volumes images; do ceph osd pool create $POOL; done
```
- Create an openstack cephx client key to access the pools
```
ceph auth add client.openstack mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=vms, allow rwx pool=volumes, allow rwx pool=images'
```
- Export the OpenStack key
```
ceph auth get client.openstack > ceph.client.openstack.keyring
```
- Export the Ceph config
```
ceph config generate-minimal-conf > ceph.conf
```

Put `ceph.conf` and `ceph.client.openstack.keyring` in /etc/ceph/ of
Ceph clients.
