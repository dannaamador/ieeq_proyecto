#!C:\xampp\perl\bin\perl.exe
use strict;
use warnings;

# Configuración centralizada de base de datos
our $db_host = '172.23.80.1';
our $db_port = '3306';
our $db_name = 'ieeq_registro';
our $db_user = 'root';
our $db_pass = 'danna1q2w';

# Ruta del cliente MySQL nativo de XAMPP (bypass de DBD::mysql que falla en Windows)
our $mysql_bin = 'C:\\xampp\\mysql\\bin\\mysql.exe';

# Función para obtener un usuario directamente usando el cliente nativo
# Busca un usuario por su correo electrónico y retorna sus datos en un hash
sub get_user_by_email {
    my ($email) = @_;
    
    # Escapar comillas para prevenir inyección SQL en consola de comandos
    $email =~ s/'/\\'/g;
    
    # Consulta SQL para recuperar información del usuario por correo electrónico
    my $query = "SELECT id_usuario, username, nombre_completo, rol, contrasena, activo FROM usuarios WHERE correo_electronico = '$email'";
    
    # Ejecutar consulta en modo Batch (-B) que devuelve los resultados separados por tabulaciones
    my $cmd = "\"$mysql_bin\" -h $db_host -P $db_port -u $db_user -p$db_pass $db_name -B -e \"$query\"";
    
    my $output = `$cmd 2>&1`;
    my @lines = split /\r?\n/, $output;
    
    # Si la salida tiene más de una línea y la primera tiene nuestras columnas
    if (@lines > 1 && $lines[0] =~ /id_usuario/) {
        my @headers = split /\t/, $lines[0];
        my @values = split /\t/, $lines[1];
        
        # Mapear los encabezados y valores en un hash
        my $user_data = {};
        for my $i (0 .. $#headers) {
            $headers[$i] =~ s/^\s+|\s+$//g;
            $values[$i] =~ s/^\s+|\s+$//g if defined $values[$i];
            $user_data->{ $headers[$i] } = $values[$i];
        }
        return $user_data;
    }
    
    return undef;
}

# Funciones base para simular Prepared Statements a través de la CLI nativa
# Esta función reemplaza los signos de interrogación por valores escapados de forma segura
sub _build_safe_query {
    my ($sql, @params) = @_;
    my @safe_params;
    
    # Procesar cada parámetro
    for my $param (@params) {
        if (!defined $param) {
            push @safe_params, 'NULL';
        } else {
            my $temp = $param;
            $temp =~ s/'/''/g; # Escape SQL standard para comillas simples
            push @safe_params, "'$temp'";
        }
    }
    # Reemplazar de manera global el signo de interrogación por el valor seguro procesado
    $sql =~ s/\?/shift(@safe_params)/eg;
    
    # Escapar comillas dobles para que no rompa el string del comando en Windows CMD
    $sql =~ s/"/\\"/g;
    return $sql;
}

# Función para ejecutar consultas SELECT y retornar una lista de hashes
sub execute_query_list {
    my ($sql, @params) = @_;
    my $safe_sql = _build_safe_query($sql, @params);
    my $cmd = "\"$mysql_bin\" -h $db_host -P $db_port -u $db_user -p$db_pass $db_name -B -e \"$safe_sql\"";
    
    my $output = `$cmd 2>&1`;
    my @lines = split /\r?\n/, $output;
    my @results;
    
    # Retornar vacío si la ejecución falló o si no hay resultados
    return () if $? != 0 || !@lines;
    
    # Extraer encabezados de la primera línea
    my @headers = split /\t/, shift @lines;
    for my $i (0 .. $#headers) { $headers[$i] =~ s/^\s+|\s+$//g; }
    
    # Construir un array de hashes por cada línea de resultados devuelta
    for my $line (@lines) {
        my @values = split /\t/, $line;
        my %row;
        for my $i (0 .. $#headers) {
            $values[$i] =~ s/^\s+|\s+$//g if defined $values[$i];
            $row{$headers[$i]} = $values[$i];
        }
        push @results, \%row;
    }
    return @results;
}

# Función para ejecutar consultas INSERT, UPDATE y DELETE
sub execute_query_write {
    my ($sql, @params) = @_;
    my $safe_sql = _build_safe_query($sql, @params);
    my $cmd = "\"$mysql_bin\" -h $db_host -P $db_port -u $db_user -p$db_pass $db_name -e \"$safe_sql\"";
    
    my $output = `$cmd 2>&1`;
    # Retorna verdadero si el comando CMD tuvo éxito (código de salida igual a 0)
    return $? == 0;
}

1;
