#!C:\xampp\perl\bin\perl.exe
use strict;
use warnings;
use utf8;
use CGI;
use CGI::Session;
use JSON;
use FindBin;
require "$FindBin::Bin/db.pl";

my $cgi = CGI->new;

# Configurar salida UTF-8
binmode(STDOUT, ":utf8");

# Evitar doble codificación UTF-8 en encode_json al usar binmode :utf8
no warnings 'redefine';
sub encode_json ($) {
    return JSON->new->utf8(0)->encode($_[0]);
}
use warnings 'redefine';

my $session = CGI::Session->new(undef, $cgi, {Directory => "$FindBin::Bin/.sesiones"});

my $rol = $session->param('rol') || '';
my $nombre_completo = $session->param('nombre_completo') || '';
my $id_usuario_sesion = $session->param('id_usuario') || 0;

if ($rol ne 'administrador') {
    print $cgi->redirect(-uri => 'dashboard.pl');
    exit;
}

my $accion = $cgi->param('accion') || '';

# ==========================================
# POST: Guardar Asociación (Crear o Editar)
# ==========================================
if ($accion eq 'guardar') {
    my $id_asoc          = $cgi->param('id_asociacion') || '';
    my $nombre_asoc      = $cgi->param('nombre_asociacion') || '';
    my $rep_legal        = $cgi->param('representante_legal') || '';
    my $telefono         = $cgi->param('telefono') || '';
    my $correo           = $cgi->param('correo_electronico') || '';
    my $calle            = $cgi->param('calle') || '';
    my $numero           = $cgi->param('numero') || '';
    my $colonia          = $cgi->param('colonia') || '';
    my $municipio        = $cgi->param('municipio') || '';
    my $codigo_postal    = $cgi->param('codigo_postal') || '';
    my $fecha_aprobacion = $cgi->param('fecha_aprobacion') || '';
    my $fecha_perdida    = $cgi->param('fecha_perdida_registro') || '';
    my $estatus          = $cgi->param('estatus') || 'VIGENTE';
    my $emblema_actual   = $cgi->param('emblema_actual') || '';

    # Limpieza de espacios
    $nombre_asoc =~ s/^\s+|\s+$//g;
    $rep_legal   =~ s/^\s+|\s+$//g;

    if (!$nombre_asoc || !$rep_legal) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'El nombre de la asociación y el representante legal son obligatorios.' });
        exit;
    }

    # Procesar archivo del emblema si se subió
    my $emblema_filename = $emblema_actual;
    my $file_handle = $cgi->upload('emblema_file');
    if ($file_handle) {
        my $orig_filename = $cgi->param('emblema_file');
        $orig_filename =~ s/.*[\\\/]//; # Quedarse solo con el nombre de archivo
        $orig_filename =~ s/[^a-zA-Z0-9\._\-]/_/g; # Sanear caracteres extraños
        $emblema_filename = time() . "_" . $orig_filename;
        
        my $upload_dir = "$FindBin::Bin/uploads/emblemas";
        mkdir $upload_dir unless -d $upload_dir;
        
        my $target_path = "$upload_dir/$emblema_filename";
        open(my $out_fh, '>', $target_path) or die "No se pudo crear el archivo: $!";
        binmode($out_fh);
        my $buffer;
        while (read($file_handle, $buffer, 4096)) {
            print $out_fh $buffer;
        }
        close($out_fh);
    }

    my $ok;
    my $detalles_log = "";
    if ($id_asoc) {
        # Actualización de asociación existente
        $ok = execute_query_write(
            "UPDATE asociaciones_politicas SET
                nombre = ?,
                representante_legal = ?,
                calle = ?,
                numero = ?,
                colonia = ?,
                municipio = ?,
                codigo_postal = ?,
                correo_electronico = ?,
                telefono = ?,
                emblema = ?,
                fecha_aprobacion = ?,
                fecha_perdida_registro = ?,
                estatus = ?
             WHERE id_asociacion = ?",
            $nombre_asoc, $rep_legal, $calle, $numero, $colonia, $municipio, $codigo_postal,
            $correo, $telefono, $emblema_filename || undef, $fecha_aprobacion || undef,
            ($estatus eq 'SIN_REGISTRO' && $fecha_perdida) ? $fecha_perdida : undef, $estatus, $id_asoc
        );
        $detalles_log = "Asociación ID $id_asoc ($nombre_asoc) modificada";
    } else {
        # Nueva asociación
        $ok = execute_query_write(
            "INSERT INTO asociaciones_politicas
                (nombre, representante_legal, calle, numero, colonia, municipio, codigo_postal,
                 correo_electronico, telefono, emblema, fecha_aprobacion, fecha_perdida_registro, estatus)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            $nombre_asoc, $rep_legal, $calle, $numero, $colonia, $municipio, $codigo_postal,
            $correo, $telefono, $emblema_filename || undef, $fecha_aprobacion || undef,
            ($estatus eq 'SIN_REGISTRO' && $fecha_perdida) ? $fecha_perdida : undef, $estatus
        );
        $detalles_log = "Nueva asociación '$nombre_asoc' registrada";
    }

    if ($ok) {
        # Registrar en bitácora
        execute_query_write(
            "INSERT INTO bitacora (id_usuario, accion, modulo, detalles, fecha) VALUES (?, 'REGISTRO', 'asociaciones_politicas', ?, NOW())",
            $id_usuario_sesion, $detalles_log
        );
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 1, message => 'Datos guardados correctamente.' });
    } else {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'Error al guardar los datos en la base de datos.' });
    }
    exit;
}

# ==========================================
# POST: Guardar Padrón Electoral
# ==========================================
if ($accion eq 'guardar_padron') {
    my $padron_total = $cgi->param('padron_total') || 0;
    my $fecha_corte  = $cgi->param('fecha_corte_padron') || '';
    my $pct_minimo   = $cgi->param('porcentaje_minimo') || 0;
    $padron_total =~ s/,//g; # Quitar comas de formato

    my @padron_existe = execute_query_list("SELECT id_padron FROM padron_electoral WHERE activo = 1 LIMIT 1");
    my $ok;
    if (@padron_existe) {
        $ok = execute_query_write(
            "UPDATE padron_electoral SET total_padron = ?, fecha_corte = ?, porcentaje_minimo = ? WHERE activo = 1",
            $padron_total, $fecha_corte || undef, $pct_minimo / 100
        );
    } else {
        $ok = execute_query_write(
            "INSERT INTO padron_electoral (total_padron, fecha_corte, porcentaje_minimo, activo)
             VALUES (?, ?, ?, 1)",
            $padron_total, $fecha_corte || undef, $pct_minimo / 100
        );
    }

    if ($ok) {
        execute_query_write(
            "INSERT INTO bitacora (id_usuario, accion, modulo, detalles, fecha) VALUES (?, 'EDICION', 'padron_electoral', ?, NOW())",
            $id_usuario_sesion, "Padrón electoral de referencia actualizado: $padron_total electores"
        );
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 1, message => 'Padrón electoral actualizado correctamente.' });
    } else {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'Error al actualizar el padrón electoral.' });
    }
    exit;
}

# ==========================================
# POST: Eliminar Asociación (AJAX)
# ==========================================
if ($accion eq 'eliminar') {
    my $id_asoc = $cgi->param('id_asociacion') || '';
    if (!$id_asoc) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'ID de asociación inválido.' });
        exit;
    }

    # Verificar dependencias (afiliaciones, auxiliares, usuarios)
    my @afiliados = execute_query_list("SELECT COUNT(*) AS total FROM afiliaciones WHERE id_asociacion = ? AND fecha_eliminacion IS NULL", $id_asoc);
    my @auxiliares = execute_query_list("SELECT COUNT(*) AS total FROM auxiliares WHERE id_asociacion = ?", $id_asoc);
    my @usuarios   = execute_query_list("SELECT COUNT(*) AS total FROM usuarios WHERE id_asociacion = ?", $id_asoc);

    my $tot_afiliados = $afiliados[0]->{total} || 0;
    my $tot_auxiliares = $auxiliares[0]->{total} || 0;
    my $tot_usuarios   = $usuarios[0]->{total} || 0;

    if ($tot_afiliados > 0 || $tot_auxiliares > 0 || $tot_usuarios > 0) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({
            success => 0,
            message => "No se puede eliminar la asociación porque tiene vinculados: " .
                       ($tot_usuarios ? "$tot_usuarios usuarios, " : "") .
                       ($tot_afiliados ? "$tot_afiliados afiliados, " : "") .
                       ($tot_auxiliares ? "$tot_auxiliares auxiliares." : "") .
                       " Por favor, reasigna o elimina estos registros primero."
        });
        exit;
    }

    # Obtener nombre antes de eliminar para bitácora
    my @asoc_info = execute_query_list("SELECT nombre FROM asociaciones_politicas WHERE id_asociacion = ?", $id_asoc);
    my $nombre_asoc = @asoc_info ? $asoc_info[0]->{nombre} : "Desconocida";

    my $ok = execute_query_write("DELETE FROM asociaciones_politicas WHERE id_asociacion = ?", $id_asoc);
    if ($ok) {
        execute_query_write(
            "INSERT INTO bitacora (id_usuario, accion, modulo, detalles, fecha) VALUES (?, 'ELIMINACION', 'asociaciones_politicas', ?, NOW())",
            $id_usuario_sesion, "Asociación '$nombre_asoc' (ID $id_asoc) eliminada"
        );
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 1, message => 'Asociación eliminada exitosamente.' });
    } else {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'Error al eliminar la asociación.' });
    }
    exit;
}

# ==========================================
# GET: Cargar Catálogos y Datos Iniciales
# ==========================================

# 1. Municipios
my @municipios = execute_query_list("SELECT id_municipio, nombre FROM municipios ORDER BY nombre ASC");

# 2. Padrón Electoral activo
my %padron_data = ();
my @padron_rows = execute_query_list(
    "SELECT total_padron, DATE_FORMAT(fecha_corte,'%Y-%m-%d') AS fecha_corte, porcentaje_minimo
     FROM padron_electoral WHERE activo = 1 LIMIT 1"
);
if (@padron_rows) {
    %padron_data = %{$padron_rows[0]};
}
my $padron_total  = $padron_data{total_padron}      || 0;
my $fecha_corte   = $padron_data{fecha_corte}        || '';
my $pct_minimo_db = $padron_data{porcentaje_minimo} || 0.0013;
my $pct_minimo    = sprintf("%.4f", $pct_minimo_db * 100);

sub format_num {
    my $n = shift // 0;
    $n =~ s/(\d)(?=(\d{3})+(?!\d))/$1,/g;
    return $n;
}
my $padron_formatted  = format_num($padron_total);
my $minimo_calculado  = int($padron_total * $pct_minimo_db);
my $minimo_formatted  = format_num($minimo_calculado);

# 3. Listado de todas las asociaciones
my @asociaciones = execute_query_list(
    "SELECT id_asociacion, nombre, representante_legal, calle, numero, colonia, municipio, codigo_postal,
            correo_electronico, telefono, emblema,
            DATE_FORMAT(fecha_aprobacion,'%Y-%m-%d') AS fecha_aprobacion,
            DATE_FORMAT(fecha_perdida_registro,'%Y-%m-%d') AS fecha_perdida_registro,
            estatus
     FROM asociaciones_politicas ORDER BY nombre ASC"
);
my $asociaciones_json = encode_json(\@asociaciones);

my $pagina_activa = 'ASOCIACION';

print $cgi->header(
    -type         => 'text/html',
    -charset      => 'utf-8',
    -expires      => 'now',
    -Cache_Control => 'no-store, no-cache, must-revalidate, max-age=0',
    -Pragma       => 'no-cache'
);

print <<"HTML";
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Gestión de Asociaciones - IEEQ</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons\@1.11.3/font/bootstrap-icons.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght\@300;400;500;600;700&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/sweetalert2\@11"></script>
    <style>
        * { box-sizing: border-box; }
        body { font-family: 'Outfit', sans-serif; background: #f5f5f8; overflow-x: hidden; margin: 0; }
        #content { margin-left: 260px; min-height: 100vh; padding: 2rem; transition: margin-left 0.3s ease; }

        /* ── Page header ── */
        .page-header {
            display: flex; justify-content: space-between; align-items: center;
            background: #fff; padding: 1rem 1.5rem; border-radius: 14px;
            box-shadow: 0 2px 12px rgba(0,0,0,0.05); margin-bottom: 1.5rem;
        }
        .page-header h4 { margin: 0; font-weight: 700; color: #1a1a2e; font-size: 1.3rem; }
        .page-header p  { margin: 0; color: #6c757d; font-size: 0.85rem; }

        /* ── Tabs Navigation ── */
        .nav-tabs-ieeq {
            border-bottom: 2px solid #e0e0e0;
            margin-bottom: 1.5rem;
            display: flex;
            gap: 8px;
        }
        .nav-tabs-ieeq .nav-link {
            border: none;
            color: #6c757d;
            font-weight: 600;
            padding: 0.8rem 1.4rem;
            border-radius: 10px 10px 0 0;
            transition: all 0.2s;
            font-size: 0.92rem;
            background: transparent;
        }
        .nav-tabs-ieeq .nav-link:hover {
            color: #6B2D8B;
            background: rgba(107, 45, 139, 0.05);
        }
        .nav-tabs-ieeq .nav-link.active {
            color: #6B2D8B;
            border-bottom: 3px solid #6B2D8B;
            background: #fff;
            font-weight: 700;
        }

        /* ── Section card ── */
        .section-card {
            background: #fff; border-radius: 14px;
            box-shadow: 0 2px 16px rgba(0,0,0,0.05);
            margin-bottom: 1.5rem; overflow: hidden;
        }
        .section-header {
            display: flex; align-items: center; gap: 14px;
            padding: 1.2rem 1.5rem; border-bottom: 1px solid #f3f3f3;
        }
        .section-icon {
            width: 40px; height: 40px; border-radius: 10px;
            background: #f3e8f8; color: #6B2D8B;
            display: flex; align-items: center; justify-content: center; font-size: 1.1rem;
            flex-shrink: 0;
        }
        .section-title  { font-weight: 700; color: #1a1a2e; font-size: 1rem; margin: 0; }
        .section-subtitle { color: #9e9e9e; font-size: 0.8rem; margin: 0; }
        .section-body { padding: 1.5rem; }

        /* ── Form ── */
        .form-label {
            font-weight: 600; font-size: 0.82rem; color: #4a4a6a;
            margin-bottom: 0.4rem; display: block;
        }
        .form-label .req { color: #e53935; }
        .form-field {
            width: 100%; padding: 0.65rem 1rem; border-radius: 10px;
            border: 1.5px solid #e0e0e0; font-family: 'Outfit', sans-serif;
            font-size: 0.9rem; color: #1a1a2e; outline: none;
            transition: border-color 0.2s, box-shadow 0.2s; background: #fff;
        }
        .form-field:focus { border-color: #6B2D8B; box-shadow: 0 0 0 3px rgba(107,45,139,0.1); }
        .form-field::placeholder { color: #bbb; }
        textarea.form-field { resize: vertical; min-height: 90px; }
        select.form-field { cursor: pointer; }
        .form-group { margin-bottom: 1.2rem; }

        /* ── Emblema / drag drop ── */
        .drop-zone {
            border: 2px dashed #d0b8e8; border-radius: 12px;
            padding: 1.5rem; text-align: center; cursor: pointer;
            transition: all 0.2s; background: #fdfaff; min-height: 160px;
            display: flex; flex-direction: column; align-items: center; justify-content: center;
            position: relative;
        }
        .drop-zone:hover, .drop-zone.drag-over {
            border-color: #6B2D8B; background: #f8f0fc;
        }
        .drop-icon { font-size: 2.2rem; color: #d0b8e8; margin-bottom: 0.4rem; }
        .drop-text { color: #9e9e9e; font-size: 0.82rem; }
        .btn-select-file {
            margin-top: 0.6rem; padding: 0.4rem 1.1rem;
            border: 1.5px solid #6B2D8B; border-radius: 20px;
            background: #fff; color: #6B2D8B; font-family: 'Outfit', sans-serif;
            font-size: 0.8rem; font-weight: 600; cursor: pointer; transition: all 0.2s;
        }
        .btn-select-file:hover { background: #6B2D8B; color: #fff; }
        
        .preview-container {
            display: none;
            position: relative;
            width: 130px;
            height: 130px;
            border-radius: 12px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .preview-container.has-img {
            display: block;
        }
        .emblema-preview {
            width: 100%;
            height: 100%;
            object-fit: contain;
            background: #fdfdfd;
        }
        .btn-remove-preview {
            position: absolute;
            top: 5px;
            right: 5px;
            background: rgba(229, 57, 53, 0.9);
            color: white;
            border: none;
            border-radius: 50%;
            width: 26px;
            height: 26px;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            transition: transform 0.2s, background 0.2s;
            font-size: 0.8rem;
            box-shadow: 0 2px 5px rgba(0,0,0,0.2);
        }
        .btn-remove-preview:hover {
            background: #d32f2f;
            transform: scale(1.1);
        }

        .req-box {
            background: #f3e8f8; border-radius: 10px; padding: 0.9rem 1rem;
            font-size: 0.78rem; color: #6B2D8B; line-height: 1.7;
        }
        .req-box b { display: block; margin-bottom: 4px; }

        /* ── Badge estatus ── */
        .badge-estatus {
            display: inline-flex; align-items: center;
            padding: 5px 14px; border-radius: 20px; font-size: 0.78rem; font-weight: 600;
        }
        .badge-estatus.activo  { background: #e8f5e9; color: #2e7d32; }
        .badge-estatus.inactivo{ background: #fce4ec; color: #c62828; }

        /* ── Tarjeta cálculo ── */
        .calc-card {
            background: linear-gradient(135deg, #6B2D8B 0%, #4a1f61 100%);
            border-radius: 12px; padding: 1.2rem 1.4rem; color: #fff;
        }
        .calc-card .calc-label { font-size: 0.72rem; opacity: 0.8; text-transform: uppercase; letter-spacing: 0.5px; }
        .calc-card .calc-value { font-size: 1.6rem; font-weight: 700; font-family: monospace; }
        .calc-card .calc-desc  { font-size: 0.8rem; opacity: 0.75; margin-top: 4px; }

        /* ── Botones de acción ── */
        .action-bar {
            display: flex; justify-content: flex-end; gap: 12px;
            padding: 1.2rem 1.5rem; background: #fff; border-radius: 14px;
            box-shadow: 0 2px 16px rgba(0,0,0,0.05); margin-top: 0.5rem;
        }
        .btn-cancel {
            padding: 0.65rem 1.8rem; border-radius: 25px; font-family: 'Outfit', sans-serif;
            font-size: 0.9rem; font-weight: 600; cursor: pointer;
            border: 1.5px solid #d0d0d0; background: #fff; color: #6c757d; transition: all 0.2s;
        }
        .btn-cancel:hover { background: #f5f5f5; }
        .btn-save {
            padding: 0.65rem 1.8rem; border-radius: 25px; font-family: 'Outfit', sans-serif;
            font-size: 0.9rem; font-weight: 600; cursor: pointer;
            border: none; background: #6B2D8B; color: #fff; transition: background 0.2s;
            display: inline-flex; align-items: center; gap: 8px;
        }
        .btn-save:hover { background: #4a1f61; }

        /* ── Tabla de Listado ── */
        .table-wrap {
            background: #fff; border-radius: 14px;
            box-shadow: 0 2px 16px rgba(0,0,0,0.05);
            overflow: hidden;
        }
        .table-ieeq { width: 100%; border-collapse: collapse; }
        .table-ieeq thead tr { background: #6B2D8B; color: #fff; }
        .table-ieeq th {
            padding: 1rem 1.2rem; font-size: 0.8rem; font-weight: 700;
            text-transform: uppercase; letter-spacing: 0.5px;
        }
        .table-ieeq td { padding: 0.9rem 1.2rem; vertical-align: middle; font-size: 0.88rem; color: #2d3748; }
        .table-ieeq tbody tr { border-bottom: 1px solid #f0f0f5; transition: background 0.15s; }
        .table-ieeq tbody tr:hover { background: #fdfcff; }
        
        .asoc-logo {
            width: 44px; height: 44px; border-radius: 8px; border: 1px solid #e2e8f0;
            object-fit: contain; background: #f7fafc;
        }
        .asoc-logo-placeholder {
            width: 44px; height: 44px; border-radius: 8px; background: #e9d8f4;
            color: #6B2D8B; display: flex; align-items: center; justify-content: center;
            font-weight: 700; font-size: 0.95rem;
        }
        .btn-action-asoc {
            border: none; background: transparent; padding: 6px; border-radius: 6px;
            color: #a0aec0; transition: all 0.2s; cursor: pointer;
        }
        .btn-action-asoc.edit:hover { color: #6B2D8B; background: rgba(107, 45, 139, 0.08); }
        .btn-action-asoc.delete:hover { color: #e53935; background: rgba(229, 57, 53, 0.08); }

        .search-wrap {
            position: relative; margin-bottom: 1rem;
        }
        .search-field {
            width: 100%; padding: 0.75rem 1rem 0.75rem 2.8rem; border-radius: 25px;
            border: 1.5px solid #e0e0e0; font-family: 'Outfit', sans-serif; font-size: 0.92rem;
            outline: none; transition: border-color 0.2s;
        }
        .search-field:focus { border-color: #6B2D8B; }
        .search-icon {
            position: absolute; left: 1.1rem; top: 50%; transform: translateY(-50%);
            color: #a0aec0; font-size: 1.05rem;
        }

        \@media (max-width: 991px) { #content { margin-left: 0 !important; } }
    </style>
</head>
<body>
HTML

require "$FindBin::Bin/_sidebar_admin.pl";

print <<"HTML";
    <!-- Main Content -->
    <div id="content">

        <!-- Page Header -->
        <div class="page-header d-flex align-items-center justify-content-between">
            <div class="d-flex align-items-center gap-2">
                <button id="sidebarToggle" class="btn btn-outline-secondary d-lg-none me-3" type="button" style="border-radius: 8px;">
                    <i class="bi bi-list"></i>
                </button>
                <div>
                    <h4><i class="bi bi-building me-2" style="color:#6B2D8B;"></i>Asociaciones Políticas</h4>
                    <p>Configura las asociaciones políticas registradas en el estado y el padrón electoral general.</p>
                </div>
            </div>
            <div class="text-muted small d-none d-md-block">
                Instituto Electoral del Estado de Querétaro
            </div>
        </div>

        <!-- Tabs Navigation -->
        <div class="nav-tabs-ieeq">
            <button class="nav-link active" id="tab-listado-btn" onclick="switchTab('listado')">
                <i class="bi bi-list-ul me-2"></i>Asociaciones Registradas
            </button>
            <button class="nav-link" id="tab-padron-btn" onclick="switchTab('padron')">
                <i class="bi bi-bar-chart-line me-2"></i>Padrón de Referencia
            </button>
        </div>

        <!-- ============================================================ -->
        <!-- TAB 1: LISTADO DE ASOCIACIONES                               -->
        <!-- ============================================================ -->
        <div id="tab-listado" class="tab-content-pane">
            <div class="d-flex justify-content-between align-items-center gap-3 mb-3">
                <div class="search-wrap flex-grow-1 mb-0">
                    <i class="bi bi-search search-icon"></i>
                    <input type="text" id="asocSearch" class="search-field" placeholder="Buscar por nombre de asociación, representante o municipio..." oninput="filtrarAsociaciones()">
                </div>
                <button type="button" class="btn-save py-2 px-4" onclick="openCreateModal()" style="border-radius:25px; height:46px; font-size:0.9rem; flex-shrink:0;">
                    <i class="bi bi-plus-circle me-2"></i>Registrar Asociación
                </button>
            </div>
            
            <div class="table-wrap">
                <div class="table-responsive">
                    <table class="table-ieeq">
                        <thead>
                            <tr>
                                <th style="width: 8%">Emblema</th>
                                <th style="width: 32%">Asociación Política</th>
                                <th style="width: 25%">Representante</th>
                                <th style="width: 15%">Contacto</th>
                                <th style="width: 12%">Estatus</th>
                                <th class="text-end" style="width: 8%">Acciones</th>
                            </tr>
                        </thead>
                        <tbody id="asocTableBody">
                            <!-- Inyectado por JS -->
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <!-- Modal de Registro/Edición de Asociación -->
        <div class="modal fade" id="modalAsociacion" tabindex="-1" aria-labelledby="modalAsociacionLabel" aria-hidden="true">
            <div class="modal-dialog modal-lg modal-dialog-centered">
                <div class="modal-content" style="border-radius: 16px; border: none; box-shadow: 0 10px 30px rgba(0,0,0,0.15);">
                    <div class="modal-header" style="border-bottom: 1px solid #f3f3f3; background: #fdfaff; border-radius: 16px 16px 0 0; padding: 1.2rem 1.5rem;">
                        <h5 class="modal-title" id="modalAsociacionLabel" style="font-weight: 700; color: #1a1a2e; font-size: 1.1rem; display: flex; align-items: center; gap: 10px;">
                            <div style="width: 32px; height: 32px; border-radius: 8px; background: #f3e8f8; color: #6B2D8B; display: flex; align-items: center; justify-content: center; font-size: 0.95rem;">
                                <i class="bi bi-building"></i>
                            </div>
                            <span id="modalTitleText">Registrar Asociación</span>
                        </h5>
                        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close" style="font-size: 0.8rem;"></button>
                    </div>
                    <form id="formAsociacion" method="POST" novalidate>
                        <div class="modal-body" style="padding: 1.8rem; max-height: 70vh; overflow-y: auto;">
                            <input type="hidden" id="asocId" name="id_asociacion" value="">
                            
                            <!-- 1. Datos Generales -->
                            <h6 class="text-uppercase text-secondary fw-bold mb-3" style="font-size: 0.75rem; letter-spacing: 0.5px;">1. Datos Generales</h6>
                            <div class="form-group mb-3">
                                <label class="form-label" for="nombreAsociacion">
                                    Nombre de la asociación <span class="req">*</span>
                                </label>
                                <input type="text" id="nombreAsociacion" name="nombre_asociacion"
                                    class="form-field" placeholder="Ej. Asociación Ciudadana por Querétaro" required>
                            </div>

                            <div class="row g-3 mb-3">
                                <div class="col-md-7">
                                    <div class="form-group mb-0">
                                        <label class="form-label" for="repLegal">
                                            Nombre del representante legal <span class="req">*</span>
                                        </label>
                                        <input type="text" id="repLegal" name="representante_legal"
                                            class="form-field" placeholder="Lic. Nombre Apellido" required>
                                    </div>
                                </div>
                                <div class="col-md-5">
                                    <div class="form-group mb-0">
                                        <label class="form-label" for="telefonoCelular">Teléfono del responsable</label>
                                        <input type="tel" id="telefonoCelular" name="telefono"
                                            class="form-field" placeholder="Ej. 4421234567" maxlength="15">
                                    </div>
                                </div>
                            </div>

                            <div class="form-group mb-4">
                                <label class="form-label" for="correoElectronico">Correo electrónico</label>
                                <input type="email" id="correoElectronico" name="correo_electronico"
                                    class="form-field" placeholder="contacto\@organizacion.mx">
                            </div>

                            <!-- 2. Domicilio de la Sede -->
                            <h6 class="text-uppercase text-secondary fw-bold mb-3" style="font-size: 0.75rem; letter-spacing: 0.5px; border-top: 1px solid #f0f0f0; padding-top: 1.5rem;">2. Domicilio de la Sede</h6>
                            <div class="row g-3 mb-3">
                                <div class="col-md-8">
                                    <div class="form-group mb-0">
                                        <label class="form-label" for="calle">Calle</label>
                                        <input type="text" id="calle" name="calle" class="form-field" placeholder="Ej. Av. Constituyentes">
                                    </div>
                                </div>
                                <div class="col-md-4">
                                    <div class="form-group mb-0">
                                        <label class="form-label" for="numero">Número</label>
                                        <input type="text" id="numero" name="numero" class="form-field" placeholder="Ej. 120-A">
                                    </div>
                                </div>
                            </div>
                            <div class="row g-3 mb-4">
                                <div class="col-md-5">
                                    <div class="form-group mb-0">
                                        <label class="form-label" for="colonia">Colonia</label>
                                        <input type="text" id="colonia" name="colonia" class="form-field" placeholder="Ej. Centro">
                                    </div>
                                </div>
                                <div class="col-md-4">
                                    <div class="form-group mb-0">
                                        <label class="form-label" for="municipio">Municipio</label>
                                        <select id="municipio" name="municipio" class="form-field">
                                            <option value="">Seleccione...</option>
HTML
                                            for my $m (@municipios) {
                                                print qq|<option value="$m->{nombre}">$m->{nombre}</option>\n|;
                                            }
print <<"HTML";
                                        </select>
                                    </div>
                                </div>
                                <div class="col-md-3">
                                    <div class="form-group mb-0">
                                        <label class="form-label" for="codigoPostal">C.P.</label>
                                        <input type="text" id="codigoPostal" name="codigo_postal" class="form-field" placeholder="Ej. 76000" maxlength="5">
                                    </div>
                                </div>
                            </div>

                            <!-- 3. Identidad Visual y Registro -->
                            <h6 class="text-uppercase text-secondary fw-bold mb-3" style="font-size: 0.75rem; letter-spacing: 0.5px; border-top: 1px solid #f0f0f0; padding-top: 1.5rem;">3. Registro e Identidad Visual</h6>
                            <div class="row g-3">
                                <div class="col-md-6 border-end pe-3">
                                    <div class="form-group mb-3">
                                        <label class="form-label" for="fechaAprobacion">Fecha de aprobación</label>
                                        <input type="date" id="fechaAprobacion" name="fecha_aprobacion" class="form-field">
                                    </div>
                                    <div class="form-group mb-3">
                                        <label class="form-label" for="estatus">Estatus de registro</label>
                                        <select id="estatus" name="estatus" class="form-field" onchange="toggleEstatusCampos()">
                                            <option value="VIGENTE">Vigente</option>
                                            <option value="SIN_REGISTRO">Sin registro</option>
                                        </select>
                                    </div>
                                    <div class="form-group mb-0" id="fechaPerdidaWrap" style="display:none;">
                                        <label class="form-label" for="fechaPerdida">Fecha pérdida del registro <span class="req">*</span></label>
                                        <input type="date" id="fechaPerdida" name="fecha_perdida_registro" class="form-field">
                                    </div>
                                </div>
                                <div class="col-md-6 ps-3">
                                    <label class="form-label">Emblema o logotipo</label>
                                    <div class="drop-zone" id="dropZone" style="min-height: 120px; padding: 1rem;">
                                        <div id="dropContent">
                                            <div class="drop-icon" style="font-size: 1.6rem;"><i class="bi bi-cloud-upload"></i></div>
                                            <div class="drop-text" style="font-size: 0.75rem;">Arrastra o haz clic para subir</div>
                                            <button type="button" class="btn-select-file py-1 px-3 mt-1" style="font-size: 0.75rem;">
                                            Subir imagen
                                            </button>
                                        </div>
                                        <div class="preview-container" id="previewContainer" style="width: 100px; height: 100px;">
                                            <img id="emblemaPreview" class="emblema-preview" alt="Preview emblema">
                                            <button type="button" class="btn-remove-preview" id="btnRemovePreview" title="Remover imagen" style="width: 22px; height: 22px; font-size: 0.7rem;">
                                                <i class="bi bi-trash-fill"></i>
                                            </button>
                                        </div>
                                    </div>
                                    <input type="file" id="fileEmblema" name="emblema_file" accept=".jpg,.jpeg,.png,.webp,.svg" class="d-none">
                                    <input type="hidden" id="emblemaActual" name="emblema_actual" value="">
                                    <div class="text-muted mt-2" style="font-size: 0.7rem; line-height: 1.3;">
                                        * Formatos: JPG, PNG, WEBP, SVG. Máx. 5MB.
                                    </div>
                                </div>
                            </div>

                        </div>
                        <div class="modal-footer" style="border-top: 1px solid #f3f3f3; padding: 1.2rem 1.5rem; justify-content: flex-end; gap: 10px; background: #fafafa; border-radius: 0 0 16px 16px;">
                            <button type="button" class="btn-cancel" data-bs-dismiss="modal">Cancelar</button>
                            <button type="submit" class="btn-save" id="btnGuardar">
                                <i class="bi bi-floppy-fill me-1"></i>Guardar Asociación
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>

        <!-- ============================================================ -->
        <!-- TAB 3: PADRÓN ELECTORAL DE REFERENCIA                        -->
        <!-- ============================================================ -->
        <div id="tab-padron" class="tab-content-pane" style="display:none;">
            <form id="formPadron" method="POST" novalidate>
                <div class="section-card">
                    <div class="section-header">
                        <div class="section-icon"><i class="bi bi-bar-chart-line"></i></div>
                        <div>
                            <p class="section-title">Padrón Electoral de Referencia RF-02</p>
                            <p class="section-subtitle">Datos generales para cálculo del umbral de afiliaciones</p>
                        </div>
                    </div>
                    <div class="section-body">
                        <div class="row g-3 mb-4">
                            <div class="col-md-5">
                                <div class="form-group mb-0">
                                    <label class="form-label" for="padronTotal">Padrón electoral del estado</label>
                                    <input type="text" id="padronTotal" name="padron_total"
                                        class="form-field" placeholder="1,500,000"
                                        value="$padron_formatted"
                                        oninput="formatPadron(this); calcularMinimo()">
                                </div>
                            </div>
                            <div class="col-md-4">
                                <div class="form-group mb-0">
                                    <label class="form-label" for="fechaCortePadron">Fecha de corte</label>
                                    <input type="date" id="fechaCortePadron" name="fecha_corte_padron"
                                        class="form-field" value="$fecha_corte">
                                </div>
                            </div>
                            <div class="col-md-3">
                                <div class="form-group mb-0">
                                    <label class="form-label" for="porcentajeMinimo">Porcentaje mínimo (%)</label>
                                    <input type="number" id="porcentajeMinimo" name="porcentaje_minimo"
                                        class="form-field" placeholder="0.13"
                                        value="$pct_minimo" step="0.0001" min="0"
                                        oninput="calcularMinimo()">
                                </div>
                            </div>
                        </div>

                        <!-- Tarjeta de cálculo automático -->
                        <div class="calc-card">
                            <div class="calc-label"><i class="bi bi-calculator me-1"></i>Mínimo requerido calculado</div>
                            <div class="calc-value" id="minimoCalculado">$minimo_formatted personas</div>
                            <div class="calc-desc" id="minimoDesc">
                                $padron_formatted electores × $pct_minimo%
                            </div>
                        </div>
                    </div>
                </div>

                <div class="action-bar">
                    <button type="submit" class="btn-save" id="btnGuardarPadron">
                        <i class="bi bi-floppy-fill"></i>Actualizar Padrón
                    </button>
                </div>
            </form>
        </div>

    </div><!-- #content -->
HTML

# Inyectar JSON sin interpolar el resto del JavaScript
print "    <script>\n";
print '    var ASOCIACIONES = ' . $asociaciones_json . ";\n";
print "    </script>\n\n";

print <<'HTML';
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    <script>
    (function () {
        'use strict';

        // ── Cambiar entre pestañas ──────────────────────────────────────────
        window.switchTab = function (tabId) {
            document.querySelectorAll('.tab-content-pane').forEach(function (el) {
                el.style.display = 'none';
            });
            document.querySelectorAll('.nav-tabs-ieeq .nav-link').forEach(function (btn) {
                btn.classList.remove('active');
            });

            document.getElementById('tab-' + tabId).style.display = 'block';
            document.getElementById('tab-' + tabId + '-btn').classList.add('active');
        };

        // ── Abrir Modal de Creación ──────────────────────────────────────────
        window.openCreateModal = function () {
            document.getElementById('asocId').value = '';
            document.getElementById('modalTitleText').textContent = 'Registrar Asociación';
            bootstrap.Modal.getOrCreateInstance(document.getElementById('modalAsociacion')).show();
        };

        // ── Filtrar asociaciones en la tabla ────────────────────────────────
        window.filtrarAsociaciones = function () {
            var q = document.getElementById('asocSearch').value.toLowerCase().trim();
            var filtered = q === ''
                ? ASOCIACIONES
                : ASOCIACIONES.filter(function (a) {
                    return (a.nombre||'').toLowerCase().includes(q)
                        || (a.representante_legal||'').toLowerCase().includes(q)
                        || (a.municipio||'').toLowerCase().includes(q);
                });
            renderTable(filtered);
        };

        // ── Renderizar la tabla de asociaciones ──────────────────────────────
        function renderTable(list) {
            var tbody = document.getElementById('asocTableBody');
            tbody.innerHTML = '';
            if (list.length === 0) {
                tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted py-4"><i class="bi bi-inbox fs-3 d-block mb-1 opacity-50"></i>No hay asociaciones registradas</td></tr>';
                return;
            }

            list.forEach(function (a) {
                var tr = document.createElement('tr');
                
                // Emblema logo col
                var logoHtml = '';
                if (a.emblema) {
                    logoHtml = '<img src="uploads/emblemas/' + a.emblema + '" class="asoc-logo" alt="Logo">';
                } else {
                    var ini = (a.nombre || 'A').charAt(0).toUpperCase();
                    logoHtml = '<div class="asoc-logo-placeholder">' + ini + '</div>';
                }

                // Domicilio formateado
                var domParts = [];
                if (a.calle) domParts.push(a.calle);
                if (a.numero) domParts.push('#' + a.numero);
                if (a.colonia) domParts.push('Col. ' + a.colonia);
                if (a.municipio) domParts.push(a.municipio);
                if (a.codigo_postal) domParts.push('C.P. ' + a.codigo_postal);
                var domicilio = domParts.join(', ') || '<span class="text-muted">No registrado</span>';

                // Estatus badge
                var badgeHtml = a.estatus === 'VIGENTE'
                    ? '<span class="badge bg-success-subtle text-success border border-success-subtle px-3 py-1 rounded-pill" style="font-size:0.75rem;">Vigente</span>'
                    : '<span class="badge bg-danger-subtle text-danger border border-danger-subtle px-3 py-1 rounded-pill" style="font-size:0.75rem;">Sin registro</span>';

                tr.innerHTML =
                    '<td>' + logoHtml + '</td>' +
                    '<td>' +
                        '<div class="fw-bold text-dark">' + a.nombre + '</div>' +
                        '<div class="text-muted" style="font-size:0.75rem;">' + domicilio + '</div>' +
                    '</td>' +
                    '<td><div class="fw-semibold text-secondary">' + a.representante_legal + '</div></td>' +
                    '<td>' +
                        '<div style="font-size:0.825rem;"><i class="bi bi-envelope text-muted me-1"></i>' + (a.correo_electronico || '-') + '</div>' +
                        '<div style="font-size:0.825rem;"><i class="bi bi-telephone text-muted me-1"></i>' + (a.telefono || '-') + '</div>' +
                    '</td>' +
                    '<td>' + badgeHtml + '</td>' +
                    '<td class="text-end">' +
                        '<button class="btn-action-asoc edit me-2" onclick="editAsociacion(' + a.id_asociacion + ')" title="Editar">' +
                            '<i class="bi bi-pencil" style="font-size:1.1rem;"></i>' +
                        '</button>' +
                        '<button class="btn-action-asoc delete" onclick="deleteAsociacion(' + a.id_asociacion + ')" title="Eliminar">' +
                            '<i class="bi bi-trash" style="font-size:1.1rem;"></i>' +
                        '</button>' +
                    '</td>';
                tbody.appendChild(tr);
            });
        }

        // ── Cargar para editar ───────────────────────────────────────────────
        window.editAsociacion = function (id) {
            var a = ASOCIACIONES.find(function (x) { return x.id_asociacion == id; });
            if (!a) return;

            document.getElementById('asocId').value = a.id_asociacion;
            document.getElementById('nombreAsociacion').value = a.nombre || '';
            document.getElementById('repLegal').value = a.representante_legal || '';
            document.getElementById('telefonoCelular').value = a.telefono || '';
            document.getElementById('correoElectronico').value = a.correo_electronico || '';
            document.getElementById('calle').value = a.calle || '';
            document.getElementById('numero').value = a.numero || '';
            document.getElementById('colonia').value = a.colonia || '';
            document.getElementById('municipio').value = a.municipio || '';
            document.getElementById('codigoPostal').value = a.codigo_postal || '';
            document.getElementById('fechaAprobacion').value = a.fecha_aprobacion || '';
            document.getElementById('fechaPerdida').value = a.fecha_perdida_registro || '';
            document.getElementById('estatus').value = a.estatus || 'VIGENTE';
            document.getElementById('emblemaActual').value = a.emblema || '';

            // Preview de imagen
            var preview = document.getElementById('emblemaPreview');
            var container = document.getElementById('previewContainer');
            var dropContent = document.getElementById('dropContent');

            if (a.emblema) {
                preview.src = 'uploads/emblemas/' + a.emblema;
                container.classList.add('has-img');
                dropContent.style.display = 'none';
            } else {
                preview.src = '';
                container.classList.remove('has-img');
                dropContent.style.display = 'block';
            }

            toggleEstatusCampos();

            document.getElementById('modalTitleText').textContent = 'Editar Asociación';
            bootstrap.Modal.getOrCreateInstance(document.getElementById('modalAsociacion')).show();
        };

        // ── Eliminar asociación ──────────────────────────────────────────────
        window.deleteAsociacion = function (id) {
            var a = ASOCIACIONES.find(function (x) { return x.id_asociacion == id; });
            if (!a) return;

            Swal.fire({
                title: '¿Eliminar asociación?',
                text: 'Esta acción borrará permanentemente la asociación "' + a.nombre + '".',
                icon: 'warning',
                showCancelButton: true,
                confirmButtonColor: '#e53935',
                cancelButtonColor: '#6c757d',
                confirmButtonText: 'Sí, eliminar',
                cancelButtonText: 'Cancelar'
            }).then(function (res) {
                if (res.isConfirmed) {
                    var fd = new FormData();
                    fd.append('accion', 'eliminar');
                    fd.append('id_asociacion', id);

                    fetch('asociacion.pl', { method: 'POST', body: fd })
                        .then(function (r) { return r.json(); })
                        .then(function (data) {
                            if (data.success) {
                                Swal.fire({
                                    icon: 'success', title: 'Eliminado', text: data.message,
                                    timer: 2000, showConfirmButton: false
                                }).then(function () {
                                    location.reload();
                                });
                            } else {
                                Swal.fire({ icon: 'error', title: 'No se pudo eliminar', text: data.message });
                            }
                        })
                        .catch(function (err) {
                            Swal.fire({ icon: 'error', title: 'Error de red', text: err.message });
                        });
                }
            });
        };

        // ── Resetear Formulario ──────────────────────────────────────────────
        window.resetForm = function () {
            document.getElementById('formAsociacion').reset();
            document.getElementById('asocId').value = '';
            document.getElementById('emblemaActual').value = '';
            
            var preview = document.getElementById('emblemaPreview');
            var container = document.getElementById('previewContainer');
            var dropContent = document.getElementById('dropContent');
            preview.src = '';
            container.classList.remove('has-img');
            dropContent.style.display = 'block';

            toggleEstatusCampos();
        };

        // ── Ocultar/mostrar campos de pérdida de registro ────────────────────
        window.toggleEstatusCampos = function () {
            var estatus = document.getElementById('estatus').value;
            var wrap = document.getElementById('fechaPerdidaWrap');
            if (estatus === 'SIN_REGISTRO') {
                wrap.style.display = 'block';
                document.getElementById('fechaPerdida').setAttribute('required', 'required');
            } else {
                wrap.style.display = 'none';
                document.getElementById('fechaPerdida').removeAttribute('required');
            }
        };

        // ── Padrón Electoral: Cálculo del Mínimo ─────────────────────────────
        window.calcularMinimo = function () {
            var rawPadron = document.getElementById('padronTotal').value.replace(/,/g, '');
            var padron    = parseInt(rawPadron, 10) || 0;
            var pct       = parseFloat(document.getElementById('porcentajeMinimo').value) || 0;
            var minimo    = Math.round(padron * pct / 100);

            var minimoFmt = minimo.toLocaleString('es-MX');
            var padronFmt = padron.toLocaleString('es-MX');

            document.getElementById('minimoCalculado').textContent = minimoFmt + ' personas';
            document.getElementById('minimoDesc').textContent = padronFmt + ' electores × ' + pct + '%';
        };

        window.formatPadron = function (inp) {
            var raw = inp.value.replace(/[^0-9]/g, '');
            if (raw === '') { inp.value = ''; return; }
            inp.value = parseInt(raw, 10).toLocaleString('es-MX');
        };

        // ── Drag & Drop y Selección de Emblema ────────────────────────────────
        var dropZone    = document.getElementById('dropZone');
        var fileInput   = document.getElementById('fileEmblema');
        var preview     = document.getElementById('emblemaPreview');
        var container   = document.getElementById('previewContainer');
        var dropContent = document.getElementById('dropContent');
        var btnRemove   = document.getElementById('btnRemovePreview');

        function handleFile(file) {
            if (!file) return;
            var validTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/svg+xml'];
            var validExts = /\.(jpe?g|png|webp|svg)$/i;
            if (!validTypes.includes(file.type) && !validExts.test(file.name)) {
                Swal.fire({ 
                    icon: 'error', 
                    title: 'Formato incorrecto', 
                    text: 'Se permiten formatos JPG, PNG, WEBP y SVG.' 
                });
                return;
            }
            if (file.size > 5242880) { // 5 MB
                Swal.fire({ 
                    icon: 'error', 
                    title: 'Archivo muy pesado', 
                    text: 'El tamaño máximo permitido es de 5 MB.' 
                });
                return;
            }
            
            var reader = new FileReader();
            reader.onload = function (e) {
                preview.src = e.target.result;
                container.classList.add('has-img');
                dropContent.style.display = 'none';
            };
            reader.readAsDataURL(file);
        }

        dropZone.addEventListener('dragover',  function (e) { e.preventDefault(); dropZone.classList.add('drag-over'); });
        dropZone.addEventListener('dragleave', function ()  { dropZone.classList.remove('drag-over'); });
        dropZone.addEventListener('drop', function (e) {
            e.preventDefault(); dropZone.classList.remove('drag-over');
            if (e.dataTransfer.files.length) {
                fileInput.files = e.dataTransfer.files;
                handleFile(e.dataTransfer.files[0]);
            }
        });
        
        // El dropZone responde al click si no tiene imagen mostrándose
        dropZone.addEventListener('click', function (e) {
            if (e.target.closest('#btnRemovePreview')) return; // No abrir file selector si clickean borrar
            fileInput.click();
        });
        
        fileInput.addEventListener('change', function () {
            if (this.files.length) handleFile(this.files[0]);
        });

        btnRemove.addEventListener('click', function (e) {
            e.stopPropagation(); // Evitar disparar click de la dropZone
            fileInput.value = '';
            document.getElementById('emblemaActual').value = '';
            preview.src = '';
            container.classList.remove('has-img');
            dropContent.style.display = 'block';
        });

        // ── Guardar formulario de asociación ─────────────────────────────────
        document.getElementById('formAsociacion').addEventListener('submit', function (e) {
            e.preventDefault();

            var nombreAsoc = document.getElementById('nombreAsociacion').value.trim();
            var repLegal   = document.getElementById('repLegal').value.trim();
            if (!nombreAsoc || !repLegal) {
                Swal.fire({ icon: 'warning', title: 'Campos requeridos', text: 'El nombre de la asociación y el representante legal son obligatorios.' });
                return;
            }

            var estatus = document.getElementById('estatus').value;
            var fechaPerdida = document.getElementById('fechaPerdida').value;
            if (estatus === 'SIN_REGISTRO' && !fechaPerdida) {
                Swal.fire({ icon: 'warning', title: 'Campo requerido', text: 'Debe ingresar la fecha de pérdida del registro.' });
                return;
            }

            var btnSave = document.getElementById('btnGuardar');
            var origHTML = btnSave.innerHTML;
            btnSave.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Guardando...';
            btnSave.disabled  = true;

            var fd = new FormData(this);
            fd.append('accion', 'guardar');

            fetch('asociacion.pl', { method: 'POST', body: fd })
                .then(function (r) { return r.json(); })
                .then(function (data) {
                    btnSave.innerHTML = origHTML;
                    btnSave.disabled  = false;
                    if (data.success) {
                        Swal.fire({
                            icon: 'success', title: '¡Guardado!', text: data.message,
                            timer: 2000, showConfirmButton: false
                        }).then(function () {
                            location.reload();
                        });
                    } else {
                        throw new Error(data.message || 'Error desconocido');
                    }
                })
                .catch(function (err) {
                    btnSave.innerHTML = origHTML;
                    btnSave.disabled  = false;
                    Swal.fire({ icon: 'error', title: 'Error', text: err.message });
                });
        });

        // ── Guardar formulario de padrón ─────────────────────────────────────
        document.getElementById('formPadron').addEventListener('submit', function (e) {
            e.preventDefault();

            var padronTotal = document.getElementById('padronTotal').value.trim();
            if (!padronTotal) {
                Swal.fire({ icon: 'warning', title: 'Campo requerido', text: 'El padrón electoral del estado es obligatorio.' });
                return;
            }

            var btnSave = document.getElementById('btnGuardarPadron');
            var origHTML = btnSave.innerHTML;
            btnSave.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Actualizando...';
            btnSave.disabled  = true;

            var fd = new FormData(this);
            fd.append('accion', 'guardar_padron');

            fetch('asociacion.pl', { method: 'POST', body: fd })
                .then(function (r) { return r.json(); })
                .then(function (data) {
                    btnSave.innerHTML = origHTML;
                    btnSave.disabled  = false;
                    if (data.success) {
                        Swal.fire({
                            toast: true, position: 'top-end', icon: 'success',
                            title: data.message,
                            showConfirmButton: false, timer: 3000, timerProgressBar: true
                        });
                    } else {
                        throw new Error(data.message || 'Error desconocido');
                    }
                })
                .catch(function (err) {
                    btnSave.innerHTML = origHTML;
                    btnSave.disabled  = false;
                    Swal.fire({ icon: 'error', title: 'Error', text: err.message });
                });
        });

        // Escuchar cuando el modal se oculta para resetear el formulario
        document.getElementById('modalAsociacion').addEventListener('hidden.bs.modal', function () {
            resetForm();
        });

        // Cargar tabla inicial
        renderTable(ASOCIACIONES);

    })();
    </script>
</body>
</html>
HTML
