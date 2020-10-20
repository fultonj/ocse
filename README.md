# OCSe

Scripts to configure OCS with an External Ceph cluster.

- deploy a VM to host a ceph cluster: [vm](vm) 
- deploy a ceph cluster with cephadm: [ceph](ceph)
- configure ocs to use that ceph cluster in [external mode](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.5/html-single/deploying_openshift_container_storage_in_external_mode/index)
- configure ocp client type 1 to use PVs from ocs
- configure ocp client [type 2](https://github.com/fultonj/pyapp) to directly use RBD

If the above works, then it should also be possible to
replace ocp client type 2 with the ones created by
[openstack-k8s-operators](https://github.com/openstack-k8s-operators/dev-tools).
