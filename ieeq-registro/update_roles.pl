use strict;
use warnings;
use FindBin;
require "$FindBin::Bin/db.pl";

print "Updating roles in the database...\n";

# Actualizar el rol a 'administrador'
execute_query_write("UPDATE usuarios SET rol = 'administrador' WHERE correo_electronico = 'admin.garcia\@ieeq.mx'");

# Actualizar el rol a 'funcionario'
execute_query_write("UPDATE usuarios SET rol = 'funcionario' WHERE correo_electronico = 'val.rodriguez\@ieeq.mx'");

# Actualizar el rol a 'integrante_organizacion'
execute_query_write("UPDATE usuarios SET rol = 'integrante_organizacion' WHERE correo_electronico = 'op.hernandez\@ieeq.mx'");

print "Roles updated successfully.\n";
