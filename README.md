# OCSe

Goal: One Ceph cluster providing storage for both OpenShift (via OCS) and OpenStack

This POC is a variation where OpenStack runs in containers on OCP.

- Deploy OCP using `make ocp_install` from [openstack-k8s-operators/dev-tools](https://github.com/openstack-k8s-operators/dev-tools/blob/master/ansible/README.md)
- On the same hypervisor deploy a [vm](vm) and install [ceph](ceph)
- Add OCS and have it use the same ceph cluster in [external mode](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.5/html-single/deploying_openshift_container_storage_in_external_mode/index)
- Configure ocp client [type 2](https://github.com/fultonj/pyapp) to directly use RBD

If the above works, then it should also be possible to
replace ocp client type 2 with the ones created by
[openstack-k8s-operators](https://github.com/openstack-k8s-operators/dev-tools).
