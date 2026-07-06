use strict;
use warnings;
use HTTP::Tiny;
use Data::Dumper;

my $http = HTTP::Tiny->new();
my $res = $http->post_form('http://localhost/ieeq-registro/login.pl', {
    correo_electronico => 'admin.esmgd@ieeq.mx',
    password => 'danna1q2w'
});

my $cookie = $res->{headers}{'set-cookie'} || '';
$cookie =~ s/;.*//;

my $res2 = HTTP::Tiny->new(default_headers => {Cookie => $cookie})->get('http://localhost/ieeq-registro/gestion_usuarios.pl');
open my $f, '>', 'out.html';
print $f $res2->{content};
close $f;
print "Done.\n";
