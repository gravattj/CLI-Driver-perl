#!/usr/bin/env perl

# vim: tabstop=4 expandtab

###### PACKAGES ######

use Modern::Perl;
use Data::Printer alias => 'pdump';
use CLI::Driver;
use Test::More;

use Getopt::Long;
Getopt::Long::Configure('no_ignore_case');
Getopt::Long::Configure('pass_through');
Getopt::Long::Configure('no_auto_abbrev');

###### CONSTANTS ######

###### GLOBALS ######

use vars qw(
  $Driver
);

###### MAIN ######

unshift @INC, 't/lib';

$| = 1;
$Driver = CLI::Driver->new( path => 't/etc', file => 'cli-driver.yml' );

###

# test 3 without optional arg
push @ARGV, '-m', 'foo', '-s', 'bar';

my $action = $Driver->get_action(name => 'test4');
ok($action);

my $result = $action->do;
ok(!defined $result);

push @ARGV, '-o', 'biz';
$result = $action->do;
ok($result eq 'biz');
 
###

done_testing();

###### END MAIN ######
