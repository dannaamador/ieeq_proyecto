#!C:\xampp\perl\bin\perl.exe
use strict;
use warnings;
use Encode qw(decode_utf8);

# Configuración centralizada de base de datos
our $db_host = '127.0.0.1';
our $db_port = '3306';
our $db_name = 'ieeq_registro';
our $db_user = 'root';
our $db_pass = 'danna1q2w';

# Ruta del cliente MySQL nativo de XAMPP (bypass de DBD::mysql que falla en Windows)
our $mysql_bin = 'C:\\xampp\\mysql\\bin\\mysql.exe';

# Función para obtener un usuario directamente usando el cliente nativo
sub get_user_by_username {
    my ($username) = @_;
    
    # Escapar comillas para prevenir inyección SQL en consola
    $username =~ s/'/\\'/g;
    
    my $query = "SELECT id_usuario, username, nombre_completo, rol, contrasena, activo FROM usuarios WHERE username = '$username' OR correo_electronico = '$username'";
    
    # Ejecutar consulta en modo Batch (-B) que devuelve separado por tabulaciones
    my $cmd = "\"$mysql_bin\" --default-character-set=utf8mb4 -h $db_host -P $db_port -u $db_user -p$db_pass $db_name -B -e \"$query\"";
    
    my $output = decode_utf8(`$cmd 2>&1`);
    
    my @lines = split /\r?\n/, $output;
    
    # Si la salida tiene más de una línea y la primera tiene nuestras columnas
    if (@lines > 1 && $lines[0] =~ /id_usuario/) {
        my @headers = split /\t/, $lines[0];
        my @values = split /\t/, $lines[1];
        
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
sub _build_safe_query {
    my ($sql, @params) = @_;
    my @safe_params;
    for my $param (@params) {
        if (!defined $param) {
            push @safe_params, 'NULL';
        } else {
            my $temp = $param;
            $temp =~ s/'/''/g; # Escape SQL standard
            push @safe_params, "'$temp'";
        }
    }
    $sql =~ s/\?/shift(@safe_params)/eg;
    
    # Escapar comillas dobles para que no rompa el string del CMD de Windows
    $sql =~ s/"/\\"/g;
    return $sql;
}

sub execute_query_list {
    my ($sql, @params) = @_;
    my $safe_sql = _build_safe_query($sql, @params);
    my $cmd = "\"$mysql_bin\" --default-character-set=utf8mb4 -h $db_host -P $db_port -u $db_user -p$db_pass $db_name -B -e \"$safe_sql\"";
    
    my $output = decode_utf8(`$cmd 2>&1`);
    my @lines = split /\r?\n/, $output;
    my @results;
    
    return () if $? != 0 || !@lines;
    
    my @headers = split /\t/, shift @lines;
    for my $i (0 .. $#headers) { $headers[$i] =~ s/^\s+|\s+$//g; }
    
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

sub execute_query_write {
    my ($sql, @params) = @_;
    my $safe_sql = _build_safe_query($sql, @params);
    my $cmd = "\"$mysql_bin\" --default-character-set=utf8mb4 -h $db_host -P $db_port -u $db_user -p$db_pass $db_name -e \"$safe_sql\"";
    
    my $output = decode_utf8(`$cmd 2>&1`);
    return $? == 0; # Verdadero si tuvo éxito
}

1;
