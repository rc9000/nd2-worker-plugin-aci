# vim: set softtabstop=2 ts=8 sw=2 et: 
package App::NetdiscoX::Worker::Plugin::Macsuck::Nodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use App::Netdisco::Util::Device qw/get_device/;
use aliased 'App::Netdisco::Worker::Status';

use Dancer::Plugin::DBIC 'schema';
use Time::HiRes 'gettimeofday';
use Scope::Guard 'guard';
use App::NetdiscoX::Util::ACI;
use Data::Dumper;
use JSON 'encode_json';
no warnings 'uninitialized';

sub store_epg_custom_fields {
  my ($device, $epgmap) = @_;

  foreach my $leaf_ip (keys %{$epgmap}){
    foreach my $port (keys %{$epgmap->{$leaf_ip}}){

        my $portrow = schema(vars->{'tenant'})->resultset('DevicePort')->find({ ip => $leaf_ip, port => $port});
        $portrow->make_column_dirty('custom_fields');

        my @arr = sort keys %{$epgmap->{$leaf_ip}->{$port}};
        my $json_arr = encode_json \@arr;
        my $k = "epgs";

        debug sprintf ' [%s] cisco aci macsuck - store_epg %s %s : %s',  $device->ip, $leaf_ip, $port, $json_arr;

        $portrow->update({
          custom_fields => \['jsonb_set(custom_fields, ?, ?::jsonb)'  => (qq!{$k}!, $json_arr) ]
        })->discard_changes();
    
    }
  }
}

register_worker({ phase => 'main', driver => 'netconf' }, sub {

  my ($job, $workerconf) = @_;

  my $device = $job->device;

  my $device_auth = [grep { $_->{tag} eq "aci" } @{setting('device_auth')}];
  my $selected_auth = $device_auth->[0];

  my $aci = App::NetdiscoX::Util::ACI->new(
      host => $device->ip,
      port => $selected_auth->{port} ? $selected_auth->{port} : 443,
      user => $selected_auth->{user},
      password => $selected_auth->{password},
  );

  info sprintf ' [%s] cisco aci macsuck - fetching data from  %s', $device->ip, $aci->url;
  $aci->login();
 
  my $mac_arp_info = $aci->fetch_mac_arp_info();
  my $now = 'to_timestamp('. (join '.', gettimeofday) .')';
  my $n = 0;
  my $fab_devices = {};

  info sprintf ' [%s] cisco aci macsuck - updating epg participation in device_port', $device->ip, $n;
  store_epg_custom_fields($device, $mac_arp_info->{epgmap});

  info sprintf ' [%s] cisco aci macsuck - updating node table', $device->ip;
  my @dp = schema('netdisco')->resultset('DevicePort')->search(undef, {columns => [qw/ip port is_uplink remote_type/]})->all;
  my $uplinks = {};
  my $remote_types = {};
  foreach my $d (@dp){
    $uplinks->{$d->ip}->{$d->port} = $d->is_uplink ? "uplink" : "no_uplink";
    $remote_types->{$d->ip}->{$d->port} = $d->remote_type;
  }

  debug sprintf ' [%s] cisco aci macsuck - prefetched ports', $device->ip;

  foreach my $entry (@{$mac_arp_info->{nodes}}){

    unless ($fab_devices->{$entry->{switch}}){
      $fab_devices->{$entry->{switch}} = get_device($entry->{switch}) unless $fab_devices->{$entry->{switch}};
    }

    my $fab_p = $uplinks->{$entry->{switch}}->{$entry->{port}};
    my $aci_ignore_uplink_re = setting('aci_ignore_uplink_re');

    if (!$fab_p){
      debug sprintf ' [%s] cisco aci macsuck - %s fabric switch %s port %s is unknown to netdisco, skipped', 
        $device->ip, $entry->{mac}, $entry->{switch}, $entry->{port};
    
    } elsif ($fab_p eq "uplink" && $remote_types->{$entry->{switch}}->{$entry->{port}} !~ m/\Q$aci_ignore_uplink_re/){
      debug sprintf ' [%s] cisco aci macsuck - %s fabric switch %s port %s is an uplink, skipped', 
        $device->ip, $entry->{mac}, $entry->{switch}, $entry->{port};

    }else{
      debug sprintf ' [%s] cisco aci macsuck - %s fabric switch %s port %s stored',  
        $device->ip, $entry->{mac}, $entry->{switch}, $entry->{port};

      App::Netdisco::Worker::Plugin::Macsuck::Nodes::store_node(
        $entry->{switch}, $entry->{vlan}, $entry->{port}, $entry->{mac}, $now
      );
      $n++ 
    }
  }
  info sprintf ' [%s] cisco aci macsuck - stored %s node entries', $device->ip, $n;



  $aci->logout();
  return Status->done("OK");
});

true;
