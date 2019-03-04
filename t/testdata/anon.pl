#!/usr/bin/perl
#

# This script can anonymize the JSON testcases in this project
# run as anon.pl < input.json > output.json
# Will print all replacements on stderr
# See the $salt comment below and use a personal value.
#
# Tested on fvCEp, topSystem and infraRsAccBndlGrpToAggrIf output, but no
# warranties as usual

use warnings;
use strict;
use Digest::SHA 'sha256_hex'; 
use Regexp::Common qw /net/;;

my $ln = 1;

# $salt is a personal pick of 6x2 characters out of a sha256 that will make up
# anoymized object names, macs an IPs. Do not use the default if you want your 
# anonymization to be harder to reverse (especially the macs are easy to brute force)
my $salt = $ENV{ANON_PL_SALT} ? $ENV{ANON_PL_SALT} 
    : "(..)..(..)(..)..................(..)............................(..)(..)....";

while(<STDIN>){
    chomp;

    $_ = anon_mac($_);
    $_ = anon_vpc($_);
    $_ = anon_obj("tn",$_);
    $_ = anon_obj("ap",$_);
    $_ = anon_obj("epg",$_);
    $_ = anon_topsys("fabricDomain",$_);
    $_ = anon_topsys("serial",$_);
    $_ = anon_topsys("name",$_);
    $_ = anon_ipv4($_);
    $_ = anon_ipv6($_);

    print $_, "\n";
    $ln++;    

}

sub anon_ipv6{
    my ($line) = @_;
    if ($line =~ m!($RE{net}{IPv6}{-sep => ':'}{-style => 'HeX'})!){
        my $orig = $1;
        my $digest = uc(sha256_hex($orig));
        $digest =~ m/^$salt$/;
        my $anon = lc("fd92:43d9::$1$1:$3$4:$5$2");
        print STDERR "line $ln anon_ipv6 $orig $anon\n";
        $line =~ s/$orig/$anon/;
    }

    return $line;

}



sub anon_ipv4{
    my ($line) = @_;
    if ($line =~ m!(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})!){
        my $orig = $1;
        return $_[0] if $orig =~ m/^0.0.0.0/;
        my $digest = uc(sha256_hex($orig));
        $digest =~ m/^$salt$/;
        my $anon = join(".", (hex "0x$5", hex "0x$1", hex "0x$2", hex "0x$4")); 
        print STDERR "line $ln anon_ipv4 $orig $anon\n";
        $line =~ s/$orig/$anon/;
    }

    return $line;

}

sub anon_topsys {
    my ($key, $line) = @_;

    if ($line =~ m!$key" : "(.*)"!){
        my $orig = $1;
        my $digest = uc(sha256_hex($orig));
        $digest =~ m/^$salt$/;
        my $anon = "$key$5$2-$3$3"; 
        print STDERR "line $ln anon_topsys $orig $anon\n";
        $line =~ s/$orig/$anon/;
    }

    return $line;
}

sub anon_vpc {
    my ($line) = @_;
    if ($line =~ m!pathep-\[(.*?)\]! || $line =~ m!accbundle-(.*?)/! ){
        my $orig = $1;
        return $line if $orig =~ /eth/;
        my $digest = uc(sha256_hex($orig));
        $digest =~ m/^$salt$/;
        my $anon = "VPC_$3$2_$5"; 
        print STDERR "line $ln anon_vpc $orig $anon\n";
        $line =~ s/$orig/$anon/;
    }

    return $line;

}

sub anon_obj {
    my ($prefix, $line) = @_;
    if ($line =~ m!($prefix-.*?)[/"]!){
        my $orig = $1;
        my $digest = uc(sha256_hex($orig));
        $digest =~ m/^$salt$/;
        my $anon = "$prefix-$3$2$6"; 
        print STDERR "line $ln anon_obj $orig $anon\n";
        $line =~ s/$orig/$anon/;
    }

    return $line;

}

sub anon_mac {
    if ($_[0] =~ m/((?:[[:xdigit:]]{2}:){5}[[:xdigit:]]{2})/x){
        my $digest = uc(sha256_hex($1));
        my $orig = $1;
        return $_[0] if $orig =~ m/^AA:BB:CC/;
        $digest =~ m/$salt/;
        my $anon = "BE:EF:$3:$4:$5:$6";
        print STDERR "line $ln anon_mac $orig $anon\n";
        $_[0] =~ s/$orig/$anon/;
    }

    return $_[0]; 
}

