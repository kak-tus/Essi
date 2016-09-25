package Essi::Controller::Root;

use common::sense;

use Mojo::Base 'Mojolicious::Controller';

use Data::GUID;
use Mojo::URL;
use File::Slurper qw(read_lines);
use File::Basename qw(basename);
use List::Util qw(any);
use Cpanel::JSON::XS qw(decode_json);

sub build {
  my $self = shift;

  my $repo = $self->_repo( $self->stash('req_type') );
  unless ($repo) {
    $self->render( json => { status => 'fail' }, status => 404 );
    return;
  }

  $self->fork_call(
    sub {
      $self->_build($repo);
    },
    [],
    sub { }
  );

  $self->render( json => { status => 'ok' } );

  return;
}

sub _repo {
  my $self = shift;
  my $type = shift;

  if ( $type eq 'custom' ) {
    return $self->param('repo');
  }
  elsif ( any { $type eq $_ } qw( github gitlab ) ) {
    if ( $self->param('payload') ) {
      my $data = decode_json( $self->param('payload') );
      return $data->{repository}{clone_url};
    }
    else {
      return $self->req->json->{repository}{clone_url};
    }
  }

  return;
}

sub _build {
  my $self = shift;
  my $repo = shift;

  my $uri = Mojo::URL->new($repo);

  ## If ssh - add host and IP's to known_hosts
  if ( $uri && $uri->protocol eq 'ssh' ) {
    $self->_add_keys( $uri->host );
  }

  my $guid = Data::GUID->new->as_string;

  ## Clone repo
  ## repo.tar.gz need to create orig.tar.gz (in dh-make-perl)
  `cd /tmp && git clone $repo essi_$guid/repo && cd essi_$guid \\
  && tar -zcvf repo.tar.gz ./repo`;

  ## Makefile.PL must exists to prevent build of nonperl repos
  unless ( -e "/tmp/essi_$guid/repo/Makefile.PL" ) {
    return;
  }

  ## Check ssh git repos in cpanfile (we add them as dependencies manually)
  my $depends = '';
  if ( -e "/tmp/essi_$guid/repo/cpanfile" ) {
    my @found_git_repos;

    my @lines = read_lines("/tmp/essi_$guid/repo/cpanfile");
    foreach my $line (@lines) {
      my ($git_repo) = $line =~ m/requires \'(ssh\:\/\/.+)\'/;
      next unless $git_repo;

      $git_repo =~ s/\.git$//;
      my $dependencie = 'lib' . lc( basename($git_repo) ) . '-perl';
      push @found_git_repos, $dependencie;
    }

    if ( scalar @found_git_repos ) {
      $depends = q{--depends '} . join( ',', @found_git_repos ) . q{'};
    }
  }

  my $deb_path = $ENV{ESSI_DEB_PATH} || $self->config->{essi}{deb_path};

  ## Build
  my $results = `export DEB_BUILD_OPTIONS=nocheck && mkdir -p $deb_path \\
  && cd /tmp/essi_$guid/repo \\
  && perl Makefile.PL \\
  && dh-make-perl -vcs none $depends && dpkg-buildpackage -d -us -uc \\
  && cp /tmp/essi_$guid/*.deb $deb_path \\
  && cp /tmp/essi_$guid/*.changes $deb_path \\
  && cp /tmp/essi_$guid/*.dsc $deb_path \\
  && cp /tmp/essi_$guid/*.tar.xz $deb_path \\
  && cp /tmp/essi_$guid/*.tar.gz $deb_path && rm -rf /tmp/essi_$guid/`;

  $self->app->log->debug($results);

  return;
}

sub _add_keys {
  my $self = shift;
  my $host = shift;

  my $keys = `ssh-keygen -F $host`;
  if ( length $keys < 100 ) {
    my @ips = `dig +short $host`;
    foreach my $ip (@ips) {
      chomp $ip;
      next unless $ip;

      `ssh-keyscan -H $ip >> ~/.ssh/known_hosts`;
    }

    `ssh-keyscan -H $host >> ~/.ssh/known_hosts`;
  }

  return;
}

1;
