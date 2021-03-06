#!/usr/bin/env perl
use lib qw(lib ../../lib);
use utf8;

use Mojolicious::Lite;

app->log->level('error');

plugin mail => {
	from     => 'sharifulin@gmail.com',
	encoding => 'base64',
	type     => 'text/html',
	how      => 'sendmail',
	howargs  => [ '/usr/sbin/sendmail -t' ],
};

get '/empty' => sub {
	my $self = shift;
	$self->render_json({ ok => 1, mail => $self->helper('mail') || undef})
};

get '/simple' => sub {
	my $self = shift;
	
	my $mail = $self->helper('mail',
		test => 1,
		mail => {
			To      => 'sharifulin@gmail.com',
			Subject => 'Тест письмо',
			Data    => "<p>Привет!</p>",
		},
	);
	
	$self->render_json({ ok => 1, mail => $mail });
};

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
	
	$self->render_json({ ok => 1, mail => $mail });
};

get '/attach' => sub {
    my $self = shift;
    
	my $mail = $self->helper('mail',
		test => 1,
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
	
	$self->render_json({ ok => 1, mail => $mail });
};

get '/multi' => sub {
    my $self = shift;
    
	my $mail = $self->helper('mail',
		test => 1,
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
	
	$self->render_json({ ok => 1, mail => $mail });
};

get '/render' => sub {
	my $self = shift;

	my $mail = $self->helper('mail',
		test => 1,
		mail => {
			To      => 'sharifulin@gmail.com',
			Subject => 'Тест render',
			Data    => '',
			Data    => $self->render_partial('render', format => 'mail'),
		},
	);
	
	$self->render(format => 'html', ok => 1, mail => $mail);
} => 'render';

get '/render2' => sub {
	my $self = shift;
	
	my $data = $self->helper('render_mail', 'render2');
	my $mail = $self->helper('mail',
		test => 1,
		mail => {
			To      => 'sharifulin@gmail.com',
			Subject => $self->stash('subject'),
			Data    => $data,
		},
	);
	
	$self->render(ok => 1, mail => $mail);
} => 'render';

#

use Test::More tests => 91;
use Test::Mojo;

use Mojo::Headers;
use Mojo::ByteStream 'b';

use Data::Dumper;

my $t = Test::Mojo->new;
my $json;

$t->get_ok('/empty')
  ->status_is(200)
  ->json_content_is({ok => 1, mail => undef}, 'empty')
;

$json = $t->get_ok('/simple')
  ->status_is(200)
  ->tx->res->json
;

{
	is ref $json, 'HASH';
	is exists $json->{ok}, 1;
	is defined $json->{ok}, 1;
	is exists $json->{mail}, 1;
	
	my($raw, $body) = split /\n\n/, $json->{mail};
	my $h = Mojo::Headers->new; $h->parse("$raw\n\n");
	
	is $h->header('MIME-Version'), '1.0';
	is $h->header('Content-Type'), 'text/html; charset="UTF-8"';
	is $h->header('Content-Disposition'), 'inline';
	is $h->header('Content-Transfer-Encoding'), 'base64';
	like $h->header('X-Mailer'), qr/Mojolicious/;
	
	is $h->header('To'), 'sharifulin@gmail.com';
	is $h->header('From'), 'sharifulin@gmail.com';
	is $h->header('Subject'), "=?UTF-8?B?" . b('Тест письмо')->b64_encode('') . "?=";
	
	is $body, b("<p>Привет!</p>")->b64_encode, 'simple';
}

$json = $t->get_ok('/simple2')
  ->status_is(200)
  ->tx->res->json
;

{
	is ref $json, 'HASH';
	is exists $json->{ok}, 1;
	is defined $json->{ok}, 1;
	is exists $json->{mail}, 1;
	
	my($raw, $body) = split /\n\n/, $json->{mail};
	my $h = Mojo::Headers->new; $h->parse("$raw\n\n");
	
	is $h->header('MIME-Version'), '1.0';
	is $h->header('Content-Type'), 'text/plain; charset="UTF-8"';
	is $h->header('Content-Disposition'), 'inline';
	is $h->header('Content-Transfer-Encoding'), 'base64';
	like $h->header('X-Mailer'), qr/Mojolicious/;
	
	is $h->header('To'), '=?UTF-8?B?ItCQ0L3QsNGC0L7Qu9C40Lkg0KjQsNGA0LjRhNGD0LvQuNC9Ig==?= <sharifulin@gmail.com>';
	is $h->header('Cc'), '=?UTF-8?B?ItCQ0L3QsNGC0L7Qu9C40Lkg0KjQsNGA0LjRhNGD0LvQuNC9Ig==?= <sharifulin@gmail.com>, Anatoly Sharifulin <sharifulin@gmail.com>';
	is $h->header('From'), 'sharifulin@gmail.com';
	is $h->header('Subject'), "=?UTF-8?B?0KLQtdGB0YIg0L/QuNGB0YzQvNC+?=";
	
	is $body, b("<p>Привет!</p>")->b64_encode, 'simple2';
}

$json = $t->get_ok('/attach')
  ->status_is(200)
  ->tx->res->json
;

{
	is ref $json, 'HASH';
	is exists $json->{ok}, 1;
	is defined $json->{ok}, 1;
	is exists $json->{mail}, 1;
	
	my($raw, $body) = split /\n\n/, $json->{mail};
	my $h = Mojo::Headers->new; $h->parse("$raw\n\n");
	
	is $h->header('MIME-Version'), '1.0';
	like $h->header('Content-Type'), qr{multipart/mixed; boundary=".*?"; charset="windows-1251"};
	is $h->header('Content-Transfer-Encoding'), 'binary';
	is $h->header('X-My-Header'), 'Mojolicious';
	like $h->header('X-Mailer'), qr/Mojolicious/;
	
	is $h->header('To'), 'sharifulin@gmail.com';
	is $h->header('From'), 'sharifulin@gmail.com';
	is $h->header('Subject'), 'Test attach';
	
	like $body, qr{This is a multi-part message in MIME format.}, 'attach';
}

$json = $t->get_ok('/multi')
  ->status_is(200)
  ->tx->res->json
;

{
	is ref $json, 'HASH';
	is exists $json->{ok}, 1;
	is defined $json->{ok}, 1;
	is exists $json->{mail}, 1;
	
	my($raw, $body) = split /\n\n/, $json->{mail};
	my $h = Mojo::Headers->new; $h->parse("$raw\n\n");
	
	is $h->header('MIME-Version'), '1.0';
	like $h->header('Content-Type'), qr{multipart/mixed; boundary=".*?"; charset="UTF-8"};
	is $h->header('Content-Transfer-Encoding'), 'binary';
	like $h->header('X-Mailer'), qr/Mojolicious/;
	
	is $h->header('To'), 'sharifulin@gmail.com';
	is $h->header('From'), 'sharifulin@gmail.com';
	is $h->header('Subject'), '=?UTF-8?B?0JzRg9C70YzRgtC4?=';
	
	like $body, qr{This is a multi-part message in MIME format.}, 'multi';
}

my $data = $t->get_ok('/render')
  ->status_is(200)
  ->tx->res
;

{
	is defined $data, 1;
	like $data, qr{<p>Hello render!</p>};
	like $data, qr{<p>1</p>};
	
	$data =~ m{.*<p>(.*?)</p>}s;
	
	my($raw, $body) = split /\n\n/, $1;
	my $h = Mojo::Headers->new; $h->parse("$raw\n\n");
	
	is $h->header('MIME-Version'), '1.0';
	is $h->header('Content-Type'), 'text/html; charset="UTF-8"';
	is $h->header('Content-Disposition'), 'inline';
	is $h->header('Content-Transfer-Encoding'), 'base64';
	like $h->header('X-Mailer'), qr/Mojolicious/;
	
	is $h->header('To'), 'sharifulin@gmail.com';
	is $h->header('From'), 'sharifulin@gmail.com';
	is $h->header('Subject'), "=?UTF-8?B?0KLQtdGB0YIgcmVuZGVy?=";
	
	is $body, b("<p>Привет mail render!</p>\n")->b64_encode, 'render';
}

my $d = $t->get_ok('/render2')
  ->status_is(200)
  ->tx->res->body
;

{
	is defined $d, 1;
	like $d, qr{<p>Hello render!</p>};
	like $d, qr{<p>1</p>};
	
	$d =~ m{.*<p>(.*?)</p>}s;
	
	my($raw, $body) = split /\n\n/, $1;
	my $h = Mojo::Headers->new; $h->parse("$raw\n\n");
	
	is $h->header('MIME-Version'), '1.0';
	is $h->header('Content-Type'), 'text/html; charset="UTF-8"';
	is $h->header('Content-Disposition'), 'inline';
	is $h->header('Content-Transfer-Encoding'), 'base64';
	like $h->header('X-Mailer'), qr/Mojolicious/;
	
	is $h->header('To'), 'sharifulin@gmail.com';
	is $h->header('From'), 'sharifulin@gmail.com';
	is $h->header('Subject'), "=?UTF-8?B?" . b('Привет render2')->b64_encode('') . "?=";
	
	is $body, "CjxwPtCf0YDQuNCy0LXRgiBtYWlsIHJlbmRlcjIhPC9wPgo=\n", 'render2';
}

__DATA__

@@ render.html.ep
<p>Hello render!</p>
<p><%= $ok %></p>
<p><%== $mail %></p>

@@ render.mail.ep
<p>Привет mail render!</p>

@@ render2.mail.ep
% stash 'subject' => 'Привет render2';

<p>Привет mail render2!</p>
