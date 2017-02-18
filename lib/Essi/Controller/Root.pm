package Essi::Controller::Root;

use common::sense;

use Mojo::Base 'Mojolicious::Controller';

use Data::GUID;
use File::Slurper qw( read_lines read_text );
use File::Basename qw(basename);
use List::Util qw(any);
use Cpanel::JSON::XS qw(decode_json);

my @BUILD_FILES = ( 'Makefile.PL', 'Build.PL' );

sub build {
  my $self = shift;

  my $stash = $self->_get( $self->stash('req_type') );
  unless ($stash) {
    $self->render( json => { status => 'fail' }, status => 400 );
    return;
  }

  $self->fork_call(
    sub {
      my $path = $self->_path($stash);
      $self->_build( $path, $stash );
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

  my %stash;

  my $v = $self->validation;

  $v->optional('auto_version');
  if ( $v->param('auto_version') ) {
    $stash{auto_version} = 1;
  }

  if ( $type eq 'custom' ) {
    $v->required('repo');
    return if $v->has_error;

    $stash{repo} = $v->param('repo');
  }
  elsif ( $type eq 'file' ) {
    $v->required('url')->like(qr/\.tar\.gz$/);
    return if $v->has_error;

    $stash{file} = $v->param('url');
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

    $stash{repo} = $repo;
  }
  elsif ( $type eq 'github-ssh' ) {
    my $repo;

    if ( $self->param('payload') ) {
      my $data = decode_json( $self->param('payload') );
      $repo = $data->{repository}{ssh_url};
    }
    else {
      $repo = $self->req->json->{repository}{ssh_url};
    }

    $stash{repo} = $repo;
  }
  elsif ( $type eq 'gitlab' ) {
    my $repo;

    my $key = 'git_http_url';
    if ( $self->stash('version') == 1 ) {
      $key = 'git_ssh_url';
    }

    if ( $self->param('payload') ) {
      my $data = decode_json( $self->param('payload') );
      $repo = $data->{repository}{$key};
    }
    else {
      $repo = $self->req->json->{repository}{$key};
    }

    $stash{repo} = $repo;
  }
  elsif ( $type eq 'gitlab-ssh' ) {
    my $repo;

    if ( $self->param('payload') ) {
      my $data = decode_json( $self->param('payload') );
      $repo = $data->{repository}{git_ssh_url};
    }
    else {
      $repo = $self->req->json->{repository}{git_ssh_url};
    }

    $stash{repo} = $repo;
  }
  elsif ( $type eq 'gogs' ) {
    $stash{repo} = $self->req->json->{repository}{html_url};
  }
  elsif ( $type eq 'gogs-ssh' ) {
    $stash{repo} = $self->req->json->{repository}{ssh_url};
  }
  else {
    return;
  }

  return \%stash;
}

sub _path {
  my $self    = shift;
  my $results = shift;

  my $guid = Data::GUID->new->as_string;

  if ( my $repo = $results->{repo} ) {
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
  my ( $path, $stash ) = @_;

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
      $git_repo = lc( basename($git_repo) );
      $git_repo =~ s/\_/\-/g;

      my $dependencie = 'lib' . $git_repo . '-perl';
      push @found_git_repos, $dependencie;
    }

    if ( scalar @found_git_repos ) {
      $depends = q{--depends '} . join( ',', @found_git_repos ) . q{'};
    }
  }

  my $deb_path = $ENV{ESSI_DEB_PATH} || $self->config->{essi}{deb_path};

  my $results = `mkdir -p $deb_path \\
  && cd $path/repo \\
  && perl $buildfile`;

  $self->app->log->debug($results);

  my $version;
  my $version_str = '';

  if ( $stash->{auto_version} ) {
    $version = $self->_detect_version($path);
    if ( defined $version ) {
      $version_str = "--version $version-1";
    }
  }

  ## Build
  $results = `export DEB_BUILD_OPTIONS=nocheck \\
  && cd $path \\
  && tar -zcvf repo.tar.gz ./repo \\
  && cd $path/repo \\
  && dh-make-perl -vcs none $version_str $depends`;

  $self->app->log->debug($results);

  if ( $stash->{auto_version} ) {
    foreach my $file ( glob "$path/*.orig.tar.gz" ) {
      my $new_file = $file;
      $new_file =~ s/\-1\.orig\.tar\.gz$/.orig.tar.gz/;
      rename $file, $new_file;
    }
  }

  $results = `export DEB_BUILD_OPTIONS=nocheck \\
  && cd $path/repo \\
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

sub _detect_version {
  my $self = shift;
  my $path = shift;

  my $meta = "$path/repo/MYMETA.json";
  return unless -e $meta;

  my $txt = read_text($meta);
  return unless $txt;

  my $decoded = decode_json($txt);

  return $decoded->{version} . '.' . time;
}

sub keyscan {
  my $self = shift;

  my $v = $self->validation;

  $v->required('host')->host();
  $v->optional('port')->like(qr/^\d{1,5}$/);

  if ( $v->has_error ) {
    $self->app->log->warn('Validation fail');
    $self->render( json => { status => 'fail' }, status => 400 );
    return;
  }

  my $host = $v->param('host');
  my $port = $v->param('port') // 22;

  my $keys = `ssh-keygen -F '$host'`;

  return if length $keys > 100;

  my @ips = `dig +short '$host'`;
  foreach my $ip (@ips) {
    chomp $ip;
    next unless $ip;

    `ssh-keyscan -p $port $ip >> ~/.ssh/known_hosts`;
  }

  `ssh-keyscan -p $port '$host' >> ~/.ssh/known_hosts`;

  $self->render( json => { status => 'ok' } );

  return;
}

1;
