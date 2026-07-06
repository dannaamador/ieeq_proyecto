#!/usr/bin/perl
use strict;
use warnings;

our $db_host = '127.0.0.1';
our $db_port = '3306';
our $db_name = 'ieeq_registro';
our $db_user = 'root';
our $db_pass = 'root1234';
our $mysql_bin = '/usr/bin/mysql';

sub _run_query {
    my ($query) = @_;
    my $cmd = "$mysql_bin --default-character-set=utf8 -h $db_host -P $db_port -u $db_user -p$db_pass $db_name -B -e \"$query\" 2>&1";
    my $output = `$cmd`;
    my @lines = grep { !/warning/i } split(/\r?\n/, $output);
    return @lines;
}

sub get_user_by_username {
    my ($username) = @_;
    $username =~ s/'/\\'/g;
    my $query = "SELECT id_usuario, username, nombre_completo, rol, contrasena, activo FROM usuarios WHERE username = '$username'";
    my @lines = _run_query($query);
    return undef if @lines < 2 || $lines[0] !~ /id_usuario/;
    my @headers = split /\t/, $lines[0];
    my @values  = split /\t/, $lines[1];
    my $user_data = {};
    for my $i (0 .. $#headers) {
        $headers[$i] =~ s/^\s+|\s+$//g;
        $values[$i]  =~ s/^\s+|\s+$//g if defined $values[$i];
        $user_data->{ $headers[$i] } = $values[$i];
    }
    return $user_data;
}

sub get_user_by_email {
    my ($email) = @_;
    $email =~ s/'/\\'/g;
    my $query = "SELECT id_usuario, username, nombre_completo, rol, contrasena, activo FROM usuarios WHERE correo_electronico = '$email'";
    my @lines = _run_query($query);
    return undef if @lines < 2 || $lines[0] !~ /id_usuario/;
    my @headers = split /\t/, $lines[0];
    my @values  = split /\t/, $lines[1];
    my $user_data = {};
    for my $i (0 .. $#headers) {
        $headers[$i] =~ s/^\s+|\s+$//g;
        $values[$i]  =~ s/^\s+|\s+$//g if defined $values[$i];
        $user_data->{ $headers[$i] } = $values[$i];
    }
    return $user_data;
}

sub _build_safe_query {
    my ($sql, @params) = @_;
    my @safe_params;
    for my $param (@params) {
        if (!defined $param) {
            push @safe_params, 'NULL';
        } else {
            my $temp = $param;
            $temp =~ s/'/''/g;
            push @safe_params, "'$temp'";
        }
    }
    $sql =~ s/\?/shift(@safe_params)/eg;
    $sql =~ s/"/\\"/g;
    return $sql;
}

sub execute_query_list {
    my ($sql, @params) = @_;
    my $safe_sql = _build_safe_query($sql, @params);
    my @lines = _run_query($safe_sql);
    my @results;
    return () if !@lines || @lines < 2;
    my @headers = split /\t/, shift @lines;
    for my $i (0 .. $#headers) { $headers[$i] =~ s/^\s+|\s+$//g; }
    for my $line (@lines) {
        my @values = split /\t/, $line;
        my %row;
        for my $i (0 .. $#headers) {
            $values[$i] =~ s/^\s+|\s+$//g if defined $values[$i];
            $row{ $headers[$i] } = $values[$i];
        }
        push @results, \%row;
    }
    return @results;
}

sub execute_query_write {
    my ($sql, @params) = @_;
    my $safe_sql = _build_safe_query($sql, @params);
    my $cmd = "$mysql_bin --default-character-set=utf8 -h $db_host -P $db_port -u $db_user -p$db_pass $db_name -e \"$safe_sql\" 2>&1";
    my $output = `$cmd`;
    return $? == 0;
}

1;
