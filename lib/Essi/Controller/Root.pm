package Essi::Controller::Root;

use common::sense;

use Mojo::Base 'Mojolicious::Controller';

use Data::GUID;
use Mojo::URL;
use File::Slurper qw(read_lines);
use File::Basename qw(basename);
use List::Util qw(any);
use Cpanel::JSON::XS qw(decode_json);

my @BUILD_FILES = ( 'Makefile.PL', 'Build.PL' );

sub build {
  my $self = shift;

  my $results = $self->_get( $self->stash('req_type') );
  unless ($results) {
    $self->render( json => { status => 'fail' }, status => 404 );
    return;
  }

  $self->fork_call(
    sub {
      my $path = $self->_path($results);
      $self->_build($path);
    },
    [],
    sub { }
  );

  $self->render( json => { status => 'ok' } );

  return;
}

sub _get {
  my $self = shift;
  my $type = shift;

  if ( $type eq 'custom' ) {
    return { repo => $self->param('repo') };
  }
  elsif ( $type eq 'file' ) {
    return unless $self->param('url') =~ m/\.tar\.gz$/;
    return { file => $self->param('url') };
  }
  elsif ( $type eq 'github' ) {
    my $repo;

    if ( $self->param('payload') ) {
      my $data = decode_json( $self->param('payload') );
      $repo = $data->{repository}{clone_url};
    }
    else {
      $repo = $self->req->json->{repository}{clone_url};
    }

    return { repo => $repo };
  }
  elsif ( $type eq 'gitlab' ) {
    my $repo;

    if ( $self->param('payload') ) {
      my $data = decode_json( $self->param('payload') );
      $repo = $data->{repository}{git_ssh_url};
    }
    else {
      $repo = $self->req->json->{repository}{git_ssh_url};
    }

    return { repo => $repo };
  }

  return;
}

sub _path {
  my $self    = shift;
  my $results = shift;

  my $guid = Data::GUID->new->as_string;

  if ( my $repo = $results->{repo} ) {
    my $uri = Mojo::URL->new($repo);

    ## If ssh - add host and IP's to known_hosts
    if ( $uri && $uri->protocol eq 'ssh' ) {
      $self->_add_keys( $uri->host );
    }

    ## Clone repo
    `cd /tmp && git clone $repo essi_$guid/repo`;
  }
  elsif ( my $file = $results->{file} ) {
    `mkdir -p /tmp/essi_$guid/repo \\
    && curl '$file' -o /tmp/essi_$guid/repo.tar.gz \\
    && tar -xzvf /tmp/essi_$guid/repo.tar.gz -C /tmp/essi_$guid/repo --strip-components=1 \\
    && rm /tmp/essi_$guid/repo.tar.gz`;
  }

  return "/tmp/essi_$guid";
}

sub _build {
  my $self = shift;
  my $path = shift;

  ## Some build *.PL must exists to prevent build of nonperl repos
  my $buildfile;
  foreach (@BUILD_FILES) {
    next unless -e "$path/repo/$_";
    $buildfile = $_;
  }

  unless ($buildfile) {
    `rm -rf $path`;
    return;
  }

  ## Check ssh git repos in cpanfile (we add them as dependencies manually)
  my $depends = '';
  if ( -e "$path/repo/cpanfile" ) {
    my @found_git_repos;

    my @lines = read_lines("$path/repo/cpanfile");
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
  my $results = `export DEB_BUILD_OPTIONS=nocheck \\
  && mkdir -p $deb_path \\
  && cd $path/repo \\
  && perl $buildfile \\
  && cd $path \\
  && tar -zcvf repo.tar.gz ./repo \\
  && cd $path/repo \\
  && dh-make-perl -vcs none $depends \\
  && dpkg-buildpackage -d -us -uc \\
  && cp $path/*.deb $deb_path \\
  && cp $path/*.changes $deb_path \\
  && cp $path/*.dsc $deb_path \\
  && cp $path/*.tar.xz $deb_path \\
  && cp $path/*.tar.gz $deb_path \\
  && rm -rf $path`;

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
