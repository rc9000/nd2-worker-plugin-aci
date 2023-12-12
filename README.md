# nd2-worker-plugin-aci

Netdisco plugin to fetch mac and arp tables from APIC (Cisco ACI SDN controllers)

## Limitations

Tested or reported to work on APIC 3.2, 4.x and up to 5.2(2f). You're very welcome to experiment and fork or contribute, but expect stuff to fail and support to be very limited. The current release requires Netdisco 2.062003 or newer.

## Description

This module can talk to APIC to:

* emulate the regular Netdisco SNMP-based macsuck to map fvCEp MAC entries to fabric switch ports
  * in the case of virtual port channel, map the VPC MAC relation onto the corresponding port-channels on the fabric switch
* emulate the regular Netdisco SNMP-based arpnip to store fvCEp MAC/IP pairs like normal arp table entries  
* enhance Netdisco discovery to enable L2 and L3 layers on the controller, so it is eligible for arpnip and macsuck jobs
* populate Netdisco `custom_fields` with ACI-specifc attributes

## Installation

### Prerequisites

    cpanm JSON LWP::Protocol::https File::Slurp URL::Encode REST::Client Regexp::Common

The installed Netdisco version should be at least 2.039031.

### Clone the this git repository

Can be in any location, e.g: 

    cd /home/netdisco 
    git clone https://github.com/rc9000/nd2-worker-plugin-aci.git

### Configure Netdisco

Add the following settings to `deployment.yml` to activate the extension

    include_paths: [ '/home/netdisco/nd2-worker-plugin-aci/lib' ]
    extra_worker_plugins: ['X::Macsuck::Nodes', 'X::Arpnip::Nodes', 'X::Discover::Properties', 'X::Discover::FabricDevices']

Then for each controller, add an entry to `device_auth` 

    device_auth:
      - tag: aci
        driver: netconf
        only:
          - 10.5.199.5 
        user: 'aciuser'
        password: 'topsecret'

The setting `aci_ignore_uplink_re` allows to specify a regex matching a remote_type. If the match succeeds, macsuck will collect entries from the port even if it is discovered as uplink. To see the current values in the database:

     $ netdisco-do psql
    netdisco=> select ip, port, remote_type from device_port where ip =  '10.219.2.76' and remote_type is not null order by port;
    
         ip      |      port       |                          remote_type
    -------------+-----------------+----------------------------------------------------------------
     10.219.2.76 | Ethernet1/2     | NetApp HCI H410S-1 Storage Node, Release Element Software 12.7
     10.219.2.76 | Ethernet1/51    | topology/pod-1/node-101
     10.219.2.76 | Ethernet1/52    | topology/pod-1/node-102
     10.219.2.76 | Ethernet103/1/6 | NetApp HCI H410S-1 Storage Node, Release Element Software 12.7

Some examples to apply a regex to these:

```
# Treat FlexFabric and NetApp trunks as connection to nodes:
aci_ignore_uplink_re: "(NetApp|FlexFabric)"

# Only treat ACI internal connections as uplinks:
aci_ignore_uplink_re: "^(?!topology).*$"

````

To display some gathered ACI attributes also in the Netdisco UI, enable these custom fields:

    custom_fields:
      device:
        - editable: false
          name: APIC
        - editable: false
          name: topSystem_dn
        - editable: false
          name: topSystem_role
      device_port:
        - editable: false
          name: l1PhysIf_dn
        - editable: false
          name: l1PhysIf_name
        - editable: false
          name: pcAggrIf_dn
        - editable: false
          name: pcAggrIf_name
        - editable: false
          name: epgs
    

### Controller Configuration

Since we'll want to keep the controller as a managed device in Netdisco, it needs to respond to SNMP and be successfully discovered. Also, all the switches in the fabric must be discovered in Netdisco as normal SNMP-based devices, so that the mac and arp entries can be mapped to the correct device port. See the documentation at https://github.com/netdisco/netdisco/ if unsure how to achieve this. 

## Running, Validation 

To test if everything works, try a manual disovery. It should look like this:

    $ netdisco-do discover -d 10.5.199.5
    [7888] 2019-02-28 20:17:38  info App::Netdisco version 2.039031 loaded.
    [7888] 2019-02-28 20:17:39  info discover: [10.5.199.5] started at Thu Feb 28 21:17:39 2019
    [7888] 2019-02-28 20:17:41  info  [10.5.199.5] NetdiscoX::Properties found an ACIController - running device.layers fixup
    [7888] 2019-02-28 20:17:41  info discover: finished at Thu Feb 28 21:17:41 2019
    [7888] 2019-02-28 20:17:41  info discover: status done: Ended discover for 10.5.199.5

As a next step, manual arpnip and macusck can be run:

    $ netdisco-do macsuck -d 10.5.199.5
    [9379] 2019-02-28 20:21:34  info App::Netdisco version 2.039031 loaded.
    [9379] 2019-02-28 20:21:35  info macsuck: [10.5.199.5] started at Thu Feb 28 21:21:35 2019
    [9379] 2019-02-28 20:21:35  info  [10.5.199.5] cisco aci macsuck - fetching data from  https://10.5.199.5:443/api
    [9379] 2019-02-28 20:21:38  info  [10.5.199.5] cisco aci macsuck - updating node table
    [9379] 2019-02-28 20:22:09  info  [10.5.199.5] cisco aci macsuck - stored 2762 node entries
    [9379] 2019-02-28 20:22:10  info macsuck: finished at Thu Feb 28 21:22:10 2019
    [9379] 2019-02-28 20:22:10  info macsuck: status done: OK


    $ netdisco-do arpnip -d 10.5.199.5
    [11310] 2019-02-28 20:23:24  info App::Netdisco version 2.039031 loaded.
    [11310] 2019-02-28 20:23:25  info arpnip: [10.5.199.5] started at Thu Feb 28 21:23:25 2019
    [11310] 2019-02-28 20:23:25  info  [10.5.199.5] cisco aci arpnip - fetching data from  https://10.5.199.5:443/api
    [11310] 2019-02-28 20:23:26  info  [10.5.199.5] cisco aci arpnip - updating node_ip table
    [11310] 2019-02-28 20:23:29  info  [10.5.199.5] cisco aci arpnip - processed 0 node_ip entries
    [11310] 2019-02-28 20:23:30  info arpnip: finished at Thu Feb 28 21:23:30 2019
    [11310] 2019-02-28 20:23:30  info arpnip: status done: OK

Once this has proven successful, Netdisco will poll the controller in exactly the same way as an SNMP based router or switch, according to the schedule settings.  

## Storing device and port `dn`, EPG and other ACI attributes

 * when running `discover`, the `Discover::FabricDevices` module will store various ACI information in the `custom_fields` structure of Netdisco 
 * `macsuck` also stores the EPG an interface participates in, in the `device_port.custom_fields.epgs` array


## Debugging & Troubleshooting

You can run netdisco-do with these additional variables and flags:

     NETDISCOX_EPFILTER=protpaths-1067 NETDISCOX_DUMPJSON=1 ND2_LOG_PLUGINS=1 netdisco-do macsuck -D -d 10.5.199.5 

This will produce a lot of debug output (-D), show details regarding the plugin loading process (ND2\_LOG\_PLUGINS), as well as store the JSON replies received from ACI in files in /tmp (NETDISCOX\_DUMPJSON). NETDISCOX\_EPFILTER is a regex that will be matched against the fvCEp tDn, so you can limit the run to certain objects or nodes.

Also check out the `./t` and  `./t/testdata` directories, you can run offline tests against the output produced by your fabric (with NETDISCOX\_DUMPJSON). To contribute test data, `./t/testdata/anon.pl` can be used to remove all identifying information from the files.

In case of errors like `SSL connect attempt failed error:14090086:SSL routines:ssl3_get_server_certificate:certificate verify failed at LWP/Protocol/http.pm line 50.`, either install the proper CA cert or set the environment variable `PERL_LWP_SSL_VERIFY_HOSTNAME=0` (not recommended).




