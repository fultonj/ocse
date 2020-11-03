#!/usr/bin/env bash
# -------------------------------------------------------
DOM=example.com
BASENAME=ceph
SRC="centos8"
IP=192.168.122.252
RAM=11718750
CPU=4
NUMBER=1
# -------------------------------------------------------
CREATE=1
DISK=1
STORAGE_NET=1
SSH_OPT="-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null"
KEY=$(cat ~/.ssh/id_rsa.pub)

for i in $(seq 0 $(( $NUMBER - 1 )) ); do
    NAME="${BASENAME}${i}"
    if [[ $CREATE -eq 1 ]]; then
        IPDEC="IPADDR=$IP"
        if [[ -e /var/lib/libvirt/images/$NAME.qcow2 ]]; then
	    echo "Destroying old $NAME"
	    if [[ $(sudo virsh list | grep $NAME) ]]; then
	        sudo virsh destroy $NAME
	    fi
	    sudo virsh undefine $NAME
	    sudo rm -f /var/lib/libvirt/images/$NAME.qcow2
	    sudo sed -i "/$IP.*/d" /etc/hosts
        fi
        sudo virt-clone --original=$SRC --name=$NAME --file /var/lib/libvirt/images/$NAME.qcow2

        sudo virsh setmaxmem $NAME --size $RAM --config
        sudo virsh setmem $NAME --size $RAM --config
        sudo virsh setvcpus $NAME --count $CPU --maximum --config
        sudo virsh setvcpus $NAME --count $CPU --config

        sudo virt-customize -a /var/lib/libvirt/images/$NAME.qcow2 --run-command "SRC_IP=\$(grep IPADDR /etc/sysconfig/network-scripts/ifcfg-eth1) ; sed -i s/\$SRC_IP/$IPDEC/g /etc/sysconfig/network-scripts/ifcfg-eth1"
        if [[ ! $(sudo virsh list | grep $NAME) ]]; then
	    sudo virsh start $NAME
        fi
        echo "Waiting for $NAME to boot and allow to SSH at $IP"
        while [[ ! $(ssh $SSH_OPT root@$IP "uname") ]]
        do
	    echo "No route to host yet; sleeping 30 seconds"
	    sleep 30
        done
        ssh $SSH_OPT root@$IP "hostname $NAME.$DOM ; echo HOSTNAME=$NAME.$DOM >> /etc/sysconfig/network"
        ssh $SSH_OPT root@$IP "echo \"$IP    $NAME.$DOM        $NAME\" >> /etc/hosts "
        sudo sh -c "echo $IP    $NAME.$DOM        $NAME >> /etc/hosts"
    fi
    if [[ $DISK -eq 1 ]]; then
        # Add disks
        X=b
        pushd /var/lib/libvirt/images/
        echo "Creating disk ${NAME}-${X}.img"
        if [[ -e ${NAME}-${X}.img ]]; then
            sudo rm -f -v ${NAME}-${X}.img
        fi
        sudo qemu-img create -f raw ${NAME}-${X}.img 50G
        sudo virsh attach-disk $NAME \
             --source /var/lib/libvirt/images/${NAME}-${X}.img \
             --target vd$X \
             --persistent \
             --cache none
        popd
    fi
    if [[ $STORAGE_NET -eq 1 ]]; then
        FINAL_OCTET=$(($i+2))
        cat > /tmp/storage_net <<EOF
if [[ \$(ip a s eth0 | grep 192.168.25 | wc -l) -eq 0 ]]; then
   echo "Bringing up eth0"
   cat /dev/null > /tmp/eth0
   echo "DEVICE=eth0" >> /tmp/eth0
   echo "ONBOOT=yes" >> /tmp/eth0
   echo "TYPE=Ethernet" >> /tmp/eth0
   echo "IPADDR=192.168.25.$FINAL_OCTET" >> /tmp/eth0
   echo "PREFIX=24" >> /tmp/eth0
   sudo mv /tmp/eth0 /etc/sysconfig/network-scripts/ifcfg-eth0
   sudo chcon system_u:object_r:net_conf_t:s0 /etc/sysconfig/network-scripts/ifcfg-eth0
   sudo ifdown eth0
   sudo ifup eth0
   ip a s eth0
else
   echo "eth0 is already configured"
fi
EOF
        echo "running the following script on $NAME"
        cat /tmp/storage_net
        scp $SSH_OPT /tmp/storage_net stack@$NAME:/tmp/storage_net
        ssh $SSH_OPT stack@$NAME "bash /tmp/storage_net"
    fi
    echo "$NAME is ready"
    ssh $SSH_OPT stack@$NAME "uname -a; lsblk"
    echo ""
    echo "ssh stack@$NAME"
    echo ""
    # decrement the management IP by one for the next loop
    TAIL=$(echo $IP | awk -F  "." '/1/ {print $4}')
    HEAD=$(echo $IP | sed s/$TAIL//g)
    TAIL=$(( TAIL - 1))
    IP=$HEAD$TAIL
done
