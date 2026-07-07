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

if (!$rol) { print $cgi->redirect(-uri => 'login.pl'); exit; }
if ($rol ne 'administrador' && $rol ne 'funcionario' && $rol ne 'integrante_organizacion') {
    print $cgi->redirect(-uri => 'dashboard.pl');
    exit;
}

# ==========================================
# ENDPOINTS AJAX
# ==========================================
my $accion = $cgi->param('accion') || '';

if ($accion eq 'cambiar_estatus') {
    my $id_afil  = $cgi->param('id_afiliacion') || 0;
    my $nuevo    = $cgi->param('estatus') || '';
    my %permitidos = (VERIFICADO => 1, EN_REVISION => 1, RECHAZADO => 1, NUEVA => 1);
    if ($id_afil && $permitidos{$nuevo}) {
        my $query = "UPDATE afiliaciones SET estatus = ?";
        my @params = ($nuevo);
        if ($nuevo eq 'VERIFICADO') {
            $query .= ", situacion_padron = 'Localizado'";
        } elsif ($nuevo eq 'RECHAZADO') {
            $query .= ", situacion_padron = 'No localizado'";
        }
        $query .= " WHERE id_afiliacion = ?";
        push @params, $id_afil;
        my $ok = execute_query_write($query, @params);

        execute_query_write(
            "INSERT INTO bitacora (id_usuario, accion, modulo, detalles, fecha) VALUES (?, ?, 'afiliaciones', ?, NOW())",
            $id_usuario_sesion,
            ($nuevo eq 'VERIFICADO' ? 'APROBACION' : ($nuevo eq 'RECHAZADO' ? 'RECHAZO' : 'EDICION')),
            "Estatus de afiliación ID $id_afil cambiado a $nuevo"
        );
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => $ok ? 1 : 0 });
    } else {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'Parámetros inválidos' });
    }
    exit;
}

if ($accion eq 'obtener_detalle') {
    my $id_afil = $cgi->param('id_afiliacion') || 0;
    my @afil = execute_query_list("
        SELECT
            a.id_afiliacion,
            a.nombre,
            a.apellido_paterno,
            a.apellido_materno,
            a.clave_elector,
            a.ocr,
            a.cic,
            a.curp,
            a.domicilio_calle,
            a.domicilio_numero,
            a.domicilio_colonia,
            COALESCE(m.nombre, '') AS domicilio_municipio,
            'Querétaro' AS domicilio_estado,
            a.domicilio_cp,
            a.estatus,
            a.situacion_padron,
            a.foto_anverso_ine,
            a.foto_reverso_ine,
            a.foto_persona,
            a.firma,
            DATE_FORMAT(a.fecha_hora_afiliacion,'%Y-%m-%d %H:%i') AS fecha
        FROM afiliaciones a
        LEFT JOIN municipios m ON a.id_municipio_afiliacion = m.id_municipio
        WHERE a.id_afiliacion = ? AND a.fecha_eliminacion IS NULL
        LIMIT 1
    ", $id_afil);

    if (@afil) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 1, data => $afil[0] });
    } else {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'Afiliación no encontrada' });
    }
    exit;
}

if ($accion eq 'eliminar_afiliacion') {
    my $id_afil = $cgi->param('id_afiliacion') || 0;
    my $puedo_eliminar = 0;
    
    if ($id_afil) {
        if ($rol eq 'administrador') {
            $puedo_eliminar = 1;
        } else {
            my @afil = execute_query_list("SELECT id_registrador, estatus FROM afiliaciones WHERE id_afiliacion = ?", $id_afil);
            if (@afil && $afil[0]->{id_registrador} == $id_usuario_sesion && $afil[0]->{estatus} eq 'NUEVA') {
                $puedo_eliminar = 1;
            }
        }
    }
    
    if ($puedo_eliminar) {
        my $ok = execute_query_write(
            "UPDATE afiliaciones SET fecha_eliminacion = NOW(), id_usuario_eliminacion = ? WHERE id_afiliacion = ?",
            $id_usuario_sesion, $id_afil
        );
        execute_query_write(
            "INSERT INTO bitacora (id_usuario, accion, modulo, detalles, fecha) VALUES (?, 'ELIMINACION', 'afiliaciones', ?, NOW())",
            $id_usuario_sesion,
            "Afiliación ID $id_afil eliminada por usuario"
        );
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => $ok ? 1 : 0 });
    } else {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'No autorizado o registro no válido para eliminar' });
    }
    exit;
}

# ==========================================
# CARGA DE DATOS
# ==========================================
my $where_afiliados = "WHERE a.fecha_eliminacion IS NULL";
my $where_counts = "WHERE fecha_eliminacion IS NULL";
my @params_afiliados = ();
my @params_counts = ();

if ($rol eq 'integrante_organizacion') {
    $where_afiliados .= " AND a.id_registrador = ?";
    push @params_afiliados, $id_usuario_sesion;

    $where_counts .= " AND id_registrador = ?";
    push @params_counts, $id_usuario_sesion;
}

# Conteos generales
my @counts = execute_query_list("
    SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN estatus = 'NUEVA'        THEN 1 ELSE 0 END) AS nuevas,
        SUM(CASE WHEN estatus = 'EN_REVISION'  THEN 1 ELSE 0 END) AS en_revision,
        SUM(CASE WHEN estatus = 'VERIFICADO'   THEN 1 ELSE 0 END) AS verificadas,
        SUM(CASE WHEN estatus = 'RECHAZADO'    THEN 1 ELSE 0 END) AS rechazadas
    FROM afiliaciones $where_counts
", @params_counts);
my $cnt_total     = $counts[0]->{total}      || 0;
my $cnt_nuevas    = $counts[0]->{nuevas}     || 0;
my $cnt_revision  = $counts[0]->{en_revision}|| 0;
my $cnt_verif     = $counts[0]->{verificadas}|| 0;
my $cnt_rechaz    = $counts[0]->{rechazadas} || 0;

# Alerta de nuevas pendientes
my $alerta_html = '';
if ($cnt_nuevas > 0) {
    $alerta_html = <<"ALERTA";
<div class="alert-banner">
    <i class="bi bi-exclamation-triangle-fill me-2" style="color:#d97706;"></i>
    Tienes <strong>$cnt_nuevas afiliaciones</strong> con estatus <strong>«Nueva»</strong> pendientes de enviar a revisión.
</div>
ALERTA
}

# Lista completa de afiliados
my @afiliados = execute_query_list("
    SELECT
        a.id_afiliacion,
        CONCAT(a.nombre,' ',a.apellido_paterno,COALESCE(CONCAT(' ',a.apellido_materno),'')) AS nombre_completo,
        a.apellido_paterno,
        a.clave_elector,
        m.nombre AS municipio,
        DATE_FORMAT(a.fecha_hora_afiliacion,'%Y-%m-%d %H:%i') AS fecha,
        a.estatus,
        a.situacion_padron,
        a.cedula_folio AS folio,
        COALESCE(CONCAT(u.nombre,' ',u.apellido_paterno),'—')   AS capturado_por,
        COALESCE(u.correo_electronico,'')                        AS correo_capturador
    FROM afiliaciones a
    LEFT JOIN usuarios u ON a.id_registrador = u.id_usuario
    LEFT JOIN municipios m ON a.id_municipio_afiliacion = m.id_municipio
    $where_afiliados
    ORDER BY a.fecha_hora_afiliacion DESC
", @params_afiliados);

# ==========================================
# HELPER: badge de estatus
# ==========================================
sub estatus_badge {
    my ($est) = @_;
    my %map = (
        'NUEVA'       => ['badge-nueva',     'Nueva afiliación'],
        'EN_REVISION' => ['badge-revision',  'En revisión'],
        'VERIFICADO'  => ['badge-verif',     'Verificado'],
        'RECHAZADO'   => ['badge-rechaz',    'Rechazada'],
    );
    my $d = $map{$est} // ['badge-default', $est];
    return sprintf('<span class="estatus-badge %s">%s</span>', $d->[0], $d->[1]);
}

# Colores avatar
my @AV_COLORS = ('#7c3aed','#2563eb','#059669','#db2777','#d97706','#0891b2','#6f42c1');
sub av_color { my $s=0; $s+=ord($_) for split//,($_[0]||''); return $AV_COLORS[$s%7]; }
sub initials {
    my @p = split /\s+/, ($_[0]||''); my $i='';
    $i .= uc(substr($p[0],0,1)) if @p>0;
    $i .= uc(substr($p[1],0,1)) if @p>1;
    return $i || '?';
}

# Construir filas HTML
my $rows_html = '';
my $idx = 0;
for my $a (@afiliados) {
    $idx++;
    my $ini   = initials($a->{nombre_completo});
    my $clr   = av_color($a->{nombre_completo});
    my $badge = estatus_badge($a->{estatus});
    my $ini_cap = initials($a->{capturado_por});
    my $clr_cap = av_color($a->{capturado_por});
    my $est  = $a->{estatus} || 'NUEVA';
    my $id   = $a->{id_afiliacion};
    my $clave = $a->{clave_elector} || '—';
    my $mun   = $a->{municipio} || '—';
    my $fecha = $a->{fecha} || '—';
    my $cap   = $a->{capturado_por} || '—';
    my $folio = $a->{folio} || '';

    # Situación Padrón
    my $sit_padron = $a->{situacion_padron};
    if (!defined $sit_padron || $sit_padron eq '') {
        if ($est eq 'NUEVA')          { $sit_padron = 'En verificación'; }
        elsif ($est eq 'EN_REVISION')  { $sit_padron = 'Localizado'; }
        elsif ($est eq 'VERIFICADO')   { $sit_padron = 'Localizado'; }
        elsif ($est eq 'RECHAZADO')    { $sit_padron = 'No localizado'; }
        else                          { $sit_padron = 'En verificación'; }
    }

    my $padron_class = 'padron-verificacion';
    if ($sit_padron eq 'Localizado') {
        $padron_class = 'padron-localizado';
    } elsif ($sit_padron eq 'No localizado') {
        $padron_class = 'padron-nolocalizado';
    }

    # Dots de flujo según estatus
    my ($d1, $d2, $d3, $d4) = ('dot-empty', 'dot-empty', 'dot-empty', 'dot-empty');
    my ($l1, $l2, $l3) = ('line-empty', 'line-empty', 'line-empty');

    if ($est eq 'NUEVA') {
        $d1 = 'dot-active';
    } elsif ($est eq 'EN_REVISION') {
        $d1 = 'dot-active'; $l1 = 'line-active'; $d2 = 'dot-active';
    } elsif ($est eq 'VERIFICADO') {
        $d1 = 'dot-active'; $l1 = 'line-active'; $d2 = 'dot-active'; $l2 = 'line-active'; $d3 = 'dot-active';
    }

    my $d4_html = '';
    if ($est eq 'RECHAZADO') {
        $d4_html = '<span class="flujo-dot-x" title="Rechazada"><i class="bi bi-x-lg text-danger" style="font-size: 0.7rem; font-weight: bold;"></i></span>';
    } else {
        $d4_html = "<span class=\"flujo-dot $d4\"></span>";
    }

    # Botones de acción
    my $action_buttons = sprintf(
        '<button class="btn-accion btn-ver" title="Ver detalle" onclick="verDetalle(%d)"><i class="bi bi-eye"></i></button>',
        $id
    );

    if ($rol eq 'integrante_organizacion') {
        if ($est eq 'NUEVA') {
            $action_buttons .= sprintf(
                ' <button class="btn-accion btn-editar" title="Editar" onclick="window.location.href=\'registro_afiliados.pl?id=%d\'"><i class="bi bi-pencil"></i></button>' .
                ' <button class="btn-accion btn-eliminar" title="Eliminar" onclick="eliminarAfiliacion(%d)"><i class="bi bi-trash"></i></button>',
                $id, $id
            );
        }
    } elsif ($rol eq 'administrador') {
        if ($est eq 'NUEVA') {
            $action_buttons .= sprintf(
                ' <button class="btn-accion btn-editar" title="Editar" onclick="window.location.href=\'registro_afiliados.pl?id=%d\'"><i class="bi bi-pencil"></i></button>' .
                ' <button class="btn-accion btn-aprobar" style="background-color: #6B2D8B; color: white;" title="Enviar a revisión" onclick="cambiarEstatus(%d,\'EN_REVISION\')"><i class="bi bi-send"></i></button>' .
                ' <button class="btn-accion btn-eliminar" title="Eliminar" onclick="eliminarAfiliacion(%d)"><i class="bi bi-trash"></i></button>',
                $id, $id, $id
            );
        }
        if ($est eq 'VERIFICADO' || $est eq 'EN_REVISION') {
            my $url_cedula = $folio ? "cedulas.pl?id=$id" : "cedulas.pl?generar_id=$id";
            $action_buttons .= sprintf(
                ' <button class="btn-accion btn-cedula" title="Cédula de Afiliación" onclick="window.location.href=\'%s\'"><i class="bi bi-award"></i></button>',
                $url_cedula
            );
        }
    } elsif ($rol eq 'funcionario') {
        if ($est eq 'EN_REVISION') {
            $action_buttons .= sprintf(
                ' <button class="btn-accion btn-aprobar" title="Verificar" onclick="cambiarEstatus(%d,\'VERIFICADO\')"><i class="bi bi-check-lg"></i></button>' .
                ' <button class="btn-accion btn-rechaz" title="Rechazar" onclick="cambiarEstatus(%d,\'RECHAZADO\')"><i class="bi bi-x-lg"></i></button>',
                $id, $id
            );
        }
        if ($est eq 'VERIFICADO' || $est eq 'EN_REVISION') {
            my $url_cedula = $folio ? "cedulas.pl?id=$id" : "cedulas.pl?generar_id=$id";
            $action_buttons .= sprintf(
                ' <button class="btn-accion btn-cedula" title="Cédula de Afiliación" onclick="window.location.href=\'%s\'"><i class="bi bi-award"></i></button>',
                $url_cedula
            );
        }
    }

    if ($rol eq 'integrante_organizacion') {
        $rows_html .= <<"ROW";
<tr data-id="$id" data-estatus="$est">
    <td class="td-num text-muted">$idx</td>
    <td class="td-nombre">
        <div class="d-flex align-items-center gap-2">
            <div class="af-avatar" style="background:$clr;">$ini</div>
            <div>
                <div class="fw-semibold af-name">$a->{nombre_completo}</div>
                <div class="text-muted" style="font-size:0.75rem;">$mun</div>
            </div>
        </div>
    </td>
    <td class="td-clave font-monospace text-muted" style="font-size:0.82rem;">$clave</td>
    <td class="td-mun text-secondary" style="font-size:0.85rem;">$mun</td>
    <td class="td-fecha text-secondary" style="font-size:0.83rem;">$fecha</td>
    <td>$badge</td>
    <td>
        <div class="flujo-dots">
            <span class="flujo-dot $d1"></span>
            <span class="flujo-line $l1"></span>
            <span class="flujo-dot $d2"></span>
            <span class="flujo-line $l2"></span>
            <span class="flujo-dot $d3"></span>
            <span class="flujo-line $l3"></span>
            $d4_html
        </div>
    </td>
    <td>
        <div class="d-flex align-items-center gap-1">
            $action_buttons
        </div>
    </td>
</tr>
ROW
    } else {
        $rows_html .= <<"ROW";
<tr data-id="$id" data-estatus="$est">
    <td class="td-num text-muted">$idx</td>
    <td class="td-nombre">
        <div class="d-flex align-items-center gap-2">
            <div class="af-avatar" style="background:$clr;">$ini</div>
            <div>
                <div class="fw-semibold af-name">$a->{nombre_completo}</div>
                <div class="text-muted" style="font-size:0.75rem;">$mun</div>
            </div>
        </div>
    </td>
    <td class="td-clave font-monospace text-muted" style="font-size:0.82rem;">$clave</td>
    <td class="td-mun text-secondary" style="font-size:0.85rem;">$mun</td>
    <td class="td-fecha text-secondary" style="font-size:0.83rem;">$fecha</td>
    <td>$badge</td>
    <td>
        <div class="flujo-dots">
            <span class="flujo-dot $d1"></span>
            <span class="flujo-line $l1"></span>
            <span class="flujo-dot $d2"></span>
            <span class="flujo-line $l2"></span>
            <span class="flujo-dot $d3"></span>
            <span class="flujo-line $l3"></span>
            $d4_html
        </div>
    </td>
    <td>
        <span class="padron-status $padron_class">$sit_padron</span>
    </td>
    <td>
        <div class="d-flex align-items-center gap-2">
            <div class="cap-avatar" style="background:$clr_cap;">$ini_cap</div>
            <span style="font-size:0.82rem;">$cap</span>
        </div>
    </td>
    <td>
        <div class="d-flex align-items-center gap-1">
            $action_buttons
        </div>
    </td>
</tr>
ROW
    }
}

my $colspan_empty = $rol eq 'integrante_organizacion' ? 8 : 10;
$rows_html = '<tr><td colspan="' . $colspan_empty . '" class="text-center text-muted py-5"><i class="bi bi-inbox fs-2 d-block mb-2 opacity-50"></i>No hay afiliaciones registradas.</td></tr>' unless $rows_html;

my $header_titulo = "Listado de Afiliados";
my $header_sub = "Gestiona estatus y genera cédulas.";
my $header_count_text = "$cnt_total afiliaciones en total";

if ($rol eq 'funcionario') {
    $header_titulo = "Consulta de Registros";
    $header_sub = "Consulta y Verificación de Registros";
    $header_count_text = "$cnt_total afiliaciones registradas. Verifica y genera cédulas.";
} elsif ($rol eq 'integrante_organizacion') {
    $header_titulo = "Mis Registros";
    $header_sub = "Mis Registros";
    $header_count_text = "$cnt_total afiliaciones capturadas por ti.";
}

# Alerta banners
my $alertas_html = '';
if ($rol eq 'funcionario') {
    $alertas_html .= <<"ALERT";
<div class="alert-banner-info">
    <i class="bi bi-info-circle-fill me-2" style="font-size: 1.1rem; color: #0284c7;"></i>
    <div><strong>Modo verificación:</strong> Acceso de solo lectura a $cnt_total registros. Puedes verificar o rechazar las afiliaciones en estatus «En revisión» y generar cédulas de las verificadas.</div>
</div>
ALERT
    if ($cnt_revision > 0) {
        $alertas_html .= <<"ALERT";
<div class="alert-banner-info" style="background:#eff6ff; border-color:#bfdbfe; color:#1d4ed8; margin-top: -0.6rem;">
    <i class="bi bi-shield-fill-check me-2" style="font-size: 1.1rem; color:#2563eb;"></i>
    <div>Hay <strong>$cnt_revision afiliaciones «En revisión»</strong> esperando tu verificación en el padrón electoral.</div>
</div>
ALERT
    }
} elsif ($rol eq 'integrante_organizacion') {
    $alertas_html .= <<"ALERT";
<div class="alert-banner-personal">
    <i class="bi bi-info-circle me-2" style="font-size: 1.1rem; color: #701a75;"></i>
    <div><strong>Vista personal:</strong> Visualizas únicamente tus $cnt_total registros capturados. Puedes editar o eliminar solo los que tengan estatus «Nueva afiliación».</div>
</div>
ALERT
} else {
    $alertas_html = $alerta_html;
}

my $table_headers_html = '';
if ($rol eq 'integrante_organizacion') {
    $table_headers_html = <<"HEADERS";
                        <tr>
                            <th>#</th>
                            <th>NOMBRE COMPLETO</th>
                            <th>CLAVE DE ELECTOR</th>
                            <th>MUNICIPIO</th>
                            <th>FECHA</th>
                            <th>ESTATUS</th>
                            <th>FLUJO</th>
                            <th>ACCIONES</th>
                        </tr>
HEADERS
} else {
    $table_headers_html = <<"HEADERS";
                        <tr>
                            <th>#</th>
                            <th>NOMBRE COMPLETO</th>
                            <th>CLAVE DE ELECTOR</th>
                            <th>MUNICIPIO</th>
                            <th>FECHA</th>
                            <th>ESTATUS</th>
                            <th>FLUJO</th>
                            <th>SITUACIÓN PADRÓN</th>
                            <th>CAPTURADO POR</th>
                            <th>ACCIONES</th>
                        </tr>
HEADERS
}

print $cgi->header(-type=>'text/html',-charset=>'utf-8',-expires=>'now',
    -Cache_Control=>'no-store,no-cache,must-revalidate,max-age=0',-Pragma=>'no-cache');

print <<"HTML";
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$header_titulo - IEEQ</title>
    <meta name="description" content="Listado completo de afiliaciones registradas en el sistema IEEQ.">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons\@1.11.3/font/bootstrap-icons.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght\@300;400;500;600;700&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/sweetalert2\@11"></script>
    <style>
        *{box-sizing:border-box;}
        body{font-family:'Outfit',sans-serif;background:#f5f5f8;overflow-x:hidden;margin:0;}
        #content{margin-left:260px;min-height:100vh;padding:2rem;transition:margin-left .3s;}

        /* ── Page header ── */
        .page-header{display:flex;justify-content:space-between;align-items:center;
            background:#fff;padding:1rem 1.5rem;border-radius:14px;
            box-shadow:0 2px 12px rgba(0,0,0,.05);margin-bottom:1.5rem;}
        .page-header h4{margin:0;font-weight:700;color:#1a1a2e;font-size:1.3rem;}
        .page-header p{margin:0;color:#6c757d;font-size:.85rem;}

        /* ── Alert banner ── */
        .alert-banner{background:#fffbeb;border:1px solid #fde68a;border-radius:12px;
            padding:.85rem 1.2rem;font-size:.85rem;color:#92400e;margin-bottom:1.2rem;}
        
        .alert-banner-info {
            background: #eff6ff;
            border: 1px solid #bfdbfe;
            border-radius: 12px;
            padding: .85rem 1.2rem;
            font-size: .85rem;
            color: #1e3a8a;
            margin-bottom: 1.2rem;
            display: flex;
            align-items: center;
        }

        .alert-banner-personal {
            background: #faf5ff;
            border: 1px solid #e9d5ff;
            border-radius: 12px;
            padding: .85rem 1.2rem;
            font-size: .85rem;
            color: #6b21a8;
            margin-bottom: 1.2rem;
            display: flex;
            align-items: center;
        }

        /* ── Filtros pill ── */
        .filter-tabs{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:1.2rem;align-items:center;}
        .ftab{padding:6px 18px;border-radius:20px;border:none;font-family:'Outfit',sans-serif;
            font-size:.82rem;font-weight:600;cursor:pointer;transition:all .2s;
            background:#f0f0f0;color:#6c757d;}
        .ftab:hover{background:#e8e0f0;color:#6B2D8B;}
        .ftab.active{background:#6B2D8B;color:#fff;}
        .ftab .badge-count{background:rgba(255,255,255,.3);border-radius:10px;
            padding:1px 7px;font-size:.72rem;margin-left:6px;}
        .ftab:not(.active) .badge-count{background:rgba(0,0,0,.08);}

        /* ── Search ── */
        .search-wrap{position:relative;flex:1;min-width:220px;}
        .search-wrap input{width:100%;padding:.6rem 1rem .6rem 2.6rem;border:1.5px solid #e0e0e0;
            border-radius:10px;font-family:'Outfit',sans-serif;font-size:.9rem;outline:none;
            transition:border-color .2s;}
        .search-wrap input:focus{border-color:#6B2D8B;}
        .search-icon{position:absolute;left:.8rem;top:50%;transform:translateY(-50%);
            color:#9e9e9e;font-size:1rem;pointer-events:none;}

        /* ── Botones export ── */
        .btn-export{padding:6px 16px;border-radius:20px;font-size:.78rem;font-weight:600;
            cursor:pointer;border:1.5px solid;transition:all .2s;font-family:'Outfit',sans-serif;
            display:inline-flex;align-items:center;gap:6px;}
        .btn-excel{border-color:#1d6f42;color:#1d6f42;background:#fff;}
        .btn-excel:hover{background:#1d6f42;color:#fff;}
        .btn-pdf{border-color:#c0392b;color:#c0392b;background:#fff;}
        .btn-pdf:hover{background:#c0392b;color:#fff;}

        /* ── Tabla ── */
        .tabla-wrap{background:#fff;border-radius:14px;box-shadow:0 2px 16px rgba(0,0,0,.06);overflow:hidden;}
        .tabla-head{background:#6B2D8B;}
        .tabla-head th{color:#fff;font-size:.75rem;font-weight:700;letter-spacing:.5px;
            text-transform:uppercase;padding:.9rem 1rem;white-space:nowrap;}
        .tabla-head th:first-child{border-radius:0;}
        tbody tr{border-bottom:1px solid #f5f5f5;transition:background .15s;}
        tbody tr:hover{background:#faf5ff;}
        tbody td{padding:.8rem 1rem;vertical-align:middle;font-size:.88rem;}

        /* ── Avatares ── */
        .af-avatar{width:36px;height:36px;border-radius:50%;display:flex;align-items:center;
            justify-content:center;font-weight:700;font-size:.8rem;color:#fff;flex-shrink:0;}
        .cap-avatar{width:28px;height:28px;border-radius:50%;display:flex;align-items:center;
            justify-content:center;font-weight:700;font-size:.68rem;color:#fff;flex-shrink:0;}

        /* ── Badges de estatus ── */
        .estatus-badge{display:inline-block;padding:4px 12px;border-radius:20px;
            font-size:.75rem;font-weight:600;white-space:nowrap;}
        .badge-nueva   {background:#fef9c3;color:#854d0e;}
        .badge-revision{background:#dbeafe;color:#1d4ed8;}
        .badge-verif   {background:#dcfce7;color:#15803d;}
        .badge-rechaz  {background:#fee2e2;color:#b91c1c;}
        .badge-default {background:#f3f4f6;color:#374151;}

        /* ── Situación Padrón status ── */
        .padron-status {
            font-size: 0.82rem;
            font-weight: 600;
        }
        .padron-localizado {
            color: #15803d;
        }
        .padron-verificacion {
            color: #b45309;
        }
        .padron-nolocalizado {
            color: #b91c1c;
        }

        /* ── Flujo de dots ── */
        .flujo-dots{display:flex;align-items:center;gap:0;}
        .flujo-dot{width:10px;height:10px;border-radius:50%;border:2px solid #d1d5db;background:#fff;flex-shrink:0;}
        .flujo-line{width:14px;height:2px;background:#d1d5db;flex-shrink:0;}
        .dot-active{border-color:#6B2D8B;background:#6B2D8B;}
        .dot-done  {border-color:#059669;background:#059669;}
        .dot-reject{border-color:#dc2626;background:#dc2626;}
        .dot-empty {border-color:#d1d5db;background:#f9fafb;}
        .line-active { background: #6B2D8B !important; }
        .line-empty { background: #d1d5db; }
        
        .flujo-dot-x {
            width: 10px;
            height: 10px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
        }

        /* ── Botones de acción ── */
        .btn-accion{width:30px;height:30px;border-radius:8px;border:none;cursor:pointer;
            display:inline-flex;align-items:center;justify-content:center;
            font-size:.85rem;transition:all .2s;}
        
        .btn-ver { background: #f3f4f6; color: #4b5563; }
        .btn-ver:hover { background: #e5e7eb; color: #1f2937; }
        .btn-aprobar { background: #dcfce7; color: #15803d; }
        .btn-aprobar:hover { background: #bbf7d0; color: #166534; }
        .btn-rechaz { background: #fee2e2; color: #b91c1c; }
        .btn-rechaz:hover { background: #fecaca; color: #991b1b; }
        .btn-cedula { background: #f3e8f8; color: #6B2D8B; }
        .btn-cedula:hover { background: #e0d0ee; color: #4a1f61; }
        .btn-editar { background: #eff6ff; color: #1d4ed8; }
        .btn-editar:hover { background: #dbeafe; color: #1e40af; }
        .btn-eliminar { background: #fee2e2; color: #b91c1c; }
        .btn-eliminar:hover { background: #fecaca; color: #991b1b; }

        /* ── Footer tabla ── */
        .tabla-footer{display:flex;justify-content:space-between;align-items:center;
            padding:.9rem 1.2rem;border-top:1px solid #f0f0f0;font-size:.82rem;color:#9e9e9e;}

        \@media(max-width:991px){#content{margin-left:0!important;}}
    </style>
</head>
<body>
HTML

require "$FindBin::Bin/_sidebar_admin.pl";

print <<"HTML";
    <div id="content">

        <!-- Page Header -->
        <div class="page-header d-flex align-items-center justify-content-between">
            <div class="d-flex align-items-center gap-2">
                <button id="sidebarToggle" class="btn btn-outline-secondary d-lg-none me-3" type="button" style="border-radius: 8px;">
                    <i class="bi bi-list"></i>
                </button>
                <div>
                    <h4><i class="bi bi-search me-2" style="color:#6B2D8B;"></i>$header_titulo</h4>
                    <p><strong>$header_sub</strong><br><span class="text-muted">$header_count_text</span></p>
                </div>
            </div>
            <div class="d-flex align-items-center gap-2">
                <button class="btn-export btn-excel" onclick="exportarExcel()">
                    <i class="bi bi-download"></i> Excel
                </button>
                <button class="btn-export btn-pdf" onclick="exportarPDF()">
                    <i class="bi bi-file-pdf"></i> PDF
                </button>
            </div>
        </div>

        $alertas_html

        <!-- Filtros + Buscador -->
        <div class="d-flex flex-wrap align-items-center justify-content-between gap-3 mb-3">
            <div class="filter-tabs">
                <button class="ftab active" data-filter="TODOS" onclick="filtrar(this,'TODOS')">
                    Todos <span class="badge-count">$cnt_total</span>
                </button>
                <button class="ftab" data-filter="NUEVA" onclick="filtrar(this,'NUEVA')">
                    Nueva afiliación <span class="badge-count">$cnt_nuevas</span>
                </button>
                <button class="ftab" data-filter="EN_REVISION" onclick="filtrar(this,'EN_REVISION')">
                    En revisión <span class="badge-count">$cnt_revision</span>
                </button>
                <button class="ftab" data-filter="VERIFICADO" onclick="filtrar(this,'VERIFICADO')">
                    Verificada <span class="badge-count">$cnt_verif</span>
                </button>
                <button class="ftab" data-filter="RECHAZADO" onclick="filtrar(this,'RECHAZADO')">
                    Rechazada <span class="badge-count">$cnt_rechaz</span>
                </button>
            </div>
            <div class="search-wrap" style="max-width:320px;">
                <i class="bi bi-search search-icon"></i>
                <input type="text" id="inputBuscar" placeholder="Nombre o clave de elector..." oninput="buscar(this.value)">
            </div>
        </div>

        <!-- Tabla -->
        <div class="tabla-wrap">
            <div class="table-responsive">
                <table id="tablaAfiliados" style="width:100%;border-collapse:collapse;">
                    <thead class="tabla-head">
                        $table_headers_html
                    </thead>
                    <tbody id="tbodyAfiliados">
                        $rows_html
                    </tbody>
                </table>
            </div>
            <div class="tabla-footer">
                <span id="footerContador">Mostrando <strong id="visibleCount">$cnt_total</strong> de $cnt_total registros</span>
                <span id="filtroActivo" style="color:#6B2D8B;font-weight:600;display:none;"></span>
            </div>
        </div>
    </div>

    <!-- MODAL DETALLE DE AFILIADO -->
    <div class="modal fade" id="modalDetalle" tabindex="-1" aria-labelledby="modalDetalleLabel" aria-hidden="true">
        <div class="modal-dialog modal-dialog-centered modal-lg">
            <div class="modal-content border-0 shadow-lg rounded-4">
                <div class="modal-header bg-light border-bottom-0 pb-0" style="padding: 1.5rem 1.5rem 0.5rem;">
                    <h5 class="modal-title fw-bold" id="modalDetalleLabel" style="color: #6B2D8B;">
                        <i class="bi bi-person-bounding-box me-2"></i>Detalle de Registro
                    </h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Cerrar"></button>
                </div>
                <div class="modal-body pt-2" style="padding: 1.5rem;">
                    <div class="row g-4">
                        <!-- Left Panel: Avatar & Basic Stats -->
                        <div class="col-md-4 text-center border-end">
                            <div id="detFotoPersona" class="mb-3 d-flex align-items-center justify-content-center mx-auto rounded-circle bg-light border" style="width:120px; height:120px; overflow:hidden;">
                                <i class="bi bi-person-fill text-muted" style="font-size: 5rem;"></i>
                            </div>
                            <h5 id="detNombre" class="fw-bold mb-1 text-dark">—</h5>
                            <p id="detMunicipioSub" class="text-muted small mb-3">—</p>
                            
                            <div class="badge-status-container d-flex flex-column gap-2 align-items-center mb-3">
                                <span id="detEstatusBadge" class="estatus-badge badge-default">—</span>
                                <span id="detPadronBadge" class="padron-status padron-verificacion">—</span>
                            </div>
                            
                            <div class="border-top pt-3 w-100 text-start">
                                <div class="mb-2">
                                    <small class="text-muted d-block">Clave de Elector</small>
                                    <strong id="detClave" class="font-monospace text-dark" style="font-size:0.88rem;">—</strong>
                                </div>
                                <div class="mb-2">
                                    <small class="text-muted d-block">CURP</small>
                                    <strong id="detCurp" class="font-monospace text-dark" style="font-size:0.88rem;">—</strong>
                                </div>
                                <div class="mb-2">
                                    <small class="text-muted d-block">OCR</small>
                                    <strong id="detOcr" class="font-monospace text-dark">—</strong>
                                </div>
                                <div>
                                    <small class="text-muted d-block">CIC</small>
                                    <strong id="detCic" class="font-monospace text-dark">—</strong>
                                </div>
                            </div>
                        </div>

                        <!-- Right Panel: Contact & Files -->
                        <div class="col-md-8">
                            <h6 class="fw-bold border-bottom pb-2 mb-3 text-secondary" style="font-size:0.9rem;">
                                <i class="bi bi-geo-alt-fill me-1"></i>Dirección Registrada
                            </h6>
                            <div class="row g-2 mb-4">
                                <div class="col-sm-8">
                                    <small class="text-muted d-block">Calle</small>
                                    <span id="detCalle" class="fw-semibold text-dark">—</span>
                                </div>
                                <div class="col-sm-4">
                                    <small class="text-muted d-block">Número</small>
                                    <span id="detNumero" class="fw-semibold text-dark">—</span>
                                </div>
                                <div class="col-sm-6">
                                    <small class="text-muted d-block">Colonia</small>
                                    <span id="detColonia" class="fw-semibold text-dark">—</span>
                                </div>
                                <div class="col-sm-6">
                                    <small class="text-muted d-block">Código Postal</small>
                                    <span id="detCp" class="fw-semibold text-dark font-monospace">—</span>
                                </div>
                                <div class="col-sm-6">
                                    <small class="text-muted d-block">Municipio / Estado</small>
                                    <span id="detMunEdo" class="fw-semibold text-dark">—</span>
                                </div>
                                <div class="col-sm-6">
                                    <small class="text-muted d-block">Fecha de Registro</small>
                                    <span id="detFechaReg" class="fw-semibold text-dark font-monospace">—</span>
                                </div>
                            </div>

                            <h6 class="fw-bold border-bottom pb-2 mb-3 text-secondary" style="font-size:0.9rem;">
                                <i class="bi bi-file-earmark-medical-fill me-1"></i>Expediente Digital
                            </h6>
                            
                            <div class="row g-2 text-center">
                                <div class="col-6 col-sm-3">
                                    <div class="card p-2 bg-light border-0 rounded-3" style="cursor:pointer;" onclick="zoomImage(document.getElementById('imgAnversoIne'))">
                                        <div id="imgAnversoIne" class="img-preview-box rounded border bg-white mb-1 d-flex align-items-center justify-content-center" style="height: 60px; overflow: hidden;">
                                            <i class="bi bi-card-image text-muted fs-4"></i>
                                        </div>
                                        <span class="d-block text-muted" style="font-size:0.68rem;">Anverso INE</span>
                                    </div>
                                </div>
                                <div class="col-6 col-sm-3">
                                    <div class="card p-2 bg-light border-0 rounded-3" style="cursor:pointer;" onclick="zoomImage(document.getElementById('imgReversoIne'))">
                                        <div id="imgReversoIne" class="img-preview-box rounded border bg-white mb-1 d-flex align-items-center justify-content-center" style="height: 60px; overflow: hidden;">
                                            <i class="bi bi-card-image text-muted fs-4"></i>
                                        </div>
                                        <span class="d-block text-muted" style="font-size:0.68rem;">Reverso INE</span>
                                    </div>
                                </div>
                                <div class="col-6 col-sm-3">
                                    <div class="card p-2 bg-light border-0 rounded-3" style="cursor:pointer;" onclick="zoomImage(document.getElementById('imgPersona'))">
                                        <div id="imgPersona" class="img-preview-box rounded border bg-white mb-1 d-flex align-items-center justify-content-center" style="height: 60px; overflow: hidden;">
                                            <i class="bi bi-person-square text-muted fs-4"></i>
                                        </div>
                                        <span class="d-block text-muted" style="font-size:0.68rem;">Foto Viva</span>
                                    </div>
                                </div>
                                <div class="col-6 col-sm-3">
                                    <div class="card p-2 bg-light border-0 rounded-3" style="cursor:pointer;" onclick="zoomImage(document.getElementById('imgFirma'))">
                                        <div id="imgFirma" class="img-preview-box rounded border bg-white mb-1 d-flex align-items-center justify-content-center" style="height: 60px; overflow: hidden;">
                                            <i class="bi bi-pen text-muted fs-4"></i>
                                        </div>
                                        <span class="d-block text-muted" style="font-size:0.68rem;">Firma</span>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="modal-footer border-top-0 pt-0" style="padding: 1.2rem 1.5rem;">
                    <button type="button" class="btn btn-outline-secondary rounded-pill px-4" data-bs-dismiss="modal">Cerrar</button>
                    <span id="detActionBtnWrap"></span>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js"></script>
    <script>
    (function(){
        'use strict';
        var filtroActual = 'TODOS';
        var busquedaActual = '';

        function actualizar() {
            var rows = document.querySelectorAll('#tbodyAfiliados tr[data-id]');
            var visible = 0;
            rows.forEach(function(tr) {
                var est   = tr.getAttribute('data-estatus') || '';
                var texto = tr.textContent.toLowerCase();
                var okFiltro  = filtroActual === 'TODOS' || est === filtroActual;
                var okBusqueda = busquedaActual === '' || texto.includes(busquedaActual.toLowerCase());
                if (okFiltro && okBusqueda) { tr.style.display = ''; visible++; }
                else { tr.style.display = 'none'; }
            });
            document.getElementById('visibleCount').textContent = visible;
            var fa = document.getElementById('filtroActivo');
            if (filtroActual !== 'TODOS') {
                fa.textContent = 'Filtro: ' + filtroActual; fa.style.display = '';
            } else { fa.style.display = 'none'; }
        }

        window.filtrar = function(btn, filtro) {
            document.querySelectorAll('.ftab').forEach(function(b){ b.classList.remove('active'); });
            btn.classList.add('active');
            filtroActual = filtro;
            actualizar();
        };

        window.buscar = function(q) { busquedaActual = q; actualizar(); };

        window.cambiarEstatus = function(id, nuevoEstatus) {
            var nombre = '';
            var row = document.querySelector('tr[data-id="' + id + '"]');
            if (row) {
                var nameEl = row.querySelector('.af-name');
                if (nameEl) nombre = nameEl.textContent.trim();
            }

            var mensajes = {
                'VERIFICADO':  { titulo:'¿Verificar afiliación?', texto:'Se marcará como <b>Verificada</b>.', icono:'question', btnColor:'#059669', btnText:'Sí, verificar' },
                'RECHAZADO':   { titulo:'¿Rechazar afiliación?',  texto:'Se marcará como <b>Rechazada</b>.',  icono:'warning',  btnColor:'#dc2626', btnText:'Sí, rechazar' },
                'EN_REVISION': { titulo:'¿Enviar a revisión?',    texto:'Se enviará para revisión del IEEQ.', icono:'question', btnColor:'#6B2D8B', btnText:'Sí, enviar' }
            };
            var cfg = mensajes[nuevoEstatus];
            if (!cfg) return;
            Swal.fire({
                title: cfg.titulo, html: cfg.texto + '<br><small class="text-muted">' + nombre + '</small>',
                icon: cfg.icono, showCancelButton: true,
                confirmButtonColor: cfg.btnColor, cancelButtonColor: '#6c757d',
                confirmButtonText: cfg.btnText, cancelButtonText: 'Cancelar'
            }).then(function(r) {
                if (!r.isConfirmed) return;
                var fd = new FormData();
                fd.append('accion','cambiar_estatus');
                fd.append('id_afiliacion', id);
                fd.append('estatus', nuevoEstatus);
                fetch('listado_afiliados.pl', { method:'POST', body:fd })
                    .then(function(r){ return r.json(); })
                    .then(function(d){
                        if (d.success) {
                            Swal.fire({ toast:true, position:'top-end', icon:'success',
                                title:'Estatus actualizado', showConfirmButton:false,
                                timer:2500, timerProgressBar:true
                            }).then(function(){ location.reload(); });
                        } else { Swal.fire({icon:'error',title:'Error',text:'No se pudo actualizar.'}); }
                    });
            });
        };

        window.eliminarAfiliacion = function(id) {
            var nombre = '';
            var row = document.querySelector('tr[data-id="' + id + '"]');
            if (row) {
                var nameEl = row.querySelector('.af-name');
                if (nameEl) nombre = nameEl.textContent.trim();
            }

            Swal.fire({
                title: '¿Eliminar afiliación?',
                text: 'Esta acción dará de baja la afiliación de ' + nombre + '. No se puede deshacer.',
                icon: 'warning',
                showCancelButton: true,
                confirmButtonColor: '#d33',
                cancelButtonColor: '#3085d6',
                confirmButtonText: 'Sí, eliminar',
                cancelButtonText: 'Cancelar'
            }).then(function(r) {
                if (!r.isConfirmed) return;
                var fd = new FormData();
                fd.append('accion', 'eliminar_afiliacion');
                fd.append('id_afiliacion', id);
                fetch('listado_afiliados.pl', { method: 'POST', body: fd })
                    .then(function(r) { return r.json(); })
                    .then(function(d) {
                        if (d.success) {
                            Swal.fire({
                                toast: true, position: 'top-end', icon: 'success',
                                title: 'Afiliación eliminada', showConfirmButton: false,
                                timer: 2000, timerProgressBar: true
                            }).then(function() { location.reload(); });
                        } else {
                            Swal.fire({ icon: 'error', title: 'Error', text: d.message || 'No se pudo eliminar.' });
                        }
                    });
            });
        };

        var modalDetalleObj = null;
        window.verDetalle = function(id) {
            try {
                if (!modalDetalleObj) {
                    if (typeof bootstrap === 'undefined') {
                        throw new Error('La librería de Bootstrap no está cargada en el navegador.');
                    }
                    modalDetalleObj = new bootstrap.Modal(document.getElementById('modalDetalle'));
                }
                
                // Clean modal fields
                document.getElementById('detNombre').textContent = 'Cargando...';
                document.getElementById('detMunicipioSub').textContent = '—';
                document.getElementById('detClave').textContent = '—';
                document.getElementById('detCurp').textContent = '—';
                document.getElementById('detOcr').textContent = '—';
                document.getElementById('detCic').textContent = '—';
                document.getElementById('detCalle').textContent = '—';
                document.getElementById('detNumero').textContent = '—';
                document.getElementById('detColonia').textContent = '—';
                document.getElementById('detCp').textContent = '—';
                document.getElementById('detMunEdo').textContent = '—';
                document.getElementById('detFechaReg').textContent = '—';
                
                document.getElementById('detEstatusBadge').className = 'estatus-badge badge-default';
                document.getElementById('detEstatusBadge').textContent = '—';
                document.getElementById('detPadronBadge').className = 'padron-status';
                document.getElementById('detPadronBadge').textContent = '—';
                
                document.getElementById('detFotoPersona').innerHTML = '<i class="bi bi-person-fill text-muted" style="font-size: 5rem;"></i>';
                document.getElementById('imgAnversoIne').innerHTML = '<i class="bi bi-card-image text-muted fs-4"></i>';
                document.getElementById('imgReversoIne').innerHTML = '<i class="bi bi-card-image text-muted fs-4"></i>';
                document.getElementById('imgPersona').innerHTML = '<i class="bi bi-person-square text-muted fs-4"></i>';
                document.getElementById('imgFirma').innerHTML = '<i class="bi bi-pen text-muted fs-4"></i>';
                document.getElementById('detActionBtnWrap').innerHTML = '';

                var fd = new FormData();
                fd.append('accion', 'obtener_detalle');
                fd.append('id_afiliacion', id);

                fetch('listado_afiliados.pl', { method: 'POST', body: fd })
                    .then(function(r) { return r.json(); })
                    .then(function(d) {
                        if (d.success) {
                            var af = d.data;
                            document.getElementById('detNombre').textContent = (af.nombre || '') + ' ' + (af.apellido_paterno || '') + ' ' + (af.apellido_materno || '');
                            document.getElementById('detMunicipioSub').textContent = af.domicilio_municipio || '—';
                            document.getElementById('detClave').textContent = af.clave_elector || '—';
                            document.getElementById('detCurp').textContent = af.curp || '—';
                            document.getElementById('detOcr').textContent = af.ocr || '—';
                            document.getElementById('detCic').textContent = af.cic || '—';
                            document.getElementById('detCalle').textContent = af.domicilio_calle || '—';
                            document.getElementById('detNumero').textContent = af.domicilio_numero || '—';
                            document.getElementById('detColonia').textContent = af.domicilio_colonia || '—';
                            document.getElementById('detCp').textContent = af.domicilio_cp || '—';
                            document.getElementById('detMunEdo').textContent = (af.domicilio_municipio || '') + ', ' + (af.domicilio_estado || '');
                            document.getElementById('detFechaReg').textContent = af.fecha || '—';

                            // Estatus badge
                            var estClasses = {
                                'NUEVA': 'badge-nueva',
                                'EN_REVISION': 'badge-revision',
                                'VERIFICADO': 'badge-verif',
                                'RECHAZADO': 'badge-rechaz'
                            };
                            var estLabels = {
                                'NUEVA': 'Nueva afiliación',
                                'EN_REVISION': 'En revisión',
                                'VERIFICADO': 'Verificado',
                                'RECHAZADO': 'Rechazada'
                            };
                            var est = af.estatus || 'NUEVA';
                            document.getElementById('detEstatusBadge').className = 'estatus-badge ' + (estClasses[est] || 'badge-default');
                            document.getElementById('detEstatusBadge').textContent = estLabels[est] || est;

                            // Padron badge
                            var sitPadron = af.situacion_padron;
                            if (!sitPadron) {
                                if (est === 'NUEVA')          { sitPadron = 'En verificación'; }
                                else if (est === 'EN_REVISION')  { sitPadron = 'Localizado'; }
                                else if (est === 'VERIFICADO')   { sitPadron = 'Localizado'; }
                                else if (est === 'RECHAZADO')    { sitPadron = 'No localizado'; }
                                else                          { sitPadron = 'En verificación'; }
                            }
                            var padronClasses = {
                                'Localizado': 'padron-localizado',
                                'En verificación': 'padron-verificacion',
                                'No localizado': 'padron-nolocalizado'
                            };
                            document.getElementById('detPadronBadge').className = 'padron-status ' + (padronClasses[sitPadron] || 'padron-verificacion');
                            document.getElementById('detPadronBadge').textContent = sitPadron;

                            // Photos
                            if (af.foto_persona) {
                                document.getElementById('detFotoPersona').innerHTML = '<img src="' + af.foto_persona + '" style="width:100%; height:100%; object-fit:cover;">';
                                document.getElementById('imgPersona').innerHTML = '<img src="' + af.foto_persona + '" style="width:100%; height:100%; object-fit:cover;">';
                            }
                            if (af.foto_anverso_ine) {
                                document.getElementById('imgAnversoIne').innerHTML = '<img src="' + af.foto_anverso_ine + '" style="width:100%; height:100%; object-fit:cover;">';
                            }
                            if (af.foto_reverso_ine) {
                                document.getElementById('imgReversoIne').innerHTML = '<img src="' + af.foto_reverso_ine + '" style="width:100%; height:100%; object-fit:cover;">';
                            }
                            if (af.firma) {
                                document.getElementById('imgFirma').innerHTML = '<img src="' + af.firma + '" style="width:100%; height:100%; object-fit:contain; background:#fff;">';
                            }

                            // Action Buttons in Modal
                            var actionsHtml = '';
                            var userRol = '$rol';
                            if (userRol === 'administrador' || userRol === 'funcionario') {
                                if (est === 'EN_REVISION') {
                                    actionsHtml += '<button class="btn btn-success rounded-pill px-3 me-2" onclick="modalAction(' + id + ', \\\'VERIFICADO\\\')"><i class="bi bi-check-lg me-1"></i>Verificar</button>';
                                    actionsHtml += '<button class="btn btn-danger rounded-pill px-3" onclick="modalAction(' + id + ', \\\'RECHAZADO\\\')"><i class="bi bi-x-lg me-1"></i>Rechazar</button>';
                                }
                            }
                            document.getElementById('detActionBtnWrap').innerHTML = actionsHtml;

                            modalDetalleObj.show();
                        } else {
                            Swal.fire({ icon: 'error', title: 'Error', text: d.message || 'No se pudo cargar el detalle.' });
                        }
                    })
                    .catch(function(err) {
                        Swal.fire({ icon: 'error', title: 'Error de Red', text: err.message || 'Error al cargar detalle.' });
                    });
            } catch (err) {
                Swal.fire({ icon: 'error', title: 'Error de Javascript', text: err.message });
            }
        };

        window.modalAction = function(id, nuevoEstatus) {
            modalDetalleObj.hide();
            window.cambiarEstatus(id, nuevoEstatus);
        };

        window.zoomImage = function(div) {
            var img = div.querySelector('img');
            if (img) {
                Swal.fire({
                    imageUrl: img.src,
                    imageAlt: 'Vista ampliada',
                    showConfirmButton: false,
                    showCloseButton: true,
                    customClass: { popup: 'rounded-4 overflow-hidden border-0 shadow-lg' }
                });
            }
        };

        window.exportarExcel = function() {
            var rows = document.querySelectorAll('#tbodyAfiliados tr[data-id]');
            var data = [['#','Nombre','Clave Elector','Municipio','Fecha','Estatus']];
            var i = 0;
            rows.forEach(function(tr){
                if(tr.style.display === 'none') return;
                var tds = tr.querySelectorAll('td');
                i++;
                data.push([i, tds[1].querySelector('.af-name')?.textContent||'',
                    tds[2].textContent.trim(), tds[3].textContent.trim(),
                    tds[4].textContent.trim(), tds[5].textContent.trim()]);
            });
            var csv = data.map(function(r){ return r.map(function(c){ return '"'+String(c).replace(/"/g,'""')+'"'; }).join(','); }).join('\\n');
            var blob = new Blob([csv],{type:'text/csv;charset=utf-8;'});
            var a = document.createElement('a'); a.href=URL.createObjectURL(blob);
            a.download='afiliados_ieeq.csv'; a.click();
        };

        window.exportarPDF = function() {
            var element = document.createElement('div');
            element.style.padding = '20px';
            element.style.fontFamily = "'Outfit', sans-serif";

            var title = document.createElement('h3');
            title.textContent = 'Reporte de Afiliados - IEEQ';
            title.style.color = '#6B2D8B';
            title.style.marginBottom = '20px';
            element.appendChild(title);

            var table = document.getElementById('tablaAfiliados').cloneNode(true);
            var ths = table.querySelectorAll('thead th');
            if (ths.length > 0) {
                ths[ths.length - 1].remove();
            }
            table.querySelectorAll('tbody tr').forEach(function(tr) {
                if (tr.style.display === 'none') {
                    tr.remove();
                    return;
                }
                var tds = tr.querySelectorAll('td');
                if (tds.length > 0) {
                    tds[tds.length - 1].remove();
                }
            });

            table.style.width = '100%';
            table.style.borderCollapse = 'collapse';
            table.querySelectorAll('th, td').forEach(function(el) {
                el.style.border = '1px solid #ddd';
                el.style.padding = '8px';
                el.style.fontSize = '12px';
            });

            element.appendChild(table);

            var opt = {
                margin:       10,
                filename:     'listado_afiliados.pdf',
                image:        { type: 'jpeg', quality: 0.98 },
                html2canvas:  { scale: 2 },
                jsPDF:        { unit: 'mm', format: 'a4', orientation: 'landscape' }
            };

            Swal.fire({
                title: 'Generando PDF...',
                text: 'Por favor espera.',
                allowOutsideClick: false,
                didOpen: function() { Swal.showLoading(); }
            });

            html2pdf().set(opt).from(element).save().then(function() {
                Swal.close();
            }).catch(function(err) {
                Swal.fire({ icon: 'error', title: 'Error', text: 'No se pudo generar el reporte PDF.' });
            });
        };

        window.addEventListener('DOMContentLoaded', function() {
            var urlParams = new URLSearchParams(window.location.search);
            var f = urlParams.get('filtro');
            if (f) {
                var btn = document.querySelector('.ftab[data-filter="' + f + '"]');
                if (btn) {
                    window.filtrar(btn, f);
                }
            }
        });
    })();
    </script>
</body>
</html>
HTML
