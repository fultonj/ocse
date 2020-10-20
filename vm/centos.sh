#!/usr/bin/env bash
# -------------------------------------------------------
IP=192.168.122.253
NAME=centos8
RAM=8192
CPU=1
PASSWD=abc123
IMG=CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2
URL=https://cloud.centos.org/centos/8/x86_64/images/$IMG
DOM=example.com
# -------------------------------------------------------
if [[ ! -e ~/.ssh/id_rsa.pub ]]; then
    echo "Please run ssh-keygen"
    exit 1
else
    KEY=$(cat ~/.ssh/id_rsa.pub)
fi
if [[ ! -e ~/.ssh/config ]]; then
    cat /dev/null > ~/.ssh/config
    echo "StrictHostKeyChecking no" >> ~/.ssh/config
    echo "UserKnownHostsFile=/dev/null" >> ~/.ssh/config
    echo "LogLevel ERROR" >> ~/.ssh/config
    chmod 0600 ~/.ssh/config
    chmod 0700 ~/.ssh
fi
# -------------------------------------------------------
sudo dnf install -y libguestfs-tools libvirt virt-install
if [[ ! $(sudo systemctl status libvirtd) ]]; then
   sudo systemctl start libvirtd
fi
# -------------------------------------------------------
if [[ ! $(sudo ls /var/lib/libvirt/images/$IMG) ]]; then
    echo "Downloading $URL"
    curl $URL > $IMG
    sudo cp $IMG /var/lib/libvirt/images/
    # to download newer image run 'sudo rm /var/lib/libvirt/images/$IMG'
fi
# -------------------------------------------------------
if [[ ! $(sudo virsh net-list | grep storage) ]]; then
    BR_NAME=storage
    MAC=52:54:00:e5:01:43
    echo "Creating virtual bridge $BR_NAME"
    
    cat /dev/null > /tmp/net.xml
    echo "<network>" >> /tmp/net.xml
    echo "<name>$BR_NAME</name>" >> /tmp/net.xml
    echo "<bridge name='$BR_NAME' stp='off' delay='0'/>" >> /tmp/net.xml
    echo "<mac address='$MAC'/>" >> /tmp/net.xml
    echo "</network>" >> /tmp/net.xml
    
    sudo virsh net-define /tmp/net.xml
    sudo virsh net-start $BR_NAME
    sudo virsh net-autostart $BR_NAME
fi
# -------------------------------------------------------
if [[ -e /var/lib/libvirt/images/$NAME.qcow2 ]]; then
    echo "Destroying old $NAME"
    if [[ $(sudo virsh list | grep $NAME) ]]; then
	sudo virsh destroy $NAME
    fi
    sudo virsh undefine $NAME
    sudo rm -f /var/lib/libvirt/images/$NAME.qcow2
fi
# -------------------------------------------------------
echo "Building new $NAME"
pushd /var/lib/libvirt/images/
if [[ ! -e $IMG ]]; then
    echo "IMG is missing"
    exit 1
fi
sudo qemu-img info $IMG
SIZE=$(sudo qemu-img info /var/lib/libvirt/images/$IMG | grep virtual | awk {'print $3'} | grep G | sed -e s/G// -e s/\.0//g)
if [[ $SIZE -lt 37 ]]; then  # if we have a new base cloud image grow the filesystem
    echo "Customizing base $IMG"
    sudo virt-filesystems --long -h --all -a $IMG
    sudo qemu-img resize $IMG +30G
    sudo virt-customize -a $IMG --run-command 'echo -e "d\nn\n\n\n\n\nw\n" | fdisk /dev/sda' 2> /dev/null
    sudo virt-customize -a $IMG --run-command 'xfs_growfs /'
    sudo virt-filesystems --long -h --all -a $IMG
    sudo virt-customize -a $IMG --run-command 'cp /etc/sysconfig/network-scripts/ifcfg-eth{0,1} && sed -i s/DEVICE=.*/DEVICE=eth1/g /etc/sysconfig/network-scripts/ifcfg-eth1'
else
    echo "File system size: $SIZE, not growing base image"
fi
echo "Creating $NAME from base image $IMG"
sudo qemu-img create -f qcow2 -b $IMG $NAME.qcow2
sudo virt-customize -a $NAME.qcow2 --run-command 'yum remove cloud-init* -y'
sudo virt-customize -a $NAME.qcow2 --root-password password:$PASSWD
sudo virt-customize -a $NAME.qcow2  --hostname $NAME.$DOM
sudo virt-customize -a $NAME.qcow2 --run-command "echo 'UseDNS no' >> /etc/ssh/sshd_config"
sudo virt-customize -a $NAME.qcow2 --run-command 'sed -i -e "s/ONBOOT=.*/ONBOOT=no/g" /etc/sysconfig/network-scripts/ifcfg-eth0'
sudo virt-customize -a $NAME.qcow2 --run-command 'sed -i -e "s/BOOTPROTO=.*/BOOTPROTO=none/g" -e "s/BOOTPROTOv6=.*/NM_CONTROLLED=no/g" -e "s/USERCTL=.*/IPADDR=THE_IP/g" -e "s/PEERDNS=.*/NETMASK=255.255.255.0/g" -e "s/IPV6INIT=.*/GATEWAY=192.168.122.1/g" -e "s/PERSISTENT_DHCLIENT=.*/DEFROUTE=yes/g" /etc/sysconfig/network-scripts/ifcfg-eth1'
sudo virt-customize -a $NAME.qcow2 --run-command "sed -i s/THE_IP/$IP/g /etc/sysconfig/network-scripts/ifcfg-eth1"
sudo virt-customize -a $NAME.qcow2 --run-command "mkdir /root/.ssh/; chmod 700 /root/.ssh/; echo $KEY > /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys; chcon system_u:object_r:ssh_home_t:s0 /root/.ssh ; chcon unconfined_u:object_r:ssh_home_t:s0 /root/.ssh/authorized_keys "
popd

# -------------------------------------------------------
sudo virt-install --ram $RAM --vcpus $CPU --os-variant centos8 --disk path=/var/lib/libvirt/images/$NAME.qcow2,device=disk,bus=virtio,format=qcow2 --import --noautoconsole --vnc --network network:storage --network network:default --name $NAME
sleep 10
if [[ ! $(sudo virsh list | grep $NAME) ]]; then
    echo "Cannot find new $NAME; Exiting."
    exit 1
fi
echo "Waiting for $NAME to boot and allow to SSH at $IP"
while [[ ! $(ssh root@$IP "uname") ]]
do
    echo "No route to host yet; sleeping 30 seconds"
    sleep 30
done
echo "SSH to $IP is working."
echo "Updating /etc/hosts"
ssh root@$IP 'echo "$IP    $NAME.$DOM        $NAME" >> /etc/hosts'
echo "Creating stack user"
ssh root@$IP 'useradd stack'
ssh root@$IP 'echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack'
ssh root@$IP 'chmod 0440 /etc/sudoers.d/stack'
ssh root@$IP "mkdir /home/stack/.ssh/; chmod 700 /home/stack/.ssh/; echo $KEY > /home/stack/.ssh/authorized_keys; chmod 600 /home/stack/.ssh/authorized_keys; chcon system_u:object_r:ssh_home_t:s0 /home/stack/.ssh ; chcon unconfined_u:object_r:ssh_home_t:s0 /home/stack/.ssh/authorized_keys; chown -R stack:stack /home/stack/.ssh/ "
ssh root@$IP "echo nameserver 192.168.122.1 > /etc/resolv.conf"
echo "$IP is ready"
ssh stack@$IP "uname -a"
echo "Shutting $NAME down"
ssh root@$IP "init 0"
