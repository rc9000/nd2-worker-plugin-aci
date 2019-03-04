# vim: set softtabstop=2 ts=8 sw=2 et: 
package App::NetdiscoX::Worker::Plugin::Macsuck::Nodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
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

  $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

  info sprintf ' [%s] cisco aci macsuck - fetching data from  %s', $device->ip, $aci->url;
  $aci->login();
 
  my $mac_arp_info = $aci->fetch_mac_arp_info();
  my $now = 'to_timestamp('. (join '.', gettimeofday) .')';
  my $n = 0;

  info sprintf ' [%s] cisco aci macsuck - updating node table', $device->ip;
  foreach my $entry (@{$mac_arp_info->{nodes}}){
    App::Netdisco::Worker::Plugin::Macsuck::Nodes::store_node(
      $entry->{switch}, $entry->{vlan}, $entry->{port}, $entry->{mac}, $now
    );
    $n++ 
  }

  info sprintf ' [%s] cisco aci macsuck - stored %s node entries', $device->ip, $n;
  $aci->logout();
  return Status->done("OK");
});

true;
