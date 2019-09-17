# vim: set softtabstop=2 ts=8 sw=2 et: 
package App::NetdiscoX::Util::ACI;
use Data::Dumper;
use REST::Client;
use Dancer ':syntax';
use JSON qw(encode_json decode_json);
use File::Slurp;
use URL::Encode ':all';
use Hash::Merge qw(merge);

use Moo;
use namespace::clean;

has port => (
  is  => 'rw',
  isa => sub { die "$_[0] is impossilbe" unless $_[0] < 65000 },
  default => sub { return 443 },
);

around 'port' => sub {
  my $orig = shift;
  return $orig->(@_) + 0;
};

has [qw(host user password)] => (
  is => 'rw'
);

sub url {
  my $self = shift;
  return "https://" . $self->{host} .  ":" . $self->{port} . "/api";
}

sub nodeinfo {
  my ($self, $id, $nodes) = @_;
  my @matches = grep { $_->{'topSystem'}->{attributes}->{id} == $id } @{$nodes};

  # relevant attributes that map to netdisco
    # device.ip is 'oobMgmtAddr' => '10.17.0.5'
    # device.name is 'name' => 'v02sw0102-za'
  return $matches[0]->{topSystem}->{attributes};

}

sub long_port {
  # apparently the REST api uses short (eth1/2) names always while all the 
  # snmp ifname/ifdescr are set to the long name (Ethernet1/2)
  my ($self, $shortport) = @_;

  if ($shortport =~ /^po(\d+)/){
    return "port-channel$1";
  }elsif ($shortport =~ /^eth(.*)/){
    return "Ethernet$1";
  }else{
    return $shortport;
  }

}

sub read_info_from_json {
  my ($self, $fvcep, $topSystem, $aggr) = @_;

  my $resp = decode_json($fvcep);
  my $tsj = decode_json($topSystem);
  my $aggrj = decode_json($aggr);

  my $ts = $tsj->{imdata};
  my @node_records; 
  my @nodeip_records; 

  foreach my $d (@{$resp->{imdata}}){
    my $dn = $d->{fvCEp}->{attributes}->{dn};
    my $mac = $d->{fvCEp}->{attributes}->{mac};
    my $ip = $d->{fvCEp}->{attributes}->{ip};
    my $vlan = $d->{fvCEp}->{attributes}->{encap} ? $d->{fvCEp}->{attributes}->{encap} : 0;
    $vlan =~ s/vlan-//;

    my @child_tdns = map { $_->{fvRsCEpToPathEp}->{attributes}->{tDn} } @{$d->{fvCEp}->{children}};
    
    foreach my $c (@child_tdns){

      next unless $c;

      if ($c =~ m!topology/pod-(\d+)/paths-(\d+)/pathep-\[(.*?)\]!){

        my $nodeinfo = $self->nodeinfo($2, $ts) ;
        debug sprintf ' [%s] NetdiscoX::Util::ACI mac_arp_info - '
          .'pod %s node %s port %s mac %s vlan %s arpip %s devname %s devip %s', 
          $self->host, $1, $2, $3, $mac, $vlan, $ip, $nodeinfo->{name}, $nodeinfo->{oobMgmtAddr};
        my $port = $self->long_port($3); 
        push(@node_records, {switch => $nodeinfo->{oobMgmtAddr}, port => $port, vlan => $vlan, mac => $mac});
        push(@nodeip_records, {on_device => $nodeinfo->{oobMgmtAddr}, node => $mac, ip => $ip});

      }elsif ($c =~ m!topology/pod-(\d+)/protpaths-(\d+)-(\d+)/pathep-\[(.*?)\]$!){

        my $nodeinfos = [$self->nodeinfo($2, $ts),  $self->nodeinfo($3, $ts)];
        my $vpc = $4;
        my $pod = $1;
        foreach my $n (@{$nodeinfos}){

          my $id = $n->{id};
          push(@nodeip_records, {on_device => $n->{oobMgmtAddr}, node => $mac, ip => $ip});


          # find the infraRsAccBndlGrpToAggrIf block for this node id and VPC
          my $tdn_re = qr!topology/pod-\d+/node-$id/sys/aggr!; 
          my $dn_re = qr!topology/pod-\d+/node-$id/local/.*/accbundle-$vpc/!; 
          #print Dumper { nodei=>$n,  tdn=> $tdn_re, dn=> $dn_re };
          my @vpc_node_agg = grep { 
            $_->{infraRsAccBndlGrpToAggrIf}->{attributes}->{tDn} =~ m!$tdn_re!  
            && $_->{infraRsAccBndlGrpToAggrIf}->{attributes}->{dn} =~ m!$dn_re!
          } @{$aggrj->{imdata}};

          if (@vpc_node_agg == 1){
            # we found one matching po interface for the VPC on this node
            my $port =  $self->long_port($vpc_node_agg[0]->{infraRsAccBndlGrpToAggrIf}->{attributes}->{tSKey});
            debug sprintf ' [%s] NetdiscoX::Util::ACI mac_arp_info - '
              .'pod %s node %s port %s mac %s vlan %s arpip %s devname %s devip %s', 
              $self->host, $pod, $id, $vpc." on ". $port, $mac, $vlan, $ip, $n->{name}, $n->{oobMgmtAddr};
            push(@node_records, {switch => $n->{oobMgmtAddr}, port => $port, vlan => $vlan, mac => $mac});

          }else {
            warning sprintf ' [%s] NetdiscoX::Util::ACI mac_arp_info - VPC %s nodeid %s - error locating port-channel'."\n", $self->host, $vpc, $id; 
          }
        }

      }else{
        warning sprintf ' [%s] NetdiscoX::Util::ACI mac_arp_info - ignore unhandled fvCEp tDn %s'."\n", $self->host, $c; 
      }
    }
  }

  return { nodes => \@node_records, node_ips => \@nodeip_records };
}

sub fetch_mac_arp_info {
  my ($self) = @_;

  my $nodes =  $self->aciget($self->url() . "/node/class/topSystem.json");
  my $aggr =  $self->aciget($self->url() . "/node/class/infraRsAccBndlGrpToAggrIf.json");

  my $pagenum = 0;
  my $pagesize = 50000;
  my $get_more_pages = 1;
  my @pages = ();
  my $status = 0;

  while ($get_more_pages){

    my $ret = $self->aciget($self->url() . "/node/class/fvCEp.json?rsp-subtree=full&"
      ."rsp-subtree-class=fvCEp,fvRsCEpToPathEp,fvIp&"
      ."order-by=fvCEp.dn&page-size=$pagesize&page=$pagenum");

    debug sprintf ' [%s] NetdiscoX::Util::ACI - fetched fvCEp page %s with pagesize %s, total records %s', 
      $self->host, $pagenum, $pagesize, $ret->{content}->{totalCount};
    push(@pages, $ret);

    if ((($pagenum + 1) * $pagesize) < $ret->{content}->{totalCount}){
      $pagenum++;
    }else{
      $get_more_pages = 0;  
    }
  }

  my $mergerec = {};
  foreach my $r (@pages){
    $mergerec = merge($mergerec, $r);
  }

  debug sprintf ' [%s] NetdiscoX::Util::ACI - merged imdata[] contains %s records', 
    $self->host, (scalar @{$mergerec->{content}->{imdata}});
  my $mergejson  = JSON->new->pretty->encode($mergerec->{content});

  return $self->read_info_from_json($mergejson, $nodes->{content_json}, $aggr->{content_json}); 
}


sub login {
  my ($self) = @_;
  my $data = { aaaUser => { attributes => { name => $self->user , pwd => $self->password }}};
  my $dataj = encode_json($data);
  my $url = $self->url() . "/aaaLogin.json";
  debug sprintf ' [%s] NetdiscoX::Util::ACI - posting %s to url %s', $self->host, $dataj, $url;

  $self->{r} = REST::Client->new();
  $self->{r}->POST($url, $dataj);
  my $replyj = $self->{r}->responseContent();
  my $code = $self->{r}->responseCode();

  if ($code == 200){
    debug sprintf ' [%s] NetdiscoX::Util::ACI - http %s reply %s', $self->host, $code, $replyj;
    my $reply = decode_json($replyj);
    my $token = $reply->{imdata}->[0]->{aaaLogin}->{attributes}->{token};
    debug sprintf ' [%s] NetdiscoX::Util::ACI - token %s', $self->host, $token;
    $self->{token} = $token;
    return true;
  }else{
    error sprintf ' [%s] NetdiscoX::Util::ACI - http %s reply %s', $self->host, $code, $replyj;
    return undef;
  }
}

sub aciget { 
  my ($self, $url) = @_;
  my $ch = { "Cookie" => "APIC-Cookie=".$self->{token} };
  $self->{r}->GET($url, $ch);

  debug sprintf ' [%s] NetdiscoX::Util::ACI - http %s get %s', $self->host,  $self->{r}->responseCode(), $url;
  my $decoded = decode_json($self->{r}->responseContent());

  if ($ENV{NETDISCOX_DUMPJSON}){
    my $fn = "/tmp/" . url_encode($url); 
    my $formatted = JSON->new->pretty->encode($decoded);
    write_file($fn, $formatted);
    debug sprintf ' [%s] NetdiscoX::Util::ACI - dumped response in %s', $self->host, $fn;
  }

  return { status => $self->{r}->responseCode(), content =>  $decoded, content_json => $self->{r}->responseContent()};

}

sub logout {
  my ($self) = @_;
  my $url = $self->url() . "/aaaLogout.json";
  my $ans = $self->aciget($url);
  debug sprintf ' [%s] NetdiscoX::Util::ACI - logout', $self->host;
}

1;
