package Essi::Mojo;

our $VERSION = 0.6;

use common::sense;

use Mojo::Base 'Mojolicious';

use App::Environ
    initialize => 0,
    finalize   => 1;

use App::Environ::Config;

App::Environ::Config->register(
  qw(
      essi.yml
      essi.d/*.yml
      )
);

my $LOADED;

sub startup {
  my $self = shift;

  $self->_init_config();
  $self->_init_plugins();
  $self->_init_routes();

  return;
}

sub _init_config {
  my $self = shift;

  App::Environ->push_event('initialize');
  $LOADED = 1;

  my $config = App::Environ::Config->instance;
  $self->config($config);

  $self->mode( $ENV{MOJO_MODE} // 'production' );

  $self->secrets( $self->config->{essi}{secrets} );

  return;
}

sub _init_plugins {
  my $self = shift;

  if ( $self->mode eq 'production' ) {
    $self->plugin(
      SetUserGroup => {
        user  => $self->config->{essi}{user},
        group => $self->config->{essi}{group}
      }
    );
  }

  $self->plugin('ForkCall');

  return;
}

sub _init_routes {
  my $self = shift;

  my $route = $self->routes();
  $route->namespaces( ['Essi::Controller'] );

  $route->post(
    '/v1/build/:req_type',
    [ req_type => [qw( github gitlab custom )] ],
    [ format   => [qw(json)] ]
  )->to('Root#build');

  return;
}

sub END {
  return unless $LOADED;

  undef $LOADED;

  App::Environ->push_event('finalize');

  return;
}

1;

=encoding utf-8

=head1 NAME

Essi::Mojo - Essi - automated perl to deb converter

=head1 AUTHOR

Andrey Kuzmin

=cut

