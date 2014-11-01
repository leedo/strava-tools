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
my $bike = $user->{athlete}{bikes}[0]{id};

my $fetch; $fetch = sub ($cv=AE::cv, $page=1) {
  $cv->begin;
  http_get "$base/api/v3/athlete/activities?page=$page",
    headers => {Authorization => "Bearer $user->{access_token}"},
    sub {
      my $activities = decode_json $_[0];

      for my $activity (@$activities) {
        next unless $activity->{type} eq "Ride";
        next if $activity->{gear_id} eq $bike;

        $cv->begin;
        http_request PUT => "$base/api/v3/activities/$activity->{id}?gear_id=$bike",
        headers => {Authorization => "Bearer $user->{access_token}"},
        sub {
          say "updated $base/activities/$activity->{id}";
          $cv->end;
        };
      }

      $fetch->($cv, $page + 1) if @$activities;
      $cv->end;
    };
  return $cv;
};

$fetch->()->recv;

say "done";
