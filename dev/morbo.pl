#!/usr/bin/env perl

use common::sense;

use Mojo::Base -strict;

$ENV{MOJO_MODE} = 'development';
$ENV{APPCONF_DIRS} = 'etc';

unshift( @INC, 'lib' );

require Mojolicious::Commands;
Mojolicious::Commands->start_app('Essi::Mojo');
