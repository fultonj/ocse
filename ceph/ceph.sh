#!/usr/bin/env bash

INV=inventory.ini
ANS=$PWD/tripleo-ceph
if [[ ! -d $ANS ]]; then
    echo "Fail: git clone https://github.com/fultonj/tripleo-ceph/ to $ANS"
    exit 1
fi
if [[ ! -e $INV ]]; then
    echo "Fail: Ansible inventory $INV is missing"
    exit 1
fi
pushd $ANS
ansible-playbook -i ../$INV site.yaml -v --skip-tags nodes $@
popd
