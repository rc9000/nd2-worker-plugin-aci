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

  info sprintf ' [%s] cisco aci macsuck - updating node table', $device->ip;

  my @dp = schema('netdisco')->resultset('DevicePort')->search(undef, {columns => [qw/ip port is_uplink/]})->all;
  my $uplinks = {};
  foreach my $d (@dp){
    $uplinks->{$d->ip}->{$d->port} = $d->is_uplink ? "uplink" : "no_uplink";
  }

  debug sprintf ' [%s] cisco aci macsuck - prefetched ports', $device->ip;

  foreach my $entry (@{$mac_arp_info->{nodes}}){

    unless ($fab_devices->{$entry->{switch}}){
      $fab_devices->{$entry->{switch}} = get_device($entry->{switch}) unless $fab_devices->{$entry->{switch}};
    }

    my $fab_p = $uplinks->{$entry->{switch}}->{$entry->{port}};

    if (!$fab_p){
      debug sprintf ' [%s] cisco aci macsuck - %s fabric switch %s port %s is unknown to netdisco, skipped', 
        $device->ip, $entry->{mac}, $entry->{switch}, $entry->{port};
    
    } elsif ($fab_p eq "uplink"){
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
