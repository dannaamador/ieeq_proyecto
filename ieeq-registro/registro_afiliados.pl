#!C:\xampp\perl\bin\perl.exe
use strict;
use warnings;
use utf8;
use CGI;
use CGI::Session;
use JSON;
use FindBin;
use File::Path qw(make_path);
use MIME::Base64;
use Time::Piece;

require "$FindBin::Bin/db.pl";

# Configurar salida UTF-8
binmode(STDOUT, ":utf8");

# Evitar doble codificación UTF-8 en encode_json al usar binmode :utf8
no warnings 'redefine';
sub encode_json ($) {
    return JSON->new->utf8(0)->encode($_[0]);
}
use warnings 'redefine';

my $cgi = CGI->new;
my $session = CGI::Session->new(undef, $cgi, {Directory => "$FindBin::Bin/.sesiones"});

my $rol = $session->param('rol') || '';
my $id_usuario = $session->param('id_usuario') || '';
my $nombre_completo = $session->param('nombre_completo') || '';
my $username = $session->param('username') || '';

# Redirecciones de seguridad
if (!$id_usuario) {
    print $cgi->redirect(-uri => 'login.pl');
    exit;
}

if ($rol ne 'integrante_organizacion' && $rol ne 'administrador') {
    print $cgi->redirect(-uri => 'dashboard.pl');
    exit;
}

sub guardar_archivo_base64 {
    my ($data_b64, $field, $id_afil) = @_;
    if ($data_b64 =~ /^data:image\/(png|jpeg|jpg);base64,(.*)$/) {
        my $ext = $1 eq 'png' ? 'png' : 'jpg';
        my $decoded = decode_base64($2);
        
        my $folder = 'fotos';
        if ($field eq 'foto_anverso_ine') { $folder = 'ine/anverso'; }
        elsif ($field eq 'foto_reverso_ine') { $folder = 'ine/reverso'; }
        elsif ($field eq 'firma') { $folder = 'firmas'; }
        
        my $dir_path = "c:/xampp/htdocs/i/ieeq_proyecto/ieeq-registro/uploads/$folder";
        make_path($dir_path) unless -d $dir_path;
        
        my $filename = "${field}_" . time() . "_" . int(rand(10000)) . "." . $ext;
        my $path = "uploads/$folder/$filename";
        
        open my $fh, '>', "c:/xampp/htdocs/i/ieeq_proyecto/ieeq-registro/$path" or die $!;
        binmode $fh;
        print $fh $decoded;
        close $fh;
        return $path;
    }
    return undef;
}

sub obtener_fecha_espanol {
    my $t = shift || Time::Piece->new;
    my @meses = ('enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre');
    my $dia = $t->mday;
    my $mes = $meses[$t->mon - 1];
    my $anio = $t->year;
    my $hora_12 = $t->strftime('%I:%M');
    my $ampm = $t->hour >= 12 ? 'p.m.' : 'a.m.';
    
    $hora_12 =~ s/^0//;
    return "$dia de $mes de $anio a las $hora_12 $ampm";
}

# ==========================================
# PROCESAR ACCIÓN AJAX POST (GUARDAR)
# ==========================================
my $accion = $cgi->param('accion') || '';

if ($cgi->request_method() eq 'POST' && $accion eq 'guardar') {
    my $id_afil = $cgi->param('id_afiliacion') || 0;
    my $nombre = $cgi->param('nombre') || '';
    my $apellido_paterno = $cgi->param('apellido_paterno') || '';
    my $apellido_materno = $cgi->param('apellido_materno') || '';
    my $domicilio_calle = $cgi->param('domicilio_calle') || '';
    my $domicilio_numero = $cgi->param('domicilio_numero') || '';
    my $domicilio_colonia = $cgi->param('domicilio_colonia') || '';
    my $domicilio_cp = $cgi->param('domicilio_cp') || '';
    my $clave_elector = $cgi->param('clave_elector') || '';
    my $ocr = $cgi->param('ocr') || '';
    my $cic = $cgi->param('cic') || '';
    my $curp = $cgi->param('curp') || '';
    my $id_municipio_afiliacion = $cgi->param('id_municipio_afiliacion') || 0;
    
    my $acepta_libre = $cgi->param('acepta_afiliacion_libre') ? 1 : 0;
    my $acepta_docs = $cgi->param('acepta_documentos') ? 1 : 0;
    my $acepta_no_otro = $cgi->param('acepta_no_otro_partido') ? 1 : 0;
    my $acepta_aviso = $cgi->param('acepta_aviso_privacidad') ? 1 : 0;

    # Validar campos obligatorios
    if (!$nombre || !$apellido_paterno || !$domicilio_calle || !$clave_elector || !$ocr || !$cic || !$curp || !$id_municipio_afiliacion) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'Por favor, complete todos los campos obligatorios.' });
        exit;
    }

    # Validar formato y longitud
    $clave_elector = uc($clave_elector);
    $clave_elector =~ s/\s+//g;
    if (length($clave_elector) != 18) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'La Clave de Elector debe tener exactamente 18 caracteres.' });
        exit;
    }
    if ($ocr !~ /^\d{13}$/) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'El Número OCR debe tener exactamente 13 dígitos numéricos.' });
        exit;
    }
    if ($cic !~ /^\d{10}$/) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'El Número CIC debe tener exactamente 10 dígitos numéricos.' });
        exit;
    }
    $curp = uc($curp);
    $curp =~ s/\s+//g;
    if (length($curp) != 18) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'La CURP debe tener exactamente 18 caracteres.' });
        exit;
    }

    # Fetch user's association ID from POST or fallbacks
    my $id_asoc = $cgi->param('id_asociacion') || 0;
    if (!$id_asoc) {
        my @usr_data = execute_query_list("SELECT id_asociacion FROM usuarios WHERE id_usuario = ?", $id_usuario);
        $id_asoc = ($usr_data[0] && $usr_data[0]->{id_asociacion}) ? $usr_data[0]->{id_asociacion} : 0;
    }
    if (!$id_asoc) {
        my @asocs = execute_query_list("SELECT id_asociacion FROM asociaciones_politicas LIMIT 1");
        $id_asoc = @asocs ? $asocs[0]->{id_asociacion} : 1;
    }

    # Decodificar fotos / firmas
    my $foto_anv = guardar_archivo_base64($cgi->param('foto_anverso_ine_base64') || '', 'foto_anverso_ine', $id_afil);
    my $foto_rev = guardar_archivo_base64($cgi->param('foto_reverso_ine_base64') || '', 'foto_reverso_ine', $id_afil);
    my $foto_per = guardar_archivo_base64($cgi->param('foto_persona_base64') || '', 'foto_persona', $id_afil);
    my $firma_path = guardar_archivo_base64($cgi->param('firma_base64') || '', 'firma', $id_afil);

    my $ok = 0;
    if ($id_afil) {
        # Validar que está en estatus NUEVA y no está eliminada
        my @exist = execute_query_list("SELECT * FROM afiliaciones WHERE id_afiliacion = ? AND estatus = 'NUEVA' AND fecha_eliminacion IS NULL", $id_afil);
        if (!@exist) {
            print $cgi->header(-type => 'application/json', -charset => 'utf-8');
            print encode_json({ success => 0, message => 'Registro no encontrado o no modificable.' });
            exit;
        }

        # Si no es administrador y no es su registro, rechazar
        if ($rol ne 'administrador' && $exist[0]->{id_registrador} != $id_usuario) {
            print $cgi->header(-type => 'application/json', -charset => 'utf-8');
            print encode_json({ success => 0, message => 'No autorizado para editar este registro.' });
            exit;
        }

        # Conservar rutas de archivos anteriores si no se subieron nuevas
        $foto_anv ||= $exist[0]->{foto_anverso_ine};
        $foto_rev ||= $exist[0]->{foto_reverso_ine};
        $foto_per ||= $exist[0]->{foto_persona};
        $firma_path ||= $exist[0]->{firma};

        $ok = execute_query_write("
            UPDATE afiliaciones SET
                nombre = ?,
                apellido_paterno = ?,
                apellido_materno = ?,
                domicilio_calle = ?,
                domicilio_numero = ?,
                domicilio_colonia = ?,
                domicilio_cp = ?,
                clave_elector = ?,
                ocr = ?,
                cic = ?,
                curp = ?,
                id_municipio_afiliacion = ?,
                id_asociacion = ?,
                foto_anverso_ine = ?,
                foto_reverso_ine = ?,
                foto_persona = ?,
                firma = ?,
                acepta_afiliacion_libre = ?,
                acepta_documentos = ?,
                acepta_no_otro_partido = ?,
                acepta_aviso_privacidad = ?,
                fecha_actualizacion = NOW(),
                id_usuario_actualizacion = ?
            WHERE id_afiliacion = ?
        ", $nombre, $apellido_paterno, $apellido_materno, $domicilio_calle, $domicilio_numero, $domicilio_colonia, $domicilio_cp, $clave_elector, $ocr, $cic, $curp, $id_municipio_afiliacion, $id_asoc, $foto_anv, $foto_rev, $foto_per, $firma_path, $acepta_libre, $acepta_docs, $acepta_no_otro, $acepta_aviso, $id_usuario, $id_afil);

        if ($ok) {
            execute_query_write(
                "INSERT INTO bitacora (id_usuario, accion, modulo, detalles, fecha) VALUES (?, 'EDICION', 'afiliaciones', ?, NOW())",
                $id_usuario, "Afiliación ID $id_afil modificada por auxiliar"
            );
        }
    } else {
        # Validar duplicados de clave elector en el sistema
        my @dup_clave = execute_query_list("SELECT id_afiliacion FROM afiliaciones WHERE clave_elector = ? AND fecha_eliminacion IS NULL", $clave_elector);
        if (@dup_clave) {
            print $cgi->header(-type => 'application/json', -charset => 'utf-8');
            print encode_json({ success => 0, message => 'La Clave de Elector ya se encuentra registrada en el sistema.' });
            exit;
        }

        # Validar que los archivos de fotos obligatorios estén presentes al crear una nueva
        if (!$foto_anv || !$foto_rev || !$foto_per || !$firma_path) {
            print $cgi->header(-type => 'application/json', -charset => 'utf-8');
            print encode_json({ success => 0, message => 'Por favor, suba todas las imágenes y guarde la firma digital.' });
            exit;
        }

        $ok = execute_query_write("
            INSERT INTO afiliaciones (
                nombre, apellido_paterno, apellido_materno,
                domicilio_calle, domicilio_numero, domicilio_colonia, domicilio_cp,
                clave_elector, ocr, cic, curp, id_municipio_afiliacion,
                foto_anverso_ine, foto_reverso_ine, foto_persona, firma,
                acepta_afiliacion_libre, acepta_documentos, acepta_no_otro_partido, acepta_aviso_privacidad,
                estatus, id_registrador, id_asociacion, fecha_hora_afiliacion, fecha_creacion
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'NUEVA', ?, ?, NOW(), NOW())
        ", $nombre, $apellido_paterno, $apellido_materno, $domicilio_calle, $domicilio_numero, $domicilio_colonia, $domicilio_cp, $clave_elector, $ocr, $cic, $curp, $id_municipio_afiliacion, $foto_anv, $foto_rev, $foto_per, $firma_path, $acepta_libre, $acepta_docs, $acepta_no_otro, $acepta_aviso, $id_usuario, $id_asoc);

        if ($ok) {
            my @last_ids = execute_query_list("SELECT LAST_INSERT_ID() as id");
            my $id_afiliacion = $last_ids[0]->{id} || 0;
            execute_query_write(
                "INSERT INTO bitacora (id_usuario, accion, modulo, detalles, fecha) VALUES (?, 'REGISTRO', 'afiliaciones', ?, NOW())",
                $id_usuario, "Nueva afiliación ID $id_afiliacion registrada por auxiliar"
            );
        }
    }

    if ($ok) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 1, message => 'Registro guardado exitosamente.' });
        exit;
    } else {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'Error al guardar el registro en la base de datos.' });
        exit;
    }
}

# ==========================================
# CARGAR DATOS PARA MODO EDICIÓN / COMBOS
# ==========================================
my @municipios_db = execute_query_list("SELECT id_municipio, nombre FROM municipios ORDER BY nombre");

my $id_edit = $cgi->param('id') || 0;
my $af_edit = undef;
my $fecha_registro_str = '';

if ($id_edit) {
    my @af_list = execute_query_list("
        SELECT *, DATE_FORMAT(fecha_hora_afiliacion,'%Y-%m-%d %H:%i:%s') AS fecha_raw
        FROM afiliaciones 
        WHERE id_afiliacion = ? AND estatus = 'NUEVA' AND fecha_eliminacion IS NULL
        LIMIT 1
    ", $id_edit);
    if (@af_list) {
        if ($rol eq 'administrador' || $af_list[0]->{id_registrador} == $id_usuario) {
            $af_edit = $af_list[0];
            my $t = Time::Piece->strptime($af_edit->{fecha_raw}, '%Y-%m-%d %H:%M:%S');
            $fecha_registro_str = obtener_fecha_espanol($t);
        }
    }
}

$fecha_registro_str ||= obtener_fecha_espanol();

# Iniciales del Integrante Logueado para la barra lateral
my $words_user = $nombre_completo;
$words_user =~ s/^\s+|\s+$//g;
my @parts_user = split /\s+/, $words_user;
my $initials_user = 'U';
if (@parts_user > 0) {
    $initials_user = uc(substr($parts_user[0], 0, 1));
    if (@parts_user > 1) {
        $initials_user .= uc(substr($parts_user[1], 0, 1));
    }
}

# Municipios options HTML helper
my $municipios_options = '<option value="">— Selecciona un municipio —</option>';
for my $m (@municipios_db) {
    my $sel = '';
    if ($af_edit && $af_edit->{id_municipio_afiliacion} == $m->{id_municipio}) {
        $sel = 'selected';
    }
    $municipios_options .= sprintf('<option value="%d" %s>%s</option>', $m->{id_municipio}, $sel, $m->{nombre});
}

# Asociaciones options HTML helper
my @asociaciones_db = execute_query_list("SELECT id_asociacion, nombre FROM asociaciones_politicas ORDER BY nombre");
my $asociaciones_options = '<option value="">— Selecciona una asociación —</option>';
for my $a (@asociaciones_db) {
    my $sel = '';
    if ($af_edit && $af_edit->{id_asociacion} == $a->{id_asociacion}) {
        $sel = 'selected';
    } elsif (!$af_edit && @asociaciones_db == 1) {
        $sel = 'selected'; # Pre-select if it is the only one available
    }
    $asociaciones_options .= sprintf('<option value="%d" %s>%s</option>', $a->{id_asociacion}, $sel, $a->{nombre});
}

print $cgi->header(
    -type => 'text/html', 
    -charset => 'utf-8',
    -expires => 'now',
    -Cache_Control => 'no-store, no-cache, must-revalidate, max-age=0',
    -Pragma => 'no-cache'
);

print <<"HTML";
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Registro de Afiliaciones - IEEQ</title>
    
    <!-- CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons\@1.11.3/font/bootstrap-icons.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght\@300;400;500;600;700&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/sweetalert2\@11"></script>
    
    <style>
        body { font-family: 'Outfit', sans-serif; background-color: #f5f5f8; overflow-x: hidden; }
        #content { margin-left: 260px; min-height: 100vh; padding: 2rem; transition: all 0.3s; }
        
        .top-header {
            background: #ffffff; padding: 1rem 1.5rem; border-radius: 14px;
            box-shadow: 0 2px 12px rgba(0,0,0,0.05); margin-bottom: 2rem;
            display: flex; justify-content: space-between; align-items: center;
        }
        
        .section-card {
            background: #fff; border-radius: 16px; box-shadow: 0 4px 20px rgba(0,0,0,0.04);
            padding: 2rem; margin-bottom: 2rem; border: none;
        }
        .section-title {
            font-size: 1.05rem; font-weight: 700; color: #1a1a2e;
            margin-bottom: 1.5rem; display: flex; align-items: center; gap: 10px;
        }
        .section-title i { color: #6B2D8B; font-size: 1.25rem; }
        
        .form-control, .form-select {
            border-radius: 12px; padding: 0.75rem 1rem; border: 1.5px solid #dee2e6;
            background-color: #ffffff; font-size: 0.95rem; transition: all 0.2s;
        }
        .form-control:focus, .form-select:focus {
            border-color: #6B2D8B; box-shadow: 0 0 0 0.25rem rgba(107, 45, 139, 0.15);
        }
        .form-label {
            font-weight: 600; color: #495057; margin-bottom: 0.5rem;
            font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.5px;
        }
        
        /* ── upload cards ── */
        .upload-card {
            border: 2px dashed #d1d5db; border-radius: 12px; background: #f9fafb;
            padding: 1.5rem 1rem; text-align: center; cursor: pointer; transition: all 0.2s;
            height: 160px; display: flex; flex-direction: column; align-items: center;
            justify-content: center; position: relative; overflow: hidden;
        }
        .upload-card:hover { border-color: #6B2D8B; background: #f3e8f8; }
        .upload-card img { width: 100%; height: 100%; object-fit: cover; position: absolute; top: 0; left: 0; }
        .upload-card i { font-size: 1.8rem; color: #6B2D8B; margin-bottom: 0.5rem; }
        .upload-card span { font-size: 0.78rem; color: #6c757d; font-weight: 500; }
        
        /* ── signature canvas ── */
        .canvas-wrap { border: 1px solid #dee2e6; border-radius: 12px; background: #fff; overflow: hidden; position: relative; }
        #canvasFirma { width: 100%; height: 110px; display: block; cursor: crosshair; }
        
        .btn-purple { background-color: #6B2D8B; color: white; border: none; }
        .btn-purple:hover { background-color: #4a1f61; color: white; box-shadow: 0 4px 10px rgba(107, 45, 139, 0.25); }
        .btn-purple:active { background-color: #3b174a; }
        
        /* ── Progress bar Acceptance ── */
        .progress-container { background: #e9ecef; border-radius: 8px; height: 8px; overflow: hidden; }
        .progress-bar-success { background-color: #198754; height: 100%; width: 0%; transition: width 0.3s ease; }
        
        .form-check-input:checked { background-color: #6B2D8B; border-color: #6B2D8B; }
        
        \@media (max-width: 991px) {
            #content { margin-left: 0; padding: 1rem; }
        }
    </style>
</head>
<body>
HTML

require "$FindBin::Bin/_sidebar_admin.pl";

my $id_val = $af_edit ? $af_edit->{id_afiliacion} : 0;
my $nom_val = $af_edit ? $af_edit->{nombre} : '';
my $ap_val = $af_edit ? $af_edit->{apellido_paterno} : '';
my $am_val = $af_edit ? $af_edit->{apellido_materno} : '';
my $dom_val = $af_edit ? $af_edit->{domicilio_calle} : '';
my $num_val = $af_edit ? $af_edit->{domicilio_numero} : '';
my $col_val = $af_edit ? $af_edit->{domicilio_colonia} : '';
my $cp_val  = $af_edit ? $af_edit->{domicilio_cp} : '';
my $cle_val = $af_edit ? $af_edit->{clave_elector} : '';
my $ocr_val = $af_edit ? $af_edit->{ocr} : '';
my $cic_val = $af_edit ? $af_edit->{cic} : '';
my $cur_val = $af_edit ? $af_edit->{curp} : '';

my $chk_libre = ($af_edit && $af_edit->{acepta_afiliacion_libre}) ? 'checked' : '';
my $chk_docs = ($af_edit && $af_edit->{acepta_documentos}) ? 'checked' : '';
my $chk_no_otro = ($af_edit && $af_edit->{acepta_no_otro_partido}) ? 'checked' : '';
my $chk_aviso = ($af_edit && $af_edit->{acepta_aviso_privacidad}) ? 'checked' : '';

print <<"HTML";
    <div id="content">
        <!-- Top header bar -->
        <div class="top-header d-flex align-items-center justify-content-between">
            <div class="d-flex align-items-center gap-2">
                <button id="sidebarToggle" class="btn btn-outline-secondary d-lg-none me-3" type="button" style="border-radius: 8px;">
                    <i class="bi bi-list"></i>
                </button>
                <div>
                    <h4 class="mb-0 text-dark fw-bold">Registro de Afiliaciones</h4>
                    <p class="text-muted mb-0 small">Captura los datos de identificación y evidencia fotográfica del ciudadano (RF-03).</p>
                </div>
            </div>
            <div class="text-muted d-none d-md-block fs-6">
                Instituto Electoral del Estado de Querétaro
            </div>
        </div>

        <form id="afiliacionForm" autocomplete="off" novalidate>
            <input type="hidden" name="id_afiliacion" value="$id_val">

            <!-- SECCIÓN 1: DATOS DE IDENTIFICACIÓN -->
            <div class="section-card">
                <div class="section-title">
                    <i class="bi bi-person-vcard"></i> Sección 1 — Datos de Identificación
                </div>
                <div class="row mb-3">
                    <div class="col-md-4">
                        <label class="form-label" for="apellido_paterno">Apellido paterno *</label>
                        <input type="text" class="form-control" id="apellido_paterno" name="apellido_paterno" required value="$ap_val" placeholder="Primer apellido">
                    </div>
                    <div class="col-md-4">
                        <label class="form-label" for="apellido_materno">Apellido materno</label>
                        <input type="text" class="form-control" id="apellido_materno" name="apellido_materno" value="$am_val" placeholder="Segundo apellido">
                    </div>
                    <div class="col-md-4">
                        <label class="form-label" for="nombre">Nombre(s) *</label>
                        <input type="text" class="form-control" id="nombre" name="nombre" required value="$nom_val" placeholder="Nombre(s) de pila">
                    </div>
                </div>
                <div class="row mb-3">
                    <div class="col-md-5">
                        <label class="form-label" for="domicilio_calle">Calle *</label>
                        <input type="text" class="form-control" id="domicilio_calle" name="domicilio_calle" required value="$dom_val" placeholder="Calle / Avenida">
                    </div>
                    <div class="col-md-2">
                        <label class="form-label" for="domicilio_numero">Número</label>
                        <input type="text" class="form-control" id="domicilio_numero" name="domicilio_numero" value="$num_val" placeholder="Ext / Int">
                    </div>
                    <div class="col-md-3">
                        <label class="form-label" for="domicilio_colonia">Colonia</label>
                        <input type="text" class="form-control" id="domicilio_colonia" name="domicilio_colonia" value="$col_val" placeholder="Colonia">
                    </div>
                    <div class="col-md-2">
                        <label class="form-label" for="domicilio_cp">C.P.</label>
                        <input type="text" class="form-control" id="domicilio_cp" name="domicilio_cp" value="$cp_val" placeholder="C.P." maxlength="5">
                    </div>
                </div>
                <div class="row">
                    <div class="col-md-3">
                        <label class="form-label" for="clave_elector">Clave de Elector *</label>
                        <input type="text" class="form-control" id="clave_elector" name="clave_elector" required value="$cle_val" placeholder="18 CARACTERES" maxlength="18" style="text-transform: uppercase;">
                        <small class="text-muted mt-1 d-block" id="count_clave">0/18 caracteres</small>
                    </div>
                    <div class="col-md-3">
                        <label class="form-label" for="curp">CURP *</label>
                        <input type="text" class="form-control" id="curp" name="curp" required value="$cur_val" placeholder="18 CARACTERES" maxlength="18" style="text-transform: uppercase;">
                        <small class="text-muted mt-1 d-block" id="count_curp">0/18 caracteres</small>
                    </div>
                    <div class="col-md-3">
                        <label class="form-label" for="ocr">Número OCR *</label>
                        <input type="text" class="form-control" id="ocr" name="ocr" required value="$ocr_val" placeholder="13 dígitos" maxlength="13">
                    </div>
                    <div class="col-md-3">
                        <label class="form-label" for="cic">Número CIC *</label>
                        <input type="text" class="form-control" id="cic" name="cic" required value="$cic_val" placeholder="10 dígitos" maxlength="10">
                    </div>
                </div>
            </div>

            <!-- SECCIÓN 2: EVIDENCIA FOTOGRÁFICA -->
            <div class="section-card">
                <div class="section-title">
                    <i class="bi bi-camera"></i> Sección 2 — Evidencia Fotográfica
                </div>
                <div class="row g-3">
                    <!-- Anverso INE -->
                    <div class="col-md-3">
                        <label class="form-label">Anverso INE *</label>
                        <div class="upload-card" onclick="triggerUpload('foto_anverso_ine')">
                            <input type="file" id="file_foto_anverso_ine" accept="image/*" class="d-none" onchange="previewFile(this, 'foto_anverso_ine')">
                            <input type="hidden" id="foto_anverso_ine_base64" name="foto_anverso_ine_base64">
                            
                            <div class="upload-placeholder" id="placeholder_foto_anverso_ine" style="@{[$af_edit && $af_edit->{foto_anverso_ine} ? 'display:none' : '']}">
                                <i class="bi bi-camera"></i>
                                <div class="fw-semibold small text-dark">Anverso INE</div>
                                <span>Tomar foto / Seleccionar</span>
                            </div>
                            
                            <div class="upload-preview" id="preview_foto_anverso_ine" style="@{[$af_edit && $af_edit->{foto_anverso_ine} ? '' : 'display:none']}">
                                <img src="@{[$af_edit ? $af_edit->{foto_anverso_ine} : '']}" id="img_foto_anverso_ine">
                            </div>
                        </div>
                    </div>

                    <!-- Reverso INE -->
                    <div class="col-md-3">
                        <label class="form-label">Reverso INE *</label>
                        <div class="upload-card" onclick="triggerUpload('foto_reverso_ine')">
                            <input type="file" id="file_foto_reverso_ine" accept="image/*" class="d-none" onchange="previewFile(this, 'foto_reverso_ine')">
                            <input type="hidden" id="foto_reverso_ine_base64" name="foto_reverso_ine_base64">
                            
                            <div class="upload-placeholder" id="placeholder_foto_reverso_ine" style="@{[$af_edit && $af_edit->{foto_reverso_ine} ? 'display:none' : '']}">
                                <i class="bi bi-camera"></i>
                                <div class="fw-semibold small text-dark">Reverso INE</div>
                                <span>Tomar foto / Seleccionar</span>
                            </div>
                            
                            <div class="upload-preview" id="preview_foto_reverso_ine" style="@{[$af_edit && $af_edit->{foto_reverso_ine} ? '' : 'display:none']}">
                                <img src="@{[$af_edit ? $af_edit->{foto_reverso_ine} : '']}" id="img_foto_reverso_ine">
                            </div>
                        </div>
                    </div>

                    <!-- Fotografía Viva -->
                    <div class="col-md-3">
                        <label class="form-label">Fotografía Viva *</label>
                        <div class="upload-card" onclick="triggerUpload('foto_persona')">
                            <input type="file" id="file_foto_persona" accept="image/*" class="d-none" onchange="previewFile(this, 'foto_persona')">
                            <input type="hidden" id="foto_persona_base64" name="foto_persona_base64">
                            
                            <div class="upload-placeholder" id="placeholder_foto_persona" style="@{[$af_edit && $af_edit->{foto_persona} ? 'display:none' : '']}">
                                <i class="bi bi-camera"></i>
                                <div class="fw-semibold small text-dark">Fotografía Viva</div>
                                <span>Tomar foto / Seleccionar</span>
                            </div>
                            
                            <div class="upload-preview" id="preview_foto_persona" style="@{[$af_edit && $af_edit->{foto_persona} ? '' : 'display:none']}">
                                <img src="@{[$af_edit ? $af_edit->{foto_persona} : '']}" id="img_foto_persona">
                            </div>
                        </div>
                    </div>

                    <!-- Firma Digital -->
                    <div class="col-md-3">
                        <label class="form-label">Firma Digital *</label>
                        <div class="canvas-wrap">
                            <div id="firma_existente_wrap" style="@{[$af_edit && $af_edit->{firma} ? '' : 'display:none']}; text-align:center; height:110px;">
                                <img src="@{[$af_edit ? $af_edit->{firma} : '']}" id="img_existente_firma" style="height:100%; object-fit:contain;">
                                <button type="button" class="btn btn-sm btn-outline-secondary position-absolute top-0 end-0 m-2" onclick="redibujarFirma()">
                                    <i class="bi bi-pencil-square"></i> Redibujar
                                </button>
                            </div>
                            <div id="firma_canvas_wrap" style="@{[$af_edit && $af_edit->{firma} ? 'display:none' : '']}; height:110px;">
                                <canvas id="canvasFirma"></canvas>
                                <input type="hidden" id="firma_base64" name="firma_base64">
                            </div>
                        </div>
                        <div class="d-flex gap-2 mt-2" id="firma_buttons" style="@{[$af_edit && $af_edit->{firma} ? 'display:none' : '']}">
                            <button type="button" class="btn btn-xs btn-outline-danger flex-grow-1" style="font-size:0.75rem;" onclick="limpiarFirma()">
                                <i class="bi bi-arrow-counterclockwise"></i> Limpiar firma
                            </button>
                            <button type="button" class="btn btn-xs btn-outline-success flex-grow-1" style="font-size:0.75rem;" onclick="guardarCanvasFirma()">
                                <i class="bi bi-check-lg"></i> Guardar firma
                            </button>
                        </div>
                    </div>
                </div>
            </div>

            <!-- SECCIÓN 3: ASOCIACIÓN, LUGAR Y FECHA -->
            <div class="section-card">
                <div class="section-title">
                    <i class="bi bi-geo-alt"></i> Sección 3 — Asociación, Lugar y Fecha de Afiliación
                </div>
                <div class="row">
                    <div class="col-md-4 mb-3">
                        <label class="form-label" for="id_asociacion_input">Asociación política *</label>
                        <select class="form-select" id="id_asociacion_input" name="id_asociacion" required>
                            $asociaciones_options
                        </select>
                    </div>
                    <div class="col-md-4 mb-3">
                        <label class="form-label" for="id_municipio_afiliacion">Lugar de afiliación (municipio) *</label>
                        <select class="form-select" id="id_municipio_afiliacion" name="id_municipio_afiliacion" required>
                            $municipios_options
                        </select>
                    </div>
                    <div class="col-md-4 mb-3">
                        <label class="form-label">Fecha y hora de afiliación</label>
                        <input type="text" class="form-control bg-light" value="$fecha_registro_str" readonly style="cursor: default;">
                    </div>
                </div>
            </div>

            <!-- SECCIÓN 4: DECLARACIONES Y ACEPTACIÓN -->
            <div class="section-card">
                <div class="section-title">
                    <i class="bi bi-shield-check"></i> Sección 4 — Declaraciones y Aceptación
                </div>
                <p class="text-muted small">El ciudadano debe aceptar todas las declaraciones obligatorias para completar el registro.</p>
                
                <div class="form-check mb-3">
                    <input class="form-check-input declaration-check" type="checkbox" id="acepta_afiliacion_libre" name="acepta_afiliacion_libre" value="1" $chk_libre>
                    <label class="form-check-label text-dark fw-medium small" for="acepta_afiliacion_libre">
                        Manifiesto que mi afiliación es libre, voluntaria, individual y pacífica.
                    </label>
                </div>
                <div class="form-check mb-3">
                    <input class="form-check-input declaration-check" type="checkbox" id="acepta_documentos" name="acepta_documentos" value="1" $chk_docs>
                    <label class="form-check-label text-dark fw-medium small" for="acepta_documentos">
                        Conozco y acepto los documentos básicos de la organización.
                    </label>
                </div>
                <div class="form-check mb-3">
                    <input class="form-check-input declaration-check" type="checkbox" id="acepta_no_otro_partido" name="acepta_no_otro_partido" value="1" $chk_no_otro>
                    <label class="form-check-label text-dark fw-medium small" for="acepta_no_otro_partido">
                        Declaro no estar afiliada/a a otra organización política estatal (o que renuncio a dicha afiliación).
                    </label>
                </div>
                <div class="form-check mb-4">
                    <input class="form-check-input declaration-check" type="checkbox" id="acepta_aviso_privacidad" name="acepta_aviso_privacidad" value="1" $chk_aviso>
                    <label class="form-check-label text-dark fw-medium small" for="acepta_aviso_privacidad">
                        He leído y acepto el <a href="#" class="text-decoration-underline" style="color: #6B2D8B;">Aviso de Privacidad Simplificado</a> e <a href="#" class="text-decoration-underline" style="color: #6B2D8B;">Integral</a>.
                    </label>
                </div>

                <div class="d-flex align-items-center justify-content-between mb-2">
                    <span class="text-secondary small font-monospace">Declaraciones aceptadas</span>
                    <span class="fw-bold" style="color: #198754;" id="declProgressText">0/4</span>
                </div>
                <div class="progress-container mb-4">
                    <div class="progress-bar-success" id="declProgress"></div>
                </div>

                <button type="submit" id="btnSubmit" class="btn btn-secondary rounded-pill w-100 py-3 fw-bold" disabled>
                    Complete las declaraciones (0/4)
                </button>
            </div>
        </form>
    </div>

    <!-- Modal de Cámara para Laptop/Móvil -->
    <div class="modal fade" id="cameraModal" data-bs-backdrop="static" data-bs-keyboard="false" tabindex="-1" aria-hidden="true">
        <div class="modal-dialog modal-dialog-centered">
            <div class="modal-content rounded-4 border-0 shadow-lg">
                <div class="modal-header border-0 pb-0">
                    <h5 class="modal-title fw-bold text-dark"><i class="bi bi-camera me-2"></i>Capturar Foto</h5>
                    <button type="button" class="btn-close" onclick="closeCameraModal()"></button>
                </div>
                <div class="modal-body text-center">
                    <div class="ratio ratio-4x3 bg-dark rounded-4 overflow-hidden mb-3">
                        <video id="webcamVideo" autoplay playsinline class="w-100 h-100" style="object-fit: cover;"></video>
                    </div>
                    <canvas id="webcamCanvas" style="display: none;"></canvas>
                    <button type="button" class="btn btn-purple rounded-pill px-4 py-2 fw-bold" onclick="takeSnapshot()">
                        <i class="bi bi-camera-fill me-2"></i>Tomar Captura
                    </button>
                </div>
            </div>
        </div>
    </div>

    <!-- Scripts -->
    <script src="https://code.jquery.com/jquery-3.7.0.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    
    <script>
        \$(document).ready(function() {
            var isEditMode = parseInt('$id_val') > 0;
            var canvas = document.getElementById('canvasFirma');
            var ctx = canvas.getContext('2d');
            var drawing = false;
            var isCanvasDrawn = false;

            // Ajustar canvas a su contenedor
            function resizeCanvas() {
                if (canvas) {
                    canvas.width = canvas.parentElement.clientWidth;
                    canvas.height = canvas.parentElement.clientHeight;
                }
            }

            window.addEventListener('resize', resizeCanvas);
            resizeCanvas();

            // Dibujo firma canvas
            if (canvas) {
                canvas.addEventListener('mousedown', function(e) { drawing = true; isCanvasDrawn = true; draw(e); });
                canvas.addEventListener('mouseup', function() { drawing = false; ctx.beginPath(); });
                canvas.addEventListener('mousemove', draw);
                
                canvas.addEventListener('touchstart', function(e) { drawing = true; isCanvasDrawn = true; drawTouch(e); e.preventDefault(); });
                canvas.addEventListener('touchend', function(e) { drawing = false; ctx.beginPath(); e.preventDefault(); });
                canvas.addEventListener('touchmove', function(e) { drawTouch(e); e.preventDefault(); });
            }

            function draw(e) {
                if (!drawing) return;
                ctx.lineWidth = 3;
                ctx.lineCap = 'round';
                ctx.strokeStyle = '#000000';
                var rect = canvas.getBoundingClientRect();
                ctx.lineTo(e.clientX - rect.left, e.clientY - rect.top);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(e.clientX - rect.left, e.clientY - rect.top);
            }

            function drawTouch(e) {
                if (!drawing) return;
                var touch = e.touches[0];
                ctx.lineWidth = 3;
                ctx.lineCap = 'round';
                ctx.strokeStyle = '#000000';
                var rect = canvas.getBoundingClientRect();
                ctx.lineTo(touch.clientX - rect.left, touch.clientY - rect.top);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(touch.clientX - rect.left, touch.clientY - rect.top);
            }

            window.limpiarFirma = function() {
                ctx.clearRect(0, 0, canvas.width, canvas.height);
                document.getElementById('firma_base64').value = '';
                isCanvasDrawn = false;
            };

            window.guardarCanvasFirma = function() {
                if (!isCanvasDrawn) {
                    Swal.fire({ icon:'warning', title:'Firma vacía', text:'Por favor, dibuje su firma antes de guardar.' });
                    return;
                }
                var dataUrl = canvas.toDataURL();
                document.getElementById('firma_base64').value = dataUrl;
                Swal.fire({ toast:true, position:'top-end', icon:'success', title:'Firma guardada correctamente', showConfirmButton:false, timer:1500 });
            };

            window.redibujarFirma = function() {
                document.getElementById('firma_existente_wrap').style.display = 'none';
                document.getElementById('firma_canvas_wrap').style.display = 'block';
                document.getElementById('firma_buttons').style.display = 'flex';
                resizeCanvas();
            };

            var cameraStream = null;
            var currentCameraField = null;
            var cameraModalObj = null;

            window.openCameraModal = function(field) {
                currentCameraField = field;
                if (!cameraModalObj) {
                    cameraModalObj = new bootstrap.Modal(document.getElementById('cameraModal'));
                }
                
                var constraints = {
                    video: {
                        facingMode: (field === 'foto_persona') ? 'user' : 'environment',
                        width: { ideal: 640 },
                        height: { ideal: 480 }
                    }
                };

                navigator.mediaDevices.getUserMedia(constraints)
                    .then(function(stream) {
                        cameraStream = stream;
                        var video = document.getElementById('webcamVideo');
                        video.srcObject = stream;
                        cameraModalObj.show();
                    })
                    .catch(function(err) {
                        console.error(err);
                        // Fallback si falla la cámara por permisos
                        var camInput = document.createElement('input');
                        camInput.type = 'file';
                        camInput.accept = 'image/*';
                        camInput.capture = 'environment';
                        camInput.onchange = function() {
                            previewFile(camInput, field);
                        };
                        camInput.click();
                    });
            };

            window.closeCameraModal = function() {
                if (cameraStream) {
                    cameraStream.getTracks().forEach(function(track) {
                        track.stop();
                    });
                    cameraStream = null;
                }
                if (cameraModalObj) {
                    cameraModalObj.hide();
                }
            };

            window.takeSnapshot = function() {
                var video = document.getElementById('webcamVideo');
                var canvas = document.getElementById('webcamCanvas');
                var ctx = canvas.getContext('2d');
                
                canvas.width = video.videoWidth || 640;
                canvas.height = video.videoHeight || 480;
                
                ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
                
                var dataUrl = canvas.toDataURL('image/jpeg');
                
                document.getElementById(currentCameraField + '_base64').value = dataUrl;
                document.getElementById('img_' + currentCameraField).src = dataUrl;
                document.getElementById('placeholder_' + currentCameraField).style.display = 'none';
                document.getElementById('preview_' + currentCameraField).style.display = 'block';
                
                closeCameraModal();
            };

            // Triggers file click or camera capture
            window.triggerUpload = function(field) {
                Swal.fire({
                    title: 'Cargar Evidencia',
                    text: 'Elige cómo deseas cargar la imagen:',
                    icon: 'question',
                    showCancelButton: true,
                    showDenyButton: true,
                    confirmButtonText: '📸 Tomar Foto (Cámara)',
                    denyButtonText: '📁 Seleccionar Archivo (Galería)',
                    cancelButtonText: 'Cancelar',
                    confirmButtonColor: '#6B2D8B',
                    denyButtonColor: '#3b174a',
                    customClass: {
                        popup: 'rounded-4 border-0 shadow'
                    }
                }).then(function(result) {
                    if (result.isConfirmed) {
                        if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
                            openCameraModal(field);
                        } else {
                            // Fallback para dispositivos móviles en contextos no seguros (HTTP)
                            var camInput = document.createElement('input');
                            camInput.type = 'file';
                            camInput.accept = 'image/*';
                            camInput.capture = 'environment';
                            camInput.onchange = function() {
                                previewFile(camInput, field);
                            };
                            camInput.click();
                        }
                    } else if (result.isDenied) {
                        var fileInput = document.getElementById('file_' + field);
                        fileInput.click();
                    }
                });
            };

            // Previsualiza imágenes de carga
            window.previewFile = function(input, field) {
                var file = input.files[0];
                if (file) {
                    var reader = new FileReader();
                    reader.onload = function(e) {
                        document.getElementById(field + '_base64').value = e.target.result;
                        document.getElementById('img_' + field).src = e.target.result;
                        document.getElementById('placeholder_' + field).style.display = 'none';
                        document.getElementById('preview_' + field).style.display = 'block';
                    };
                    reader.readAsDataURL(file);
                }
            };

            // Contador de caracteres Clave Elector
            \$('#clave_elector').on('input', function() {
                var val = \$(this).val().toUpperCase();
                \$(this).val(val);
                \$('#count_clave').text(val.length + '/18 caracteres');
            });
            \$('#clave_elector').trigger('input');

            // Contador de caracteres CURP
            \$('#curp').on('input', function() {
                var val = \$(this).val().toUpperCase();
                \$(this).val(val);
                \$('#count_curp').text(val.length + '/18 caracteres');
            });
            \$('#curp').trigger('input');

            // Actualizar barra de declaraciones
            function updateDeclarations() {
                var checked = \$('.declaration-check:checked').length;
                \$('#declProgress').css('width', (checked / 4 * 100) + '%');
                \$('#declProgressText').text(checked + '/4');
                
                if (checked === 4) {
                    \$('#btnSubmit').prop('disabled', false)
                                 .text(isEditMode ? 'Guardar Cambios' : 'Confirmar y Registrar Afiliación')
                                 .removeClass('btn-secondary').addClass('btn-purple');
                } else {
                    \$('#btnSubmit').prop('disabled', true)
                                 .text('Complete las declaraciones (' + checked + '/4)')
                                 .removeClass('btn-purple').addClass('btn-secondary');
                }
            }

            \$('.declaration-check').on('change', updateDeclarations);
            updateDeclarations();

            // Forzar solo números en OCR y CIC
            \$('#ocr, #cic').on('keypress', function(e) {
                if (e.which < 48 || e.which > 57) {
                    e.preventDefault();
                }
            });

            // Guardar Formulario
            \$('#afiliacionForm').on('submit', function(e) {
                e.preventDefault();

                // Validación simple de requeridos
                var valid = true;
                \$(this).find('[required]').each(function() {
                    if (!\$(this).val()) {
                        \$(this).addClass('is-invalid');
                        valid = false;
                    } else {
                        \$(this).removeClass('is-invalid');
                    }
                });

                if (!valid) {
                    Swal.fire({ icon:'warning', title:'Campos incompletos', text:'Por favor, complete todos los campos obligatorios.' });
                    return;
                }

                // Validar longitud Clave de Elector
                var cleVal = \$('#clave_elector').val().replace(/\\s+/g, '').toUpperCase();
                if (cleVal.length !== 18) {
                    \$('#clave_elector').addClass('is-invalid');
                    Swal.fire({ icon:'warning', title:'Clave de Elector inválida', text:'La Clave de Elector debe tener exactamente 18 caracteres.' });
                    return;
                } else {
                    \$('#clave_elector').removeClass('is-invalid');
                }

                // Validar longitud CURP
                var curpVal = \$('#curp').val().replace(/\\s+/g, '').toUpperCase();
                if (curpVal.length !== 18) {
                    \$('#curp').addClass('is-invalid');
                    Swal.fire({ icon:'warning', title:'CURP inválida', text:'La CURP debe tener exactamente 18 caracteres.' });
                    return;
                } else {
                    \$('#curp').removeClass('is-invalid');
                }

                // Validar longitud y formato OCR
                var ocrVal = \$('#ocr').val().trim();
                if (!/^\\d{13}\$/.test(ocrVal)) {
                    \$('#ocr').addClass('is-invalid');
                    Swal.fire({ icon:'warning', title:'OCR inválido', text:'El Número OCR debe tener exactamente 13 dígitos numéricos.' });
                    return;
                } else {
                    \$('#ocr').removeClass('is-invalid');
                }

                // Validar longitud y formato CIC
                var cicVal = \$('#cic').val().trim();
                if (!/^\\d{10}\$/.test(cicVal)) {
                    \$('#cic').addClass('is-invalid');
                    Swal.fire({ icon:'warning', title:'CIC inválido', text:'El Número CIC debe tener exactamente 10 dígitos numéricos.' });
                    return;
                } else {
                    \$('#cic').removeClass('is-invalid');
                }

                // Si no se ha guardado firma digital y es registro nuevo
                if (!isEditMode && !document.getElementById('firma_base64').value) {
                    Swal.fire({ icon:'warning', title:'Firma requerida', text:'Por favor, dibuje su firma y presione "Guardar firma".' });
                    return;
                }

                // Validar si re-dibujó firma en modo edición pero no la guardó
                if (isEditMode && \$('#firma_existente_wrap').is(':hidden') && !document.getElementById('firma_base64').value) {
                    Swal.fire({ icon:'warning', title:'Firma requerida', text:'Por favor, guarde la firma digital antes de guardar los cambios.' });
                    return;
                }

                // Si faltan fotos en creación nueva
                if (!isEditMode) {
                    if (!\$('#foto_anverso_ine_base64').val() || !\$('#foto_reverso_ine_base64').val() || !\$('#foto_persona_base64').val()) {
                        Swal.fire({ icon:'warning', title:'Imágenes requeridas', text:'Por favor, cargue todas las imágenes obligatorias.' });
                        return;
                    }
                }

                // Crear FormData y enviar
                var formData = new FormData(this);
                formData.append('accion', 'guardar');

                \$('#btnSubmit').html('<span class="spinner-border spinner-border-sm me-2"></span>Procesando...').prop('disabled', true);

                fetch('registro_afiliados.pl', { method:'POST', body:formData })
                    .then(function(r) { return r.json(); })
                    .then(function(d) {
                        \$('#btnSubmit').html(isEditMode ? 'Guardar Cambios' : 'Confirmar y Registrar Afiliación').prop('disabled', false);
                        if (d.success) {
                            Swal.fire({
                                icon: 'success',
                                title: isEditMode ? 'Cambios guardados' : 'Registro exitoso',
                                text: d.message,
                                confirmButtonColor: '#6B2D8B'
                            }).then(function() {
                                window.location.href = 'listado_afiliados.pl';
                            });
                        } else {
                            Swal.fire({ icon:'error', title:'Error', text: d.message || 'No se pudo guardar la afiliación.' });
                        }
                    })
                    .catch(function(err) {
                        \$('#btnSubmit').html(isEditMode ? 'Guardar Cambios' : 'Confirmar y Registrar Afiliación').prop('disabled', false);
                        Swal.fire({ icon:'error', title:'Error de red', text:'No se pudo conectar con el servidor.' });
                    });
            });
        });
    </script>
</body>
</html>
HTML
