package App::NetdiscoX::Worker::Plugin::Discover::Properties;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';
use Data::Dumper;

register_worker({ phase => 'user' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;

  if ($device->model eq "ACIController"){

    info sprintf ' [%s] NetdiscoX::Properties found an ACIController - running device.layers fixup', $device->ip;
    $device->set_column( layers => "01001110" );

    schema('netdisco')->txn_do(sub {
      $device->update_or_insert(undef, {for => 'update'});
    });

  }else{
    info sprintf ' [%s] NetdiscoX::Properties - not an ACIController, ignored', $device->ip;

  }

  return Status->info("NetdiscoX Worker done");
});


true;
