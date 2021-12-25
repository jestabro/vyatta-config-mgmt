#!/usr/bin/perl
#
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# A copy of the GNU General Public License is available as
# `/usr/share/common-licenses/GPL' in the Debian GNU/Linux distribution
# or on the World Wide Web at `http://www.gnu.org/copyleft/gpl.html'.
# You can also obtain it by writing to the Free Software Foundation,
# Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2010 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Stig Thormodsrud
# Date: October 2010
# Description: Script to push cofig.boot to one or more URIs
#
# **** End License ****
#

use strict;
use warnings;
use lib '/opt/vyatta/share/perl5/';

use Vyatta::Config;
use Vyatta::ConfigMgmt;
use POSIX;
use File::Compare;
use File::Copy;
use URI;
use Sys::Hostname;
use IO::Prompt;


my $debug = 0;

my $config = new Vyatta::Config;
$config->setLevel('system config-management commit-archive');
my @uris = $config->returnOrigValues('location');

if (scalar(@uris) < 1) {
    print "No URI's configured\n";
    exit 0;
}

my $last_push_file = cm_get_last_push_file();
my $tmp_push_file  = "/tmp/config.boot.$$";

my $cmd = 'cli-shell-api showConfig --show-ignore-edit --show-active-only';
system("$cmd > $tmp_push_file");

if (-e $last_push_file and compare($last_push_file, $tmp_push_file) == 0) {
    exit 0;
}

my $timestamp = strftime(".%Y%m%d_%H%M%S", localtime);
my $hostname = hostname();
$hostname = 'vyos' if ! defined $hostname;
my $save_file = "config.boot-$hostname" . $timestamp;

# Was a source address specified?
my $source_address = $config->returnEffectiveValue('source-address');
# If so, we're going to pass that to the Python funcall.
if (defined($source_address)) {
    print("Using source address $source_address\n");
}
else {
    $source_address = '';
}
# The string needs to be wrapped in quotes, even if it's empty.
$source_address = '"' . $source_address . '"';

print "Archiving config...\n";
foreach my $uri (@uris) {
    my $u      = URI->new($uri);
    my $scheme = $u->scheme();
    my $auth   = $u->authority();
    my $path   = $u->path();
    my ($host, $remote, $cmd) = ('', '', '');
    if (defined $auth and $auth =~ /.*\@(.*)/) {
        $host = $1;
    } else {
        $host = $auth if defined $auth;
    }
    $remote .= "$scheme://$host";
    $remote .= "$path" if defined $path;
    print "  $remote ";

    system("python3 -c 'from vyos.remote import upload; upload(\"$tmp_push_file\", \"$uri/$save_file\", source_host=$source_address)'");
}

move($tmp_push_file, $last_push_file);

exit 0;
