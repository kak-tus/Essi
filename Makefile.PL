use common::sense;

use ExtUtils::MakeMaker::CPANfile;

WriteMakefile(
  NAME          => 'Essi',
  VERSION_FROM  => 'lib/Essi/Mojo.pm',
  ABSTRACT_FROM => 'lib/Essi/Mojo.pm',
  AUTHOR        => 'Andrey Kuzmin <kak-tus@mail.ru>',
  EXE_FILES     => ['bin/essi.pl'],
);

package MY;

sub install {
  my $self = shift;

  my $install_sec = $self->SUPER::install(@_);
  $install_sec =~ s/doc_install\n/etc_install\n/;

  $install_sec .= <<MAKE

etc_install :
	\$(NOECHO) \$(MOD_INSTALL) \\
		etc /etc

MAKE
      ;

  return $install_sec;
}

1;

