use strict;
use warnings;
open my $fh, '>', 'test_output.html';
my $test = <<"HTML";
    <script>
        \$(document).ready(function() {
            var tabla = \$('#usuariosTable').DataTable({
                "responsive": true
            });
        });
        function x() {
            var email = "admin.esmgd\@ieeq.mx";
        }
    </script>
HTML
print $fh $test;
close $fh;
