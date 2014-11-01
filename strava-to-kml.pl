#!/usr/bin/env perl

use v5.20;
use feature 'signatures';

use AnyEvent;
use AnyEvent::HTTP;
use AnyEvent::HTTPD;
use JSON::XS;
use URI;
use URI::QueryParam;

my ($id, $secret) = do {
  open(my $fh, "<", "secret") or die "missing secret";
  split " ", <$fh>;
};

my $base = "https://www.strava.com";
my $auth = URI->new("$base/oauth/authorize");
$auth->query_form_hash({
  client_id => $id,
  redirect_uri => "http://localhost:8001/",
  response_type => "code",
  scope => "write"
});

say "paste this URL into your browser: " . $auth->as_string;

my $cv = AE::cv;
my $httpd = AnyEvent::HTTPD->new(port => 8001);

$httpd->reg_cb("/" => sub {
  my ($httpd, $req) = @_;
  $req->respond([200, "OK", {"Content-Type" => "text/plain"}, "success"]);
  $cv->send($req->parm("code"));
});

my $code = $cv->recv;

$cv = AE::cv;
http_post "$base/oauth/token",
  "client_id=$id&client_secret=$secret&code=$code",
  sub { $cv->send(decode_json $_[0]) };

my $user = $cv->recv;

