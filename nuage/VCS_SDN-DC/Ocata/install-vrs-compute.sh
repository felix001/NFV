#!/usr/bin/env bash
# VSP 5.3.2

# Variables
VSC1_IP=172.29.236.186
VSC2_IP=
OS_CONTROLLER_IP=172.29.236.180
NOVA_OS_PW=56eb3244272e42f5
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

echo "${BOLD}[*] Install crudini${NORMAL}"
easy_install crudini

echo "${BOLD}[*] Disable SELinux${NORMAL}"
sed -i 's/SELINUX=.*$/SELINUX=disabled/g' /etc/selinux/config
setenforce 0

echo "${BOLD}[*] Install Deps${NORMAL}"
rpm -iv http://dl.fedoraproject.org/pub/epel/7/x86_64/Packages/v/vconfig-1.9-16.el7.x86_64.rpm
yum install python-twisted-core perl-JSON libvirt qemu-kvm -y

echo "${BOLD}[*] Install VRS${NORMAL}"
rpm -e --nodeps openvswitch-2.9.0-3.el7.x86_64
yum localinstall nuage-openvswitch-5.3.2-28.el7.x86_64.rpm -y
service openvswitch restart
ovs-vsctl show

echo "${BOLD}[*] Configure VRS${NORMAL}"
OVS_CONF=/etc/default/openvswitch
sed -i 's/PERSONALITY.*/PERSONALITY=vrs/g' $OVS_CONF
sed -i "s/^.ACTIVE_CONTROLLER=.*/ACTIVE_CONTROLLER=${VSC1_IP}/g" $OVS_CONF
sed -i "s/^.STANDBY_CONTROLLER=.*/STANDBY_CONTROLLER=${VSC2_IP}/g" $OVS_CONF

echo "${BOLD}[*] Update OpenStack Nova${NORMAL}"
NOVA_CONF=/etc/nova/nova.conf
crudini --set "${NOVA_CONF}" DEFAULT Network_api_class nova.network.neutronv2.api.API
crudini --set "${NOVA_CONF}" DEFAULT Libvirt_vif_driver nova.virt.libvirt.vif.LibvirtGenericVIFDriver
crudini --set "${NOVA_CONF}" DEFAULT  Security_group_api neutron
crudini --set "${NOVA_CONF}" DEFAULT Firewall_driver nova.virt.firewall.NoopFirewallDriver
crudini --set "${NOVA_CONF}" neutron ovs_bridge alubr0

echo "${BOLD}[*] Update OpenStack MetaAgent${NORMAL}"
yum install python-novaclient python-httplib2 -y
rpm -vi nuage-metadata-agent-*.x86_64.rpm

echo "
METADATA_PORT=9697
NOVA_METADATA_IP=${OS_CONTROLLER}
NOVA_METADATA_PORT=8775
METADATA_PROXY_SHARED_SECRET="NuageNetworksSharedSecret"
NOVA_CLIENT_VERSION=2
NOVA_OS_USERNAME=nova
NOVA_OS_PASSWORD=${NOVA_OS_PW}
NOVA_OS_TENANT_NAME=admin
NOVA_OS_AUTH_URL=http://${OS_CONTROLLER}:5000/v3
NUAGE_METADATA_AGENT_START_WITH_OVS=true
#NOVA_REGION_NAME=regionOne
NOVA_API_ENDPOINT_TYPE=publicURL
NOVA_PROJECT_NAME=services
NOVA_USER_DOMAIN_NAME=default
NOVA_PROJECT_DOMAIN_NAME=default
IDENTITY_URL_VERSION=3
NOVA_OS_KEYSTONE_USERNAME=nova
" > /etc/default/nuage-metadata-agent

echo "${BOLD}[*] Configure Nuage Plugin${NORMAL}"
service openstack-nova-compute restart || exit 1

echo "${BOLD}[*] INSTALL COMPLETE${NORMAL}"
exit 0

