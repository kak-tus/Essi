package Essi::Mojo;

our $VERSION = 0.12;

use common::sense;

use Mojo::Base 'Mojolicious';

use App::Environ
    initialize => 0,
    finalize   => 1;

use App::Environ::Config;
use Data::Validate::Domain qw(is_hostname);

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
  $self->_init_validation();

  return;
}

sub _init_config {
  my $self = shift;

  App::Environ->send_event('initialize');
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
    [ req_type => [qw( github gitlab custom file gogs )] ],
    [ format   => [qw(json)] ]
  )->to( 'Root#build', version => 1 );

  $route->post(
    '/v2/build/:req_type',
    [ req_type => [
        qw(
            github
            github-ssh
            gitlab
            gitlab-ssh
            custom
            file
            gogs
            gogs-ssh
            )
      ]
    ],
    [ format => [qw(json)] ]
  )->to( 'Root#build', version => 2 );

  $route->post( '/v2/ssh-keyscan', [ format => [qw(json)] ] )
      ->to('Root#keyscan');

  return;
}

sub _init_validation {
  my $self = shift;

  $self->validation->validator->add_check(
    host => sub {
      my ( $validation, $name, $value ) = @_;
      return !is_hostname($value);
    }
  );

  return;
}

sub END {
  return unless $LOADED;

  undef $LOADED;

  App::Environ->send_event('finalize:r');

  return;
}

1;

=encoding utf-8

=head1 NAME

Essi::Mojo - Essi - automated perl to deb converter

=head1 AUTHOR

Andrey Kuzmin

=cut

