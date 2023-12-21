# -*- Perl -*-
use strict;
use warnings;
use Path::Tiny;
use Time::HiRes qw(time);
use Promise;
use Promised::Flow;
use Promised::File;
use JSON::PS;
use Digest::SHA qw(hmac_sha1);
use Web::Transport::Base64;
use Web::Encoding;
use Web::URL;
use Wanage::HTTP;
use Warabe::App;

use WorkerState;

my $DEBUG = $ENV{WDIPP_DEBUG};

my $AboutBlank = Web::URL->parse_string ("about:blank");
my $Creating = 0;
sub get_session ($$) {
  my $sdata = shift;
  my $usage = shift;

  my $max_count = $sdata->{config}->{max_wd_sessions} || 4;
  my $ss_timeout = $sdata->{config}->{wd_session_start_timeout} || 60;
  my $created;
  my $create_session = sub {
    my $wd = Web::Driver::Client::Connection->new_from_url
        (Web::URL->parse_string ($sdata->{config}->{wd_url}));
    my $key = rand;
    my $session;
    my $abort = sub {
      my $reason = shift;
      warn "SESSION: $$: Abort ($reason) $key [$usage]\n" if $DEBUG;
      delete $sdata->{wds}->{$key};
      $session->close if defined $session;
      my $close = defined $wd ? $wd->close : undef;
      undef $session;
      undef $wd;
      return $close;
    }; # $abort
    my $done = sub {
      warn "SESSION: $$: Done $key [$usage]\n" if $DEBUG;
      $sdata->{wds}->{$key}->[4] = 0 if defined $sdata->{wds}->{$key};
      $abort->("No session reuse") if $sdata->{config}->{no_wd_session_reuse};
    }; # $done
    return Promise->resolve->then (sub {
      return promised_wait_until {
        die "Create canceled" if $created;
        my @c = keys %{$sdata->{wds}};
        if (@c >= $max_count) {
          warn "SESSION: $$: Too many sessions ($max_count), wait... [$usage]\n" if $DEBUG;
          return not 'done';
        }
        return not 'done' if $Creating > 0;
        $Creating++;
        return $wd->new_session (
          desired => {},
          #http_proxy_url
        )->then (sub {
          $session = $_[0];
          warn "SESSION: $$: Created (@{[0+keys %{$sdata->{wds}}]}) $key [$usage]\n" if $DEBUG;
          return 'done';
        }, sub {
          if (UNIVERSAL::isa ($_[0], 'Web::Driver::Client::Response') and
              defined $_[0]->{response} and
              ($_[0]->{response}->status == 504 or
               $_[0]->{response}->status == 503)) { # XXX
            warn $_[0]->{response}->body_bytes;
          }
          warn "Failed to create a session: $_[0] [$usage]";
          return not 'done';
        })->finally (sub {
          $Creating--;
        });
      } timeout => $ss_timeout, interval => 15;
    })->then (sub {
      die unless defined $session;
      return $sdata->{wds}->{$key} = [$wd, $session, $done, $abort, (not 'in use'), $key];
    }, sub {
      $abort->("Session creation failed: $_[0]");
      die $_[0];
    });
  }; # $create_session

  return new Promise (sub {
    my ($ok, $ng) = @_;
    Promise->all ([
      promised_sleep (1)->then (sub {
        return if $created;
        return $create_session->();
      }),
      (promised_wait_until {
        for (keys %{$sdata->{wds}}) {
          my $v = $sdata->{wds}->{$_};
          if (! $v->[4]) {
            $v->[4] = 1;
            warn "SESSION: $$: Reuse $_ [$usage]\n" if $DEBUG;
            return $v->[1]->go ($AboutBlank)->then (sub {
              $created = 1;
              $ok->($v);
              return 'done';
            }, sub {
              $v->[3]->("Stalled");
              return not 'done';
            });
          }
        }
        return not 'done';
      } timeout => $ss_timeout, interval => 3),
    ])->catch ($ng);
  });
} # get_session

sub error_response ($$$$) {
  my ($app, $config, $reason, $details) = @_;
  $app->http->set_status (500, reason_phrase => $reason);
  if ($config->{is_live} or $config->{is_test_script}) {
    $app->http->set_response_header
        ('Content-Type' => 'text/plain; charset=us-ascii');
    $app->http->send_response_body_as_text ('500 ' . $reason);
  } else {
    $app->http->set_response_header
        ('Content-Type' => 'text/plain; charset=utf-8');
    $app->http->send_response_body_as_text ('500 ' . $reason . "\x0A" . $details);
  }
  $app->http->close_response_body;
  warn "ERROR: $details\n";
  return $app->throw;
} # error_response

sub run_processor ($$) {
  my ($app, $name) = @_;
  my $sdata = $app->http->server_state->data;
  my $def = $sdata->{config}->{processors}->{$name};
  unless (defined $def) {
    return $app->throw_error (404, reason_phrase => 'No processor');
  }

  my $arg = $app->text_param ('arg') // '';
  if (defined $def->{key}) {
    my $sig_got = $app->bare_param ('signature') // '';
    my $sig_expected = encode_web_base64 hmac_sha1
        (encode_web_utf8 ($arg), encode_web_utf8 ($def->{key}));
    return $app->throw_error (400, reason_phrase => 'Bad |signature|')
        unless $sig_got eq $sig_expected;
  }
  
  my $js_path = path ($sdata->{config}->{processors_dir})->child ($name . '.js');
  my $js_file = Promised::File->new_from_path ($js_path);
  
  my $timeout = $def->{timeout} || 60;
  my $abort = sub { };
  my $wdskey;
  return Promise->resolve->then (sub {
    return promised_timeout {
      return get_session ($sdata, $name.':'.$arg)->then (sub {
        my $session;
        my $done;
        (undef, $session, $done, $abort, undef, $wdskey) = @{$_[0]};

        return Promise->resolve->then (sub {
          return unless defined $def->{page_url};
          my $u = Web::URL->parse_string ($def->{page_url});
          return error_response $app, $sdata->{config}, 'Bad process',
              "$wdskey: Bad |page_url|: " . $def->{page_url}
              unless defined $u and $u->is_http_s;
          return $session->go ($u);
        })->then (sub {
          return $js_file->read_char_string;
        })->then (sub {
          return $session->execute (q{
            return Promise.resolve ().then (() => new Function (arguments[0]).apply (null, arguments[1])).then (value => {
              if (value && value.content && value.content.targetElement) {
                value.content.sizes = {
                  teWidth: value.content.targetElement.offsetWidth,
                  teHeight: value.content.targetElement.offsetHeight,
                  teLeft: value.content.targetElement.offsetLeft,
                  teTop: value.content.targetElement.offsetTop,
                  wDeltaX: window.outerWidth - window.innerWidth,
                  wDeltaY: window.outerHeight - window.innerHeight,
                };
              }
              return value;
            });
          }, [$_[0], [$arg]], timeout => $timeout * 2)->then (sub {
            my $res = $_[0];
        my $value = $res->json->{value};
        unless (defined $value and
                ref $value eq 'HASH' and
                defined $value->{content} and
                ref $value->{content} eq 'HASH') {
          return error_response $app, $sdata->{config}, 'Bad result',
              "$wdskey: Bad JavaScript response: " . perl2json_bytes $value;
        }
        my $headers = sub {
          $app->http->set_status ($value->{statusCode}) if defined $value->{statusCode};
          if (defined $value->{httpCache} and
              ref $value->{httpCache} eq 'HASH' and
              defined $value->{httpCache}->{maxAge}) {
            $app->http->add_response_header
                ('cache-control', sprintf 'public,max-age=%d', $value->{httpCache}->{maxAge});
          }
        }; # $headers
        if (($value->{content}->{type} // '') eq 'screenshot') {
          if (defined $value->{content}->{targetElement} and
              not ref $value->{content}->{targetElement} eq 'HASH') {
            return error_response $app, $sdata->{config}, 'Bad result',
                "$wdskey: Bad JavaScript response: " . perl2json_bytes $value;
          }
          return Promise->resolve->then (sub {
            return unless defined $value->{content}->{targetElement};
            my $ss = $value->{content}->{sizes};
            return $session->set_window_dimension (
              $ss->{wDeltaX} + $ss->{teLeft} + $ss->{teWidth} + 100,
              $ss->{wDeltaY} + $ss->{teTop} + $ss->{teHeight} + 100,
            );
          })->then (sub {
            return $session->screenshot (element => $value->{content}->{targetElement});
          })->then (sub {
            if (($value->{content}->{imageType} // '') eq 'jpeg') {
              return $session->execute (q{
                var blob = new Blob ([Uint8Array.from (arguments[0])]);
                var img = document.createElement ('img');
                return new Promise ((ok, ng) => {
                  img.onload = ok;
                  img.onerror = ng;
                  img.src = URL.createObjectURL (blob);
                }).then (() => {
                  var canvas = document.createElement ('canvas');
                  canvas.width = img.naturalWidth;
                  canvas.height = img.naturalHeight;
                  var ctx = canvas.getContext ('2d');
                  ctx.drawImage (img, 0, 0);
                  return canvas.toDataURL ("image/jpeg", arguments[1]);
                });
              }, [
                [map { ord $_ } split //, $_[0]],
                $value->{content}->{imageQuality},
              ])->then (sub {
                $app->http->set_response_header ('content-type', 'image/jpeg');
                $headers->();
                my $v = $_[0]->json->{value};
                $v =~ s{^data:image/jpeg;base64,}{}g;
                $app->http->send_response_body_as_ref (\(decode_web_base64 $v));
                return $app->http->close_response_body;
              });
            } else { # PNG
              $app->http->set_response_header ('content-type', 'image/png');
              $headers->();
              $app->http->send_response_body_as_ref (\($_[0]));
              return $app->http->close_response_body;
            }
          }, sub {
            my $res = $_[0];
            $abort->("Screenshot error");
            return error_response $app, $sdata->{config}, 'Failed',
                "$wdskey: Processor error: (screenshot) $_[0]";
          });
        } else {
          $headers->();
          return $app->send_plain_text ($value->{content}->{value} // '');
        }
      }, sub {
        my $res = $_[0];
        $abort->("Execute error");
        return error_response $app, $sdata->{config}, 'Failed',
            "$wdskey: Processor error: $_[0]";
      });
        }, sub { # file not found or error
          return error_response $app, $sdata->{config}, 'Bad process',
              "$wdskey: Processor error: $_[0]";
        })->finally ($done);
      }); # session
    } $timeout;
  })->catch (sub {
    my $e = $_[0];
    if (UNIVERSAL::isa ($e, 'Warabe::App::Done')) {
      die $e;
    }
    if (UNIVERSAL::isa ($e, 'Promise::AbortError')) {
      $abort->("Timeout error");
      return $app->throw_error (504, reason_phrase => 'Process timeout ('.$timeout.')');
    }
    $abort->("Unknown error");
    die $e;
  });
} # run_processor

return sub {
  my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
  my $app = Warabe::App->new_from_http ($http);
  $app->execute_by_promise (sub {
    my $config = $app->http->server_state->data->{config};
    $app->http->set_response_header
        ('Strict-Transport-Security',
         'max-age=10886400; includeSubDomains; preload')
        if $config->{is_live} or $config->{is_test_script};

    my $path = $app->path_segments;

    if (@$path == 1 and $path->[0] eq 'robots.txt') {
      $app->http->set_response_header ('X-Rev' => $config->{git_sha});
      $app->http->set_response_last_modified (1556636400);
      if ($config->{is_live} or
          $config->{is_test_script} or
          $app->bare_param ('is_live')) {
        return $app->send_plain_text ("");
      } else {
        return $app->send_plain_text ("User-agent: *\x0ADisallow: /\x0A");
      }
    }
    
    if (@$path == 1 and $path->[0] eq 'favicon.ico') {
      return $app->throw_error (204);
    }

    return Promise->resolve->then (sub {
      if (@$path == 3 and $path->[0] eq '-' and $path->[1] eq 'health') {
        my $sdata = $app->http->server_state->data;
        my @c = grep { $_->[4] } values %{$sdata->{wds}}; # in use
        $app->http->set_response_header ('x-count', 0+@c);
        if (@c) {
          return $app->send_plain_text ("");
        }
        my $done = sub { };
        return Promise->resolve->then (sub {
          return promised_timeout {
            return get_session ($sdata, 'health')->then (sub {
              (undef, undef, $done, undef, undef, undef) = @{$_[0]};
              return 'done';
            });
          } 20;
        })->then (sub {
          $done->();
          return $app->send_plain_text ("");
        }, sub {
          my $e = $_[0];
          $done->();
          if (UNIVERSAL::isa ($e, 'Promise::AbortError')) {
            return $app->throw_error (504, reason_phrase => 'Timeout (20)');
          }
          die $e;
        });
      }
      
      my $origin = $app->http->get_request_header ('origin');
      if (defined $origin) {
        if ($config->{_cors_allowed}->{$origin}) {
          $app->http->set_response_header ('access-control-allow-origin', $origin);
        }
      }
      $app->http->add_response_header ('vary', 'origin');
      
      if (@$path == 1 and $path->[0] =~ /\A[0-9A-Za-z_]+\z/) {
        return run_processor ($app, $path->[0]);
      }

      return $app->send_error (404, reason_phrase => 'Page not found');
    })->catch (sub {
      return if UNIVERSAL::isa ($_[0], 'Warabe::App::Done');
      if (ref $_[0] eq 'HASH') {
        warn "ERROR: ".(perl2json_bytes_for_record $_[0])."\n";
      } else {
        warn "ERROR: $_[0]\n";
      }
      return $app->send_error (500);
    });
  });
};

=head1 LICENSE

Copyright 2020-2023 Wakaba <wakaba@suikawiki.org>.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public
License along with this program.  If not, see
<https://www.gnu.org/licenses/>.

=cut
