use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/lib');
use Tests;

Test {
  my $current = shift;
  return $current->client->request (path => ['notfounderror'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 404;
      is $res->body_bytes, '404 No processor';
    } $current->c;
  });
} n => 2, name => 'No processor';

Test {
  my $current = shift;
  return $current->client->request (path => ['processornotfound'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 500;
      is $res->header ('content-type'), 'text/plain; charset=us-ascii';
      is $res->body_bytes, "500 Bad process";
    } $current->c;
  });
} n => 3, name => 'File not found';

Test {
  my $current = shift;
  return $current->client->request (path => ['processorthrows'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 500;
      is $res->header ('content-type'), 'text/plain; charset=us-ascii';
      is $res->body_bytes, "500 Failed";
    } $current->c;
  });
} n => 3, name => 'throws';

Test {
  my $current = shift;
  return $current->client->request (path => ['processorrejects'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 500;
      is $res->header ('content-type'), 'text/plain; charset=us-ascii';
      is $res->body_bytes, "500 Failed";
    } $current->c;
  });
} n => 3, name => 'rejects';

Test {
  my $current = shift;
  return $current->client->request (path => ['badresult'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 500;
      is $res->header ('content-type'), 'text/plain; charset=us-ascii';
      is $res->body_bytes, "500 Bad result";
    } $current->c;
  });
} n => 3, name => 'Bad result';

Test {
  my $current = shift;
  return $current->client->request (path => ['badselectorerror'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 500;
      is $res->header ('content-type'), 'text/plain; charset=us-ascii';
      is $res->header ('cache-control'), undef;
      is $res->body_bytes, "500 Bad result";
    } $current->c;
  });
} n => 4, name => 'Bad selector';

Test {
  my $current = shift;
  return $current->client->request (path => ['processorresolves'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 403;
      is $res->header ('content-type'), 'text/plain; charset=utf-8';
      is $res->header ('cache-control'), undef;
      is $res->body_bytes, "Response あいうえお";
    } $current->c;
  });
} n => 4, name => 'resolves';

Test {
  my $current = shift;
  return $current->client->request (path => ['test1'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 400;
      is $res->header ('content-type'), 'text/plain; charset=utf-8';
      is $res->body_bytes, "Default response あいうえお";
    } $current->c;
  });
} n => 3, name => 'test1';

Test {
  my $current = shift;
  return $current->client->request (path => ['test2'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 201;
      is $res->header ('content-type'), 'image/png';
      like $res->body_bytes, qr{^\x89PNG};
      $current->save_artifact ($res->body_bytes, ['image'], 'png');
    } $current->c;
  });
} n => 3, name => 'test2', timeout => 180;

Test {
  my $current = shift;
  return $current->client->request (path => ['test3'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 201;
      is $res->header ('content-type'), 'image/png';
      like $res->body_bytes, qr{^\x89PNG};
      $current->save_artifact ($res->body_bytes, ['image'], 'png');
    } $current->c;
  });
} n => 3, name => 'test3 element screenshot', timeout => 180;

Test {
  my $current = shift;
  return $current->client->request (path => ['jpeg'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 201;
      is $res->header ('content-type'), 'image/jpeg';
      like $res->body_bytes, qr{^\xFF\xD8\xFF};
      $current->save_artifact ($res->body_bytes, ['image'], 'jpeg');
    } $current->c;
  });
} n => 3, name => 'element screenshot jpeg', timeout => 180;

Test {
  my $current = shift;
  return $current->client->request (path => ['jpeg'], params => {
    arg => '0.1',
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 201;
      is $res->header ('content-type'), 'image/jpeg';
      like $res->body_bytes, qr{^\xFF\xD8\xFF};
      $current->save_artifact ($res->body_bytes, ['image'], 'jpeg');
    } $current->c;
  });
} n => 3, name => 'element screenshot jpeg with quality', timeout => 180;

Test {
  my $current = shift;
  return $current->client->request (path => ['test4'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 201;
      is $res->header ('content-type'), 'image/png';
      is $res->header ('cache-control'), 'public,max-age=5331';
      like $res->body_bytes, qr{^\x89PNG};
      is $res->header ('access-control-allow-origin'), undef;
      is $res->header ('vary'), 'origin';
    } $current->c;
  });
} n => 6, name => 'test4', timeout => 180;

Test {
  my $current = shift;
  return $current->client->request (path => ['objectreturned'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 200;
      is $res->header ('content-type'), 'text/plain; charset=utf-8';
      like $res->body_bytes, qr{^HASH\(.+\)$};
    } $current->c;
  });
} n => 3, name => 'objectreturned';

Test {
  my $current = shift;
  return $current->client->request (path => ['nullreturned'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 200;
      is $res->header ('content-type'), 'text/plain; charset=utf-8';
      is $res->body_bytes, q{};
    } $current->c;
  });
} n => 3, name => 'nullreturned';

Test {
  my $current = shift;
  return $current->client->request (path => ['undefinedreturned'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 200;
      is $res->header ('content-type'), 'text/plain; charset=utf-8';
      is $res->body_bytes, q{};
    } $current->c;
  });
} n => 3, name => 'undefinedreturned';

Test {
  my $current = shift;
  return $current->client->request (path => ['defaultstatus'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 200;
      is $res->header ('content-type'), 'text/plain; charset=utf-8';
      is $res->body_bytes, q{Hello};
    } $current->c;
  });
} n => 3, name => 'default status code';

Test {
  my $current = shift;
  return $current->client->request (path => ['elementnotfound'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 500;
      is $res->body_bytes, q{500 Failed};
      $current->save_artifact ($res->body_bytes, ['image'], 'png');
    } $current->c;
  });
} n => 2, name => 'element not found';

Test {
  my $current = shift;
  return $current->client->request (path => ['test4'], headers => {
    origin => q<http://domain1.test>,
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 201;
      is $res->header ('content-type'), 'image/png';
      is $res->header ('cache-control'), 'public,max-age=5331';
      like $res->body_bytes, qr{^\x89PNG};
      is $res->header ('access-control-allow-origin'), undef;
    } $current->c;
  });
} n => 5, name => 'CORS bad origin';

Test {
  my $current = shift;
  return $current->client->request (path => ['test4'], headers => {
    origin => q<https://domain1.test>,
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 201;
      is $res->header ('content-type'), 'image/png';
      is $res->header ('cache-control'), 'public,max-age=5331';
      like $res->body_bytes, qr{^\x89PNG};
      is $res->header ('access-control-allow-origin'), 'https://domain1.test';
      is $res->header ('vary'), 'origin';
    } $current->c;
  });
} n => 6, name => 'CORS good origin';

Test {
  my $current = shift;
  return $current->client->request (path => ['echo'], params => {
    arg => do { use utf8; ["あいうえお?Q&A#2", "abc"] },
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 200;
      is $res->body_bytes, "string,あいうえお?Q&A#2";
    } $current->c;
  });
} n => 2, name => 'arg';

Test {
  my $current = shift;
  return $current->client->request (path => ['echo'], params => {
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 200;
      is $res->body_bytes, "string,";
    } $current->c;
  });
} n => 2, name => 'arg missing';

Test {
  my $current = shift;
  return $current->client->request (path => ['echosigned'], params => {
    signature => do { use utf8; signature ("", 'key1') },
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 200;
      is $res->body_bytes, "string,";
    } $current->c;
  });
} n => 2, name => 'empty arg with key';

Test {
  my $current = shift;
  return $current->client->request (path => ['echosigned'], params => {
    arg => do { use utf8; ["あいうえお?Q&A#2", "abc"] },
    signature => do { use utf8; signature ("あいうえお?Q&A#2", 'key1') },
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 200;
      is $res->body_bytes, "string,あいうえお?Q&A#2";
    } $current->c;
  });
} n => 2, name => 'arg with key';

Test {
  my $current = shift;
  return $current->client->request (path => ['echosigned'], params => {
    arg => do { use utf8; ["あいうえお?Q&A#2", "abc"] },
    signature => do { use utf8; signature ("あいうえお?Q&A#2", 'key') },
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 400;
      is $res->body_bytes, "400 Bad |signature|";
    } $current->c;
  });
} n => 2, name => 'arg with bad key';

Test {
  my $current = shift;
  return $current->client->request (path => ['echosigned'], params => {
    arg => do { use utf8; ["", "abc"] },
    signature => do { use utf8; signature ("", 'key') },
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 400;
      is $res->body_bytes, "400 Bad |signature|";
    } $current->c;
  });
} n => 2, name => 'empty arg with bad key';

Test {
  my $current = shift;
  return $current->client->request (path => ['echosigned'], params => {
    arg => do { use utf8; ["あいうえお?Q&A#2", "abc"] },
    signature => do { use utf8; signature ("あいうえお?Q&A#3", 'key1') },
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 400;
      is $res->body_bytes, "400 Bad |signature|";
    } $current->c;
  });
} n => 2, name => 'arg with bad signature';

Test {
  my $current = shift;
  return $current->client->request (path => ['timeout2'], params => {
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 504;
      is $res->body_bytes, "504 Process timeout (2)";
    } $current->c;
  });
} n => 2, name => 'timeout error';

Test {
  my $current = shift;
  return Promise->all ([
    map {
      my $key = $_;
      $current->client ($key)->request (path => ['sleep'], params => {
        arg => "5,$key",
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->status, 200;
          is $res->body_bytes, $key;
        } $current->c, name => $key;
      });
    } 1..10
  ]);
} n => 2*10, name => 'concurrents', timeout => 300;

Test {
  my $current = shift;
  my $p = $current->client (1)->request (path => ['sleep'], params => {
    arg => "10,abc",
  });
  return promised_sleep (5)->then (sub {
    return $current->client (2)->request (path => ['-', 'health', 'all']);
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 200;
      warn $res->header ('x-count');
    } $current->c;
    return Promise->all ([$p]);
  });
} n => 1, name => 'health check during worker is active';

Test {
  my $current = shift;
  return $current->client->request (path => ['ext1'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 200;
      is $res->body_bytes, "https://www.example.com/";
    } $current->c;
  });
} n => 2, name => 'external page';

Test {
  my $current = shift;
  return $current->client->request (path => ['extbad'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 500;
      is $res->body_bytes, "500 Bad process";
    } $current->c;
  });
} n => 2, name => 'external page_url broken';

RUN;

=head1 LICENSE

Copyright 2016-2023 Wakaba <wakaba@suikawiki.org>.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Affero General Public License for more details.

You does not have received a copy of the GNU Affero General Public
License along with this program, see <https://www.gnu.org/licenses/>.

=cut
