#!/usr/bin/env perl

use common::sense;

use Mojo::Base -strict;

$ENV{MOJO_MODE} = 'production';
$ENV{APPCONF_DIRS} = '/etc';

require Mojolicious::Commands;
Mojolicious::Commands->start_app('Essi::Mojo');

