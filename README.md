# nd2-worker-plugin-aci

Netdisco plugin to fetch mac and arp tables from APIC (Cisco ACI SDN controllers)

## Limitations

This is a very early release. It is known to work on exactly ~~one fabric~~ two fabrics with APIC 3.2 or 4.1. You're very welcome to experiment and fork or contribute, but expect stuff to fail and support to be very limited.

## Description

This module can talk to APIC to:

* emulate the regular Netdisco SNMP-based macsuck to map fvCEp MAC entries to fabric switch ports
  * in the case of virtual port channel, map the VPC MAC relation onto the corresponding port-channels on the fabric switch
* emulate the regular Netdisco SNMP-based arpnip to store fvCEp MAC/IP pairs like normal arp table entries  
* enhance Netdisco discovery to enable L2 and L3 layers on the controller, so it is eligible for arpnip and macsuck jobs

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
    extra_worker_plugins: ['X::Macsuck::Nodes', 'X::Arpnip::Nodes', 'X::Discover::Properties']

Then for each controller, add an entry to `device_auth` 

    device_auth:
      - tag: aci
        driver: netconf
        only:
          - 10.5.199.5 
        user: 'aciuser'
        password: 'topsecret'



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

## Debugging & Troubleshooting

You can run netdisco-do with these additional variables and flags:

     NETDISCOX_EPFILTER=protpaths-1067 NETDISCOX_DUMPJSON=1 ND2_LOG_PLUGINS=1 netdisco-do macsuck -D -d 10.5.199.5 

This will produce a lot of debug output (-D), show details regarding the plugin loading process (ND2\_LOG\_PLUGINS), as well as store the JSON replies received from ACI in files in /tmp (NETDISCOX\_DUMPJSON). NETDISCOX\_EPFILTER is a regex that will be matched against the fvCEp tDn, so you can limit the run to certain objects or nodes.

Also check out the `./t` and  `./t/testdata` directories, you can run offline tests against the output produced by your fabric (with NETDISCOX\_DUMPJSON). To contribute test data, `./t/testdata/anon.pl` can be used to remove all identifying information from the files.

In case of errors like `SSL connect attempt failed error:14090086:SSL routines:ssl3_get_server_certificate:certificate verify failed at LWP/Protocol/http.pm line 50.`, either install the proper CA cert or set the environment variable `PERL_LWP_SSL_VERIFY_HOSTNAME=0` (not recommended).




