# vim: set softtabstop=2 ts=8 sw=2 et: 
package App::NetdiscoX::Worker::Plugin::Arpnip::Nodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';
use App::Netdisco::Util::Node qw/check_mac store_arp/;
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';

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

  $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

  info sprintf ' [%s] cisco aci arpnip - fetching data from  %s', $device->ip, $aci->url;
  $aci->login();
 
  my $mac_arp_info = $aci->fetch_mac_arp_info();
  my $now = 'to_timestamp('. (join '.', gettimeofday) .')';
  my $n = 0;

  info sprintf ' [%s] cisco aci arpnip - updating node_ip table', $device->ip;

  my $resolved_ips = hostnames_resolve_async($mac_arp_info->{node_ips});

  #my @slice =   @ { $resolved_ips } [1,3,2];
  #$resolved_ips = \@slice;

  foreach my $entry (@$resolved_ips){

    if ($entry->{ip} && $entry->{ip} ne "0.0.0.0"){   
  
      debug sprintf ' [%s] cisco aci arpnip - store mac %s ip %s found on %s', 
        $device->ip, $entry->{node}, $entry->{ip}, $entry->{on_device};
      store_arp($entry, $now, $device->ip);
      $n++ 

    }else{
      debug sprintf ' [%s] cisco aci arpnip - ignore mac %s ip %s found on %s (zeros or empty)', 
        $device->ip, $entry->{node}, $entry->{ip}, $entry->{on_device};
    }
  }

  info sprintf ' [%s] cisco aci arpnip - processed %s node_ip entries', $device->ip, $n;
  $aci->logout();
  return Status->done("OK");
});

true;
