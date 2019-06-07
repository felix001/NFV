#!/usr/bin/env bash
# VSP 5.3.2

# Variables
VSD_IP=172.29.236.184
KEYSTONE_PW=$(crudini --get /etc/nova/nova.conf keystone_authtoken password)
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# pw for vrs compute install script
echo "Note: Keystone PW=${KEYSTONE_PW}"

# check VSD user created
echo -n "${BOLD}Ensure VSD user (cmsuser:cmsuser) is created. Continue (y/n)?${NORMAL}"
read answer
if [ "$answer" != "${answer#[Nn]}" ] ;then
    exit 1
fi

echo "${BOLD}[*] Install crudini${NORMAL}"
easy_install crudini

echo "${BOLD}[*] Disable SELinux${NORMAL}"
sed -i 's/SELINUX=.*$/SELINUX=disabled/g' /etc/selinux/config
setenforce 0

echo "${BOLD}[*] Stop Services${NORMAL}"
systemctl stop neutron-dhcp-agent.service
systemctl stop neutron-l3-agent.service
systemctl stop neutron-metadata-agent.service
systemctl stop neutron-openvswitch-agent.service
systemctl stop neutron-netns-cleanup.service
systemctl stop neutron-ovs-cleanup.service
systemctl stop neutron-server.service

echo "${BOLD}[*] Disable Services${NORMAL}"
systemctl disable neutron-dhcp-agent.service
systemctl disable neutron-l3-agent.service
systemctl disable neutron-metadata-agent.service
systemctl disable neutron-openvswitch-agent.service
systemctl disable neutron-netns-cleanup.service
systemctl disable neutron-ovs-cleanup.service

echo "${BOLD}[*] Install RPMs${NORMAL}"
rpm -iv nuage-openstack-horizon-11.0.0-5.3.2_20_nuage.noarch.rpm
rpm -iv nuage-openstack-neutron-10.0.0-5.3.2_20_nuage.noarch.rpm
rpm -iv nuage-openstack-neutronclient-6.1.0-5.3.2_20_nuage.noarch.rpm
rpm -iv nuage-nova-extensions-15.0.0-5.3.2_20_nuage.noarch.rpm

echo "${BOLD}[*] Update OpenStack Neutron${NORMAL}"
NEUTRON_CONF=/etc/neutron/neutron.conf
crudini --set "${NEUTRON_CONF}" DEFAULT service_plugins "NuageL3, NuageAPI, NuagePortAttributes"
crudini --set "${NEUTRON_CONF}" DEFAULT core_plugin "ml2"

echo "${BOLD}[*] Update OpenStack ML2${NORMAL}"
ML2_INI=/etc/neutron/plugins/ml2/ml2_conf.ini
crudini --set "${ML2_INI}" ml2 mechanism_drivers nuage
crudini --set "${ML2_INI}" ml2 extension_drivers "nuage_subnet, nuage_port, port_security"

echo "${BOLD}[*] Configure Nuage Plugin${NORMAL}"
mkdir -p /etc/neutron/plugins/nuage/
rm -rf /etc/neutron/plugin.ini
ln -s /etc/neutron/plugins/nuage/nuage_plugin.ini /etc/neutron/plugin.ini
echo "
[RESTPROXY]
# Desired Name of VSD Organization/Enterprise to use when net-partition
# is not specified
default_net_partition_name = OpenStack_default
# Hostname or IP address and port for connection to VSD server
server = $VSD_IP:8443
# VSD Username and password for OpenStack plugin connection
# User must belong to CSP Root group and CSP CMS group
serverauth = cmsuser:cmsuser
nuage_fip_underlay = True
### Do not change the below options for standard installs
organization = csp
auth_resource = /me
serverssl = True
base_uri = /nuage/api/v5_0
cms_id =
[PLUGIN]
default_allow_non_ip = True" > /etc/neutron/plugins/nuage/nuage_plugin.ini

echo "${BOLD}[*] Update OpenStack Nova${NORMAL}"
NOVA_CONF=/etc/nova/nova.conf
crudini --set "${NOVA_CONF}" DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
crudini --set "${NOVA_CONF}" DEFAULT use_neutron True
crudini --set "${NOVA_CONF}" neutron ovs_bridge alubr0
crudini --set "${NOVA_CONF}" libvirt vif_driver nova.virt.libvirt.vif.LibvirtGenericVIFDriver

echo "${BOLD}[*] Create CMD ID${NORMAL}"
mkdir -p openstack-upgrade
tar xzf nuage-openstack-upgrade-5.3.2-20.tar.gz -C openstack-upgrade/
cd openstack-upgrade
python generate_cms_id.py --config-file /etc/neutron/plugin.ini || exit 1

echo "${BOLD}[*] Update OpenStack Horizon${NORMAL}"
ALIAS_UPDATE='Alias /dashboard/static/nuage "/usr/lib/python2.7/site-packages/nuage_horizon/static"'
sed -i "s|Alias declarations.*DocumentRoot|&\n  $ALIAS_UPDATE|g" /etc/httpd/conf.d/15-horizon_vhost.conf

sed -i "s/HORIZON_CONFIG = {/&\n\    'customization_module\'\: \'nuage_horizon.customization\'\,/g" \
    /usr/share/openstack-dashboard/openstack_dashboard/local/local_settings.py

sed '/Directory>/r'<(
echo "  <Directory \"/usr/lib/python2.7/site-packages/nuage_horizon\">"
echo "   Options FollowSymLinks"
echo "   AllowOverride None"
echo "   Require all granted"
echo "  </Directory>"
) -i -- /etc/httpd/conf.d/15-horizon_vhost.conf


echo "${BOLD}[*] Update Neutron DB${NORMAL}"
neutron-db-manage --config-file /etc/neutron/neutron.conf \
                  --config-file /etc/neutron/plugins/nuage/nuage_plugin.ini \
                  upgrade head

echo "${BOLD}[*] Final Services Restart${NORMAL}"
NEUTRON_SERVICE_SERVICE=/usr/lib/systemd/system/neutron-server.service
crudini --set "${NEUTRON_SERVICE_SERVICE}" Service ExecStart "/usr/bin/neutron-server --config-file /usr/share/neutron/neutron-dist.conf --config-dir /usr/share/neutron/server --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugin.ini  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini --config-dir /etc/neutron/conf.d/common --config-dir /etc/neutron/conf.d/neutron-server --log-file /var/log/neutron/server.log"
set -v
service openstack-nova-api restart || exit 1
service openstack-nova-cert restart || exit 1
service openstack-nova-consoleauth restart || exit 1
service openstack-nova-scheduler  restart || exit 1
service openstack-nova-conductor restart || exit 1
service openstack-nova-novncproxy restart || exit 1
service httpd restart || exit 1
service neutron-server restart || exit 1
set +v
echo "${BOLD}[*] INSTALL COMPLETE${NORMAL}"
exit 0
