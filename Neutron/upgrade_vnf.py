from keystoneauth1.identity import v3
from keystoneauth1 import session
from novaclient import client as nova_client
from neutronclient.v2_0 import client as neutron_client
import datetime
import os
import binascii
import time
import sys

class Counter:
    def start(self):
        self.start =  datetime.datetime.now()

    def stop(self):
        self.stop =  datetime.datetime.now()
        response_time = self.stop - self.start

        return str(response_time.seconds)

class Authenticate(object):
    def authenticate(self):
        auth = v3.Password(auth_url='http://#####:5000/v3',
                           username='admin',
                           password='####',
                           project_name='admin',
                           user_domain_id='default',
                           project_domain_id='default')
        self.session = session.Session(auth=auth)

class VirtualNetDevice(Authenticate):
    def __init__(self, device_id):
        self.device_id = device_id
        self.authenticate()
        self.nova = nova_client.Client("2.1",
                                       session=self.session,
                                       endpoint_type='internal' ,
                                       insecure=True)
        self.neutron = neutron_client.Client(session=self.session,
                                             endpoint_type='internal')

    def get_port_data(self, device_id):
        return [port for port in self.neutron.list_ports()['ports'] if port['device_id'] == device_id]

    def get_port_ids(self, device_id):
        return [p['id'] for p in self.get_port_data(device_id)]

    def get_device_id(self, device_name):
        instances = self.nova.servers.list()
        return [i.id for i in instances if str(i.name) == device_name]

    def remove_port_security(self, port_ids):
        for p in port_ids:
            self.neutron.update_port(p, {'port': {'security_groups': [],
                                                  'port_security_enabled':False}})

    def remove_fixed_ips(self, port_ids):
        for p in port_ids:
            self.neutron.update_port(p, {'port': {'fixed_ips': []}})

    def add_fixed_ips(self, port_id, ipaddrs)
        self.neutron.update_port(port_id, {'port': {'fixed_ips': ipaddrs}})
        
class VirtualNetDeviceUpgrade(VirtualNetDevice):
    
    MGMT_IP = '######'
    
    def __init__(self, device_id):
        super(VirtualNetDeviceUpgrade, self).__init__(device_id)

    def detach_ips(self):
        print "[*] Detaching fixed ips from device=%s" % self.device_id
        port_ids = self.get_port_ids(self.device_id)
        self.remove_fixed_ips(port_ids)

    def attach_ips(self):
        print "[*] Attaching fixed ips to device=%s" % self.device_id
        port_id = self.get_port_ids(self.device_id)[0]
        self.add_fixed_ips(port_id, [MGMT_IP])
    
    def power_off_instance(self):
        print "[*] Powering off device=%s" % self.device_id
        self.nova.servers.stop(self.device_id)

    def is_server_built(self, device_name):
        server_active = False
        while not server_active:
            instances = self.nova.servers.list()
            for i in instances:
                sys.stdout.write('#') ; sys.stdout.flush()
                if str(i.name) == device_name and i.status == 'ACTIVE':
                    sys.stdout.write('\n') ; sys.stdout.flush()
                    print "[*] Migration device built and active"
                    return True
                elif str(i.name) == device_name and i.status == 'ERROR':
                    print "[FAIL] ERROR Building instance"
                    sys.exit(1)
            time.sleep(3)

    def is_server_shutdown(self, device_id):
        print "[*] Checking device is shutdown"
        server_active = False
        while not server_active:
            instances = self.nova.servers.list()
            for i in instances:
                sys.stdout.write('#') ; sys.stdout.flush()
                if str(i.id) == device_id and i.status == 'SHUTOFF':
                    sys.stdout.write('\n') ; sys.stdout.flush()
                    print "[*] Device shutoff"
                    return True
                elif str(i.id) == device_id and i.status == 'ERROR':
                    print "[FAIL] ERROR Building instance"
                    sys.exit(1)
            time.sleep(3)

    def create_server(self, mgmt_ip=MGMT_IP):
        print "[*] Creating migration device"
        name = 'DEMO-MIGRATION-DEVICE-%s' % binascii.b2a_hex(os.urandom(5))
        config = open("/root/day0-config", "r")
        self.nova.servers.create(name=name,
                                 image='######',
                                 flavor='######',
                                 availability_zone='ZONE-B',
                                 config_drive=True,
                                 files={'/day0-config': config},
                                 nics=[{'net-id': '#######',
                                        'v4-fixed-ip': mgmt_ip},
                                       {'net-id': '######'},
                                       {'net-id': '######'}])

        if self.is_server_built(name):
            migration_device_id = self.get_device_id(name)[0]
            port_ids = self.get_port_ids(migration_device_id)
            self.remove_port_security(port_ids)

    def migrate_mass(self):
        """
        Migration method detachs IPs so that you are not limited by the remaining fixed ips left in subnet.
        This allows for mass migrations.
        """
        self.detach_ips()
        self.power_off_instance()

        self.create_server()
        if self.is_server_shutdown(self.device_id):
            print "[OK] Migration complete"
    
    def migrate_zero_downtime(self):
        """
        Migration method uses another ip from the subnet on instance startup as a temp address.
        Method allows for reduced downtime, but is limits amount of devices that can be upgraded 
        based upon available ips in subnet.
        """
        self.create_server(mgmt_ip=None)
        self.detach_ips()
        self.attach_ips()
    

if __name__ == "__main__":
    version = "%prog beta"
    program = "upgrade demo"

    c = Counter() ; c.start()

    device_id = sys.argv[1]
    option = sys.argv[2]
    netdev_upgrade = VirtualNetDeviceUpgrade(device_id)
    
    if option == 'zero':
        netdev_upgrade.migrate_zero_downtime()    
    elif option == 'mass':
        netdev_upgrade.migrate_mass()

    print "\nTOTAL TIME = %ssec(s)" % c.stop()
