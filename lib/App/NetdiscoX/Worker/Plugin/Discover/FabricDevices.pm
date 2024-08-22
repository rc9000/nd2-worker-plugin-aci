# vim: set softtabstop=2 ts=8 sw=2 et: 
package App::NetdiscoX::Worker::Plugin::Discover::FabricDevices;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';
use App::NetdiscoX::Util::ACI;
use Data::Dumper;

register_worker({ phase => 'user', priority => 100  }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;

  if ($device->model eq "ACIController"){
    info sprintf ' [%s] NetdiscoX::FabricDevices - updating custom_fields for devices managed by this APIC', $device->ip;

    my $device_auth = [grep { $_->{tag} eq "aci" } @{setting('device_auth')}];
    my $selected_auth = $device_auth->[0];

    my $aci = App::NetdiscoX::Util::ACI->new(
      host => $device->ip,
      port => $selected_auth->{port} ? $selected_auth->{port} : 443,
      user => $selected_auth->{user},
      password => $selected_auth->{password},
      https_hostname => $selected_auth->{https_hostname} ? $selected_auth->{https_hostname} : $device->ip
    );
    $aci->login();
    discover_topsystems($device, $aci);
    discover_interfaces($device, $aci, "l1PhysIf");
    discover_interfaces($device, $aci, "pcAggrIf");
  }else{
    info sprintf ' [%s] NetdiscoX::Properties - not an ACIController, ignored', $device->ip;

  }

  return Status->info("NetdiscoX Worker done");
});

sub discover_topsystems {
  my ($device, $aci) = @_;
  my $nodes =  $aci->aciget($aci->url() . "/node/class/topSystem.json?rsp-prop-include=all");
  my $custom_cnt = 0;

  foreach my $n (@{$nodes->{'content'}->{'imdata'}}){
    my $att = $n->{'topSystem'}->{'attributes'};

    my $nodeinfo = $aci->nodeinfo($att->{id}, $nodes->{'content'}->{'imdata'});
    my $topsystem_device_ip = $nodeinfo->{'mgmtAddr'};

    my $store_attrs = { 
      'APIC' => $device->ip,
      'topSystem_dn' => $att->{'dn'},
      'topSystem_role' => $att->{'role'},
    };

    debug sprintf ' [%s] updating custom_fields for topSystem %s dn %s', $device->ip, $topsystem_device_ip, $att->{'dn'};

    my $row = schema(vars->{'tenant'})->resultset('Device')->find($topsystem_device_ip);
    if (!$row){
      info sprintf ' [%s] topSystem %s does not seem to be known in netdisco.device table, skipping', $device->ip, $topsystem_device_ip;
      next;
    }

    $row->make_column_dirty('custom_fields');

    foreach my $k (keys %$store_attrs){
      my $val = '"'.$store_attrs->{$k}.'"';
      $row->update({
        custom_fields => \['jsonb_set(custom_fields, ?, ?::jsonb)'  => (qq!{$k}!, $val) ]
      })->discard_changes();
      $custom_cnt++;
    }

  }

  info sprintf ' [%s] updated %s attributes of %s devices', $device->ip, $custom_cnt,  scalar(@{$nodes->{'content'}->{'imdata'}});

}

sub get_fexmap {
  my ($device, $aci) = @_;

  my $fexmap = {};

  my $fexes =  $aci->aciget_paged($aci->url() . "/node/class/eqptExtCh.json");
  foreach my $p (@{$fexes->{content}}){
    foreach my $n (@{$p->{'imdata'}}){
      my $att = $n->{'eqptExtCh'}->{'attributes'};
      my $fexdescr = sprintf 'fex %s %s %s serial %s', $att->{'dn'}, $att->{'model'}, $att->{'descr'}, $att->{'ser'}; 
      $att->{'fexdescr'} = $fexdescr;
      debug sprintf ' [%s] found %s', $device->ip, $fexdescr;
      $fexmap->{$att->{'dn'}} = $att;
    }
  }

  return $fexmap;

}

sub discover_interfaces {
  my ($device, $aci, $class) = @_;
  my $device_auth = [grep { $_->{tag} eq "aci" } @{setting('device_auth')}];
  my $selected_auth = $device_auth->[0];
  #my $class = "pcAggrIf";
  my $fexmap = get_fexmap($device, $aci);
  my $interfaces =  $aci->aciget_paged($aci->url() . "/node/class/$class.json");
  my $devicecache = {};

  foreach my $p (@{$interfaces->{content}}){
    foreach my $n (@{$p->{'imdata'}}){
      my $att = $n->{$class}->{'attributes'};

      # topology/pod-1/node-1008/sys/aggr-[po4] -> topology/pod-1/node-1008/sys 
      # topology/pod-1/node-1015/sys/phys-[eth1/4] -> topology/pod-1/node-1015/sys 
      (my $system_dn = $att->{'dn'}) =~ s!/sys/(phys|aggr)-.*$!/sys!;
      # topology/pod-1/node-1008/sys/aggr-[po4] -> po4
      (my $short_port = $att->{'dn'}) =~ s!.*\[(.*)\]$!$1!;

      my $store_attrs = { 
        $class.'_dn' => $att->{'dn'},
        $class.'_name' => $att->{'name'},
        #$class.'_descr' => $att->{'descr'},
        #'dn' => $att->{'dn'}
      };

      # check if this is a port on a fex, i.e. topology/pod-1/node-1094/sys/phys-[eth102/1/5] -> topology/pod-1/node-1094/sys/extch-102 exists
      (my $fexdn = $att->{'dn'}) =~ s!/sys/phys-.eth(\d+)/\d+/\d+.!/sys/extch-$1!;
      my $fexattr = $fexmap->{$fexdn};
      if ($fexattr->{'fexdescr'}){
        $store_attrs->{'eqptExtCh'} = $fexattr->{'fexdescr'};
        debug sprintf ' [%s] storing FEX info (eqptExtCh): %s on %s', $device->ip, $att->{'dn'}, $fexattr->{'fexdescr'} ;
      }

      debug sprintf ' [%s] updating custom_fields for %s %s name: %s top: %s', $device->ip, $class, $att->{'dn'}, $att->{'name'}, $system_dn;

      # now we need to find the fabric switch to update
      my $devicerow = $devicecache->{$device->ip}->{$system_dn};

      if (! $devicerow){
        #debug sprintf ' [%s] fetching row %s %s', $device->ip, $device->ip, $system_dn;
        $devicerow = schema(vars->{'tenant'})->resultset('Device')->search({ qq!custom_fields->>'topSystem_dn'! => $system_dn, qq!custom_fields->>'APIC'! => $device->ip});
        $devicecache->{$device->ip}->{$system_dn} = $devicerow;
      }else{
        #debug sprintf ' [%s] cached row %s %s', $device->ip, $device->ip, $system_dn;
      }

      unless ($devicerow->first){
        info sprintf ' [%s] topSystem %s does not seem to be known in netdisco.device table, skipping', $device->ip, $system_dn;
        next;
      }

      my $device_pk = $devicerow->first->id;
      my $long_port = $aci->long_port($short_port);
      #debug sprintf ' [%s] netdisco.device_port entry for dn is %s %s', $device->ip, $device_pk, $long_port;

      my $portrow = schema(vars->{'tenant'})->resultset('DevicePort')->find({ ip => $device_pk, port => $long_port});
      $portrow->make_column_dirty('custom_fields');

      foreach my $k (keys %$store_attrs){
        my $val = '"'.$store_attrs->{$k}.'"';
        $portrow->update({
          custom_fields => \[ 'jsonb_set(custom_fields, ?, ?::jsonb)'  => (qq!{$k}!, $val) ]
        })->discard_changes();
      }
    }
  }
}


true;
