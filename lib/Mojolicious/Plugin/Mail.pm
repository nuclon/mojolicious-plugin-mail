package Mojolicious::Plugin::Mail;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Encode ();
use MIME::Lite;
use MIME::EncWords ();

use constant TEST    => $ENV{MOJO_MAIL_TEST} || 0;
use constant CHARSET => 'UTF-8';

our $VERSION = '0.5';

__PACKAGE__->attr(conf => sub { +{} });

sub register {
	my ($plugin, $app, $conf) = @_;
	
	$plugin->conf( $conf ) if $conf;
	
	$app->renderer->add_helper(
		mail => sub {
			my $self = shift;
			my $msg  = @_ ? $plugin->build( @_ ) : return;
			
			my $test = { @_ }->{test} || TEST;
			$msg->send( $conf->{'how'}, @{$conf->{'howargs'}||[]} ) unless $test;
			
			return $msg->as_string;
		},
	);
	
	$app->renderer->add_helper(
		render_mail => sub {
			my $self = shift;

			# Template name can be given as single argument or as hash value of 'template' key
			my $template;
			$template = shift if (@_ % 2 && !ref $_[0]) || (!@_ % 2 && ref $_[1]);
			my $args = ref $_[0] ? $_[0] : {@_};
			$args->{'template'} = $template if $template;
			
			my $data = $self->render_partial(%{$args}, format => 'mail');
			
			delete @{$self->stash}{ qw(partial mojo.content mojo.rendered format), keys %$args };
			return $data;
		},
	);
}

sub build {
	my $self = shift;
	my $conf = $self->conf;
	my $p    = { @_ };
	
	my $mail     = $p->{mail};
	my $charset  = $p->{charset } || $conf->{charset } || CHARSET;
	my $encoding = $p->{encoding} || $conf->{encoding};
	my $encode   = $encoding eq 'base64' ? 'B' : 'Q';
	my $mimeword = defined $p->{mimeword} ? $p->{mimeword} : !$encoding ? 0 : 1;
	
	# tuning
	
	$mail->{From} ||= $conf->{from};
	$mail->{Type} ||= $conf->{type};
	
	if ($mail->{Data}) {
		$mail->{Encoding} ||= $encoding;
		_enc($mail->{Data});
	}
	
	if ($mimeword) {
		$_ = MIME::EncWords::encode_mimeword($_, $encode, $charset) for grep { _enc($_); 1 } $mail->{Subject};
		
		for ( grep { $_ } @$mail{ qw(From To Cc Bcc) } ) {
			$_ = join ",\n",
				grep {
					_enc($_);
					{
						next unless /(.*) \s+ (\S+ @ .*)/x;
						
						my($name, $email) = ($1, $2);
						$email =~ s/(^<+|>+$)//sg;
						
						$_ = $name =~ /^[\w\s"'.,]+$/
							? "$name <$email>"
							: MIME::EncWords::encode_mimeword($name, $encode, $charset) . " <$email>"
						;
					}
					1;
				}
				split /\s*,\s*/
			;
		}
	}
	
	# year, baby!
	
	my $msg = MIME::Lite->new( %$mail );
	
	$msg->add   ( %$_ ) for @{$p->{headers} || []}; # XXX: add From|To|Cc|Bcc => ... (mimeword)
	
	$msg->attr  ( %$_ ) for @{$p->{attr   } || []};
	$msg->attr  ('content-type.charset' => $charset) if $charset;
	
	$msg->attach( %$_ ) for
		grep {
			if (!$_->{Type} || $_->{Type} eq 'TEXT') {
				$_->{Encoding} ||= $encoding;
				_enc($_->{Data});
			}
			1;
		}
		grep { $_->{Data} || $_->{Path} }
		@{$p->{attach} || []}
	;
	
	$msg->replace('X-Mailer' => join ' ', 'Mojolicious',  $Mojolicious::VERSION, __PACKAGE__, $VERSION, '(Perl)');
	
	return $msg;
}

sub _enc($) {
	Encode::_utf8_off($_[0]) if $_[0] && Encode::is_utf8($_[0]);
	return $_[0];
}

1;

__END__

=encoding UTF-8

=head1 NAME

Mojolicious::Plugin::Mail - Mojolicious Plugin for send mail.

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin(mail => {
    from     => 'sharifulin@gmail.com',
    encoding => 'base64',
    type     => 'text/html',
    how      => 'sendmail',
    howargs  => [ '/usr/sbin/sendmail -t' ],
  });

  # Mojolicious::Lite
  plugin mail => { ... };

  # in controller
  $self->helper('mail',
    mail => {
      To      => 'sharifulin@gmail.com',
      Subject => 'Test email',
      Data    => '<p>Привет!</p>',
    }
  );


=head1 DESCRIPTION

L<Mojolicous::Plugin::Mail> is a plugin to send mail using L<MIME::Lite>.

=head1 HELPERS

L<Mojolicious::Plugin::Mail> contains two helpers: mail and render_mail.

=head2 C<mail>

  $self->helper('mail',
      test   => 1, # test mode
      mail   => { ... }, # as MIME::Lite->new( ... )
      attach => [
        { ... }, # as MIME::Lite->attach( .. )
        ...
      },
      headers => [
        { ... }, # as MIME::Lite->add( .. )
        ...
      },
      attr => [
        { ... }, # as MIME::Lite->attr( .. )
        ...
      },
  );

Build and send email, return mail as string.

Supported parameters:

=over 5

=item * mail

Hashref, containts parameters as I<new(PARAMHASH)>. See MIME::Lite L<http://search.cpan.org/~rjbs/MIME-Lite-3.027/lib/MIME/Lite.pm#Construction>.

=item * attach 

Arrayref of hashref, hashref containts parameters as I<attach(PARAMHASH)>. See MIME::Lite L<http://search.cpan.org/~rjbs/MIME-Lite-3.027/lib/MIME/Lite.pm#Construction>.

=item * headers

Arrayref of hashref, hashref containts parameters as I<add(TAG, VALUE)>. See MIME::Lite L<http://search.cpan.org/~rjbs/MIME-Lite-3.027/lib/MIME/Lite.pm#Construction>.

=item * attr

Arrayref of hashref, hashref containts parameters as I<attr(ATTR, VALUE)>. See MIME::Lite L<http://search.cpan.org/~rjbs/MIME-Lite-3.027/lib/MIME/Lite.pm#Construction>.

=item * test

Test mode, don't send mail.

=back

=head2 C<render_mail>

  my $data = $self->render_mail( ... ); # any stash params;

Render mail template and return data, mail template format is I<mail>, i.e. I<controller/action.mail.ep>.

=head1 ATTRIBUTES

L<Mojolicious::Plugin::Mail> contains one attribute - conf.

=head2 C<conf>

  $plugin->conf;

Config of mail plugin, hashref.

Keys of hashref:

=over 6

=item * from

Default from address

=item * encoding 

Default encoding of Subject and any Data, value is MIME::Lite content transfer encoding L<http://search.cpan.org/~rjbs/MIME-Lite-3.027/lib/MIME/Lite.pm#Content_transfer_encodings>

=item * charset

Default charset of Subject and any Data, default value is UTF-8

=item * type

Default type of Data, default value is text/plain.

=item * how

HOW parameter of MIME::Lite::send, value are sendmail or smtp

=item * howargs 

HOWARGS parameter of MIME::Lite::send (arrayref)

=back

=head1 METHODS

L<Mojolicious::Plugin::Mail> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

  $plugin->register($app, $conf);

Register plugin hooks in L<Mojolicious> application.

=head2 C<build>

  $plugin->build( mail => { ... }, ... );

Build mail using L<MIME::Lite> and L<MIME::EncWords> and return MIME::Lite object.

=head1 TEST MODE

L<Mojolicious::Plugin::Mail> has test mode, no send mail.

  # all mail don't send mail
  BEGIN { $ENV{MOJO_MAIL_TEST} = 1 };

  # or only once
  $self->helper('mail',
    test => 1,
    mail => { ... },
  );

=head1 EXAMPLES

Simple send mail:

  get '/simple' => sub {
    my $self = shift;
    
    $self->helper('mail',
      mail => {
        To      => 'sharifulin@gmail.com',
        Subject => 'Тест письмо',
        Data    => "<p>Привет!</p>",
      },
    );
  };

Simple send mail with test mode:

  get '/simple2' => sub {
    my $self = shift;
    
    my $mail = $self->helper('mail',
      test => 1,
      mail => {
        To      => '"Анатолий Шарифулин" sharifulin@gmail.com',
        Cc      => '"Анатолий Шарифулин" <sharifulin@gmail.com>, Anatoly Sharifulin sharifulin@gmail.com',
        Bcc     => 'sharifulin@gmail.com',
        Subject => 'Тест письмо',
        Type    => 'text/plain',
        Data    => "<p>Привет!</p>",
      },
    );
    
    warn $mail;
  };

Mail with binary attachcment, charset is windows-1251, mimewords off and mail has custom header:

  get '/attach' => sub {
    my $self = shift;
    
    my $mail = $self->helper('mail',
      charset  => 'windows-1251',
      mimeword => 0,

      mail => {
        To      => 'sharifulin@gmail.com',
        Subject => 'Test attach',
        Type    => 'multipart/mixed'
      },
      attach => [
        {
          Data => 'Any data',
        },
        {
          Type        => 'BINARY',
          Filename    => 'crash.data',
          Disposition => 'attachment',
          Data        => 'binary data binary data binary data binary data binary data',
        },
      ],
      headers => [ { 'X-My-Header' => 'Mojolicious' } ],
    );
  };

Multipart mixed mail:

  get '/multi' => sub {
    my $self = shift;
    
    $self->helper('mail',
      mail => {
        To      => 'sharifulin@gmail.com',
        Subject => 'Мульти',
        Type    => 'multipart/mixed'
      },

      attach => [
        {
          Type     => 'TEXT',
          Encoding => '7bit',
          Data     => "Just a quick note to say hi!"
        },
        {
          Type     => 'image/gif',
          Path     => $0
        },
        {
          Type     => 'x-gzip',
          Path     => "gzip < $0 |",
          ReadNow  => 1,
          Filename => "somefile.zip"
        },
      ],
    );
  };

Mail with render data and subject from stash param:

  get '/render' => sub {
    my $self = shift;

    my $data = $self->helper('render_mail', 'render');
    $self->helper('mail',
      mail => {
        To      => 'sharifulin@gmail.com',
        Subject => $self->stash('subject'),
        Data    => $data,
      },
    );
  } => 'render';

  __DATA__

  @@ render.html.ep
  <p>Hello render!</p>
  
  @@ render.mail.ep
  % stash 'subject' => 'Привет render';
  
  <p>Привет mail render!</p>


=head1 SEE ALSO

L<MIME::Lite> L<MIME::EncWords> L<Mojolicious> L<Mojolicious::Guides> L<http://mojolicious.org>.

=head1 AUTHOR

Anatoly Sharifulin <sharifulin@gmail.com>

=head1 THANKS

Alex Kapranoff <kapranoff@gmail.com>

=head1 BUGS

Please report any bugs or feature requests to C<bug-mojolicious-plugin-mail at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.htMail?Queue=Mojolicious-Plugin-Mail>.  We will be notified, and then you'll
automatically be notified of progress on your bug as we make changes.

=over 5

=item * Github

L<http://github.com/sharifulin/mojolicious-plugin-mail/tree/master>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.htMail?Dist=Mojolicious-Plugin-Mail>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Mojolicious-Plugin-Mail>

=item * CPANTS: CPAN Testing Service

L<http://cpants.perl.org/dist/overview/Mojolicious-Plugin-Mail>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Mojolicious-Plugin-Mail>

=item * Search CPAN

L<http://search.cpan.org/dist/Mojolicious-Plugin-Mail>

=back

=head1 COPYRIGHT & LICENSE

Copyright (C) 2010 by Anatoly Sharifulin.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
