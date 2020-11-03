# vm

Optional scripts to create a quick VM to run a ceph cluster.

- [centos.sh](centos.sh)
  - download centos8 cloud image
  - minamally modify it (e.g. remove cloud init, install ssh key)
  - configure it to use an extra network (192.168.25.0/24)
  - (5 minutes or less)

- [clone.sh](clone.sh)
  - clone VM(s) from centos8 named ceph0 (ceph1 ...)
  - add ceph0 entry to /etc/hosts
  - assign an IP to eth0 on the extra network
  - create virtual block device to be used as an OSD
  - (5 minutes or less)
