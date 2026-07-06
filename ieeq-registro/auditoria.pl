#!C:\xampp\perl\bin\perl.exe
use strict;
use warnings;
use utf8;
use CGI;
use CGI::Session;
use FindBin;
use Encode qw(decode_utf8);
require "$FindBin::Bin/db.pl";

binmode(STDOUT, ":utf8");

my $cgi     = CGI->new;
my $session = CGI::Session->new(undef, $cgi, {Directory => "$FindBin::Bin/.sesiones"});

my $rol             = $session->param('rol')             || '';
my $nombre_completo = $session->param('nombre_completo') || '';

if ($rol ne 'administrador' && $rol ne 'funcionario') {
    print $cgi->redirect(-uri => (!$rol ? 'login.pl' : 'dashboard.pl'));
    exit;
}

# ══════════════════════════════════════════════════════════════
# CONSULTAS
# ══════════════════════════════════════════════════════════════

# KPI
my @kpi = execute_query_list("
    SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN accion IN ('APROBACION','VALIDACION')         THEN 1 ELSE 0 END) AS aprobaciones,
        SUM(CASE WHEN accion IN ('RECHAZO','OBSERVACION')           THEN 1 ELSE 0 END) AS rechazos,
        SUM(CASE WHEN accion IN ('EDICION','MODIFICACION')          THEN 1 ELSE 0 END) AS ediciones,
        SUM(CASE WHEN accion IN ('CONSULTA','CONSULTA_REPORTE')     THEN 1 ELSE 0 END) AS consultas,
        SUM(CASE WHEN accion = 'LOGIN'                              THEN 1 ELSE 0 END) AS logins,
        SUM(CASE WHEN accion = 'ELIMINACION'                        THEN 1 ELSE 0 END) AS eliminaciones,
        SUM(CASE WHEN accion = 'GENERACION_CEDULA'                  THEN 1 ELSE 0 END) AS cedulas
    FROM bitacora
");
my $cnt_total       = $kpi[0]->{total}        || 0;
my $cnt_aprobaciones= $kpi[0]->{aprobaciones} || 0;
my $cnt_rechazos    = $kpi[0]->{rechazos}     || 0;
my $cnt_ediciones   = $kpi[0]->{ediciones}    || 0;
my $cnt_consultas   = $kpi[0]->{consultas}    || 0;
my $cnt_logins      = $kpi[0]->{logins}       || 0;
my $cnt_eliminaciones = $kpi[0]->{eliminaciones} || 0;
my $cnt_cedulas     = $kpi[0]->{cedulas}      || 0;

# Registros completos con ROL
my @logs = execute_query_list("
    SELECT
        b.fecha,
        b.accion,
        b.modulo AS tabla_afectada,
        b.id_registro_afectado AS id_registro,
        b.detalles AS detalle,
        COALESCE(CONCAT(u.nombre,' ',u.apellido_paterno),'Sistema') AS nombre_completo,
        COALESCE(u.correo_electronico,'sistema')                     AS username,
        COALESCE(u.tipo_usuario,'SISTEMA')                           AS tipo_usuario
    FROM bitacora b
    LEFT JOIN usuarios u ON b.id_usuario = u.id_usuario
    ORDER BY b.fecha DESC
");

# ══════════════════════════════════════════════════════════════
# HELPERS HTML
# ══════════════════════════════════════════════════════════════
sub badge_accion {
    my ($accion) = @_;
    my %map = (
        'LOGIN'           => ['#6B2D8B','bi-box-arrow-in-right'],
        'LOGOUT'          => ['#6c757d','bi-box-arrow-right'],
        'REGISTRO'        => ['#0891b2','bi-plus-circle-fill'],
        'EDICION'         => ['#d97706','bi-pencil-fill'],
        'MODIFICACION'    => ['#d97706','bi-pencil-fill'],
        'APROBACION'      => ['#16a34a','bi-check-circle-fill'],
        'VALIDACION'      => ['#16a34a','bi-check-circle-fill'],
        'RECHAZO'         => ['#dc2626','bi-x-circle-fill'],
        'OBSERVACION'     => ['#dc2626','bi-x-circle-fill'],
        'ELIMINACION'     => ['#ef4444','bi-trash-fill'],
        'GENERACION_CEDULA'=>['#059669','bi-award-fill'],
        'CONSULTA'        => ['#2563eb','bi-eye-fill'],
        'CONSULTA_REPORTE'=> ['#2563eb','bi-eye-fill'],
        'CREACION_USUARIO'=> ['#6f42c1','bi-person-plus-fill'],
        'PERMISO_ASIGNADO'=> ['#343a40','bi-shield-lock-fill'],
    );
    my $d = $map{$accion} // ['#9e9e9e','bi-dot'];
    return sprintf(
        '<span class="badge-accion" style="background:%s;">'
        . '<i class="bi %s me-1"></i>%s</span>',
        $d->[0], $d->[1], $accion
    );
}

sub badge_rol {
    my ($tipo) = @_;
    my %rmap = (
        'ADMINISTRADOR'    => ['#f3e8f8','#6B2D8B','Administrador'],
        'FUNCIONARIO_IEEQ' => ['#ede9fe','#4f46e5','Funcionario IEEQ'],
        'AUXILIAR'         => ['#fef3c7','#92400e','Auxiliar'],
        'SISTEMA'          => ['#f3f4f6','#6b7280','Sistema'],
    );
    my $d = $rmap{$tipo} // ['#f3f4f6','#6b7280', $tipo];
    return sprintf(
        '<span class="badge-rol" style="background:%s;color:%s;">%s</span>',
        $d->[0], $d->[1], $d->[2]
    );
}

sub mapear_modulo {
    my ($m) = @_;
    return 'Registro de Afiliaciones'   if ($m||'') =~ /afiliacion/i;
    return 'Listado de Afiliados'       if ($m||'') =~ /listado/i;
    return 'Gestión de Usuarios'        if ($m||'') =~ /usuario/i;
    return 'Gestión de Permisos'        if ($m||'') =~ /permiso/i;
    return 'Cédulas'                    if ($m||'') =~ /cedula/i;
    return 'Sistema'                    if !$m || $m eq 'sistema';
    return ucfirst($m);
}

# ── Construir filas ──
my $table_rows = '';
for my $row (@logs) {
    my $fecha    = $row->{fecha}          || '';
    my $nombre   = $row->{nombre_completo}|| 'Sistema';
    my $username = $row->{username}       || 'sistema';
    my $accion   = $row->{accion}         || '';
    my $tipo_usr = $row->{tipo_usuario}   || 'SISTEMA';
    my $modulo   = mapear_modulo($row->{tabla_afectada});
    my $registro = $row->{id_registro}    || '—';
    my $detalle  = $row->{detalle}        || '';

    $detalle  =~ s/&/&amp;/g; $detalle =~ s/</&lt;/g; $detalle =~ s/>/&gt;/g;
    $registro =~ s/&/&amp;/g;

    my $badge_a = badge_accion($accion);
    my $badge_r = badge_rol($tipo_usr);

    # Avatar
    my @pn = split /\s+/, $nombre;
    my $ini = '';
    $ini .= uc(substr($pn[0],0,1)) if @pn > 0;
    $ini .= uc(substr($pn[1],0,1)) if @pn > 1;
    $ini ||= 'S';
    my @ac = ('#6B2D8B','#2563eb','#059669','#dc2626','#d97706','#0dcaf0');
    my $color = $ac[length($nombre) % 6];

    # Acción normalizada para filtro JS
    my $accion_norm = $accion;
    $accion_norm = 'APROBACION' if $accion eq 'VALIDACION';
    $accion_norm = 'RECHAZO'    if $accion eq 'OBSERVACION';
    $accion_norm = 'EDICION'    if $accion eq 'MODIFICACION';
    $accion_norm = 'CONSULTA'   if $accion eq 'CONSULTA_REPORTE';

    $table_rows .= sprintf(
        '<tr data-accion="%s" data-usuario="%s" data-fecha="%s">
            <td class="align-middle text-muted" style="font-size:.88rem;white-space:nowrap;">%s</td>
            <td class="align-middle">
                <div class="d-flex align-items-center gap-2">
                    <div class="av-circle" style="background:%s;">%s</div>
                    <div>
                        <div class="fw-semibold text-dark" style="font-size:.88rem;">%s</div>
                        <div class="text-muted" style="font-size:.72rem;">%s</div>
                    </div>
                </div>
            </td>
            <td class="align-middle">%s</td>
            <td class="align-middle">%s</td>
            <td class="align-middle text-secondary" style="font-size:.85rem;">%s</td>
            <td class="align-middle fw-semibold text-muted" style="font-size:.82rem;">%s</td>
            <td class="align-middle text-secondary" style="font-size:.82rem;max-width:260px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title="%s">%s</td>
        </tr>',
        $accion_norm, lc($nombre), substr($fecha,0,10),
        $fecha,
        $color, $ini, $nombre, $username,
        $badge_r,
        $badge_a,
        $modulo,
        ($registro eq '—' ? '—' : "ID: $registro"),
        $detalle, $detalle
    );
}

my $pagina_activa = 'BITACORA';

print $cgi->header(
    -type         => 'text/html',
    -charset      => 'utf-8',
    -expires      => 'now',
    -Cache_Control=> 'no-store, no-cache, must-revalidate, max-age=0',
    -Pragma       => 'no-cache'
);

print <<"HTML";
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bitácora de Auditoría - IEEQ</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons\@1.11.3/font/bootstrap-icons.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght\@300;400;600;700&display=swap" rel="stylesheet">
    <style>
        *{box-sizing:border-box;}
        body{font-family:'Outfit',sans-serif;background:#f5f5f8;overflow-x:hidden;margin:0;}
        #content{margin-left:260px;min-height:100vh;padding:2rem;transition:margin-left .3s;}

        /* ── Top header ── */
        .top-header{background:#fff;padding:1rem 1.5rem;border-radius:14px;
            box-shadow:0 2px 12px rgba(0,0,0,.05);margin-bottom:1.5rem;
            display:flex;justify-content:space-between;align-items:center;}
        .top-header h4{margin:0;font-weight:700;color:#1a1a2e;font-size:1.3rem;}
        .top-header p{margin:0;color:#6c757d;font-size:.85rem;}

        /* ── KPI cards ── */
        .kpi-row{display:flex;flex-wrap:wrap;gap:12px;margin-bottom:1.5rem;}
        .kpi-card{background:#fff;border-radius:12px;padding:.9rem 1.2rem;flex:1;min-width:100px;
            box-shadow:0 2px 10px rgba(0,0,0,.04);border-left:4px solid transparent;}
        .kpi-card .kpi-val{font-size:1.6rem;font-weight:800;font-family:monospace;}
        .kpi-card .kpi-lbl{font-size:.72rem;color:#9e9e9e;font-weight:600;text-transform:uppercase;letter-spacing:.4px;}

        /* ── Leyenda de colores ── */
        .legend-row{background:#fff;border-radius:12px;padding:.75rem 1.2rem;
            margin-bottom:1.2rem;box-shadow:0 2px 10px rgba(0,0,0,.04);}
        .legend-title{font-size:.72rem;font-weight:700;color:#9e9e9e;text-transform:uppercase;
            letter-spacing:.5px;margin-bottom:.5rem;}
        .legend-pills{display:flex;flex-wrap:wrap;gap:8px;}
        .legend-pill{display:inline-flex;align-items:center;gap:5px;padding:4px 12px;
            border-radius:20px;font-size:.72rem;font-weight:600;color:#fff;}

        /* ── Filtros ── */
        .filters-card{background:#fff;border-radius:12px;padding:1rem 1.2rem;
            margin-bottom:1.2rem;box-shadow:0 2px 10px rgba(0,0,0,.04);}
        .filters-title{font-size:.78rem;font-weight:700;color:#9e9e9e;
            text-transform:uppercase;letter-spacing:.5px;margin-bottom:.75rem;
            display:flex;align-items:center;gap:6px;}
        .filters-grid{display:flex;flex-wrap:wrap;gap:10px;align-items:flex-end;}
        .filter-group{display:flex;flex-direction:column;gap:3px;}
        .filter-group label{font-size:.72rem;font-weight:600;color:#6c757d;}
        .filter-group input, .filter-group select{
            padding:.4rem .75rem;border:1.5px solid #e0e0e0;border-radius:8px;
            font-family:'Outfit',sans-serif;font-size:.82rem;outline:none;
            transition:border-color .2s;background:#fff;}
        .filter-group input:focus, .filter-group select:focus{border-color:#6B2D8B;}
        .btn-filter{padding:.42rem 1.2rem;border-radius:8px;border:none;cursor:pointer;
            font-family:'Outfit',sans-serif;font-size:.82rem;font-weight:600;transition:all .2s;}
        .btn-aplicar{background:#6B2D8B;color:#fff;}
        .btn-aplicar:hover{background:#4a1f61;}
        .btn-limpiar{background:#f0f0f0;color:#6c757d;}
        .btn-limpiar:hover{background:#e0e0e0;}

        /* ── Tabla card ── */
        .table-card{background:#fff;border-radius:14px;box-shadow:0 2px 16px rgba(0,0,0,.06);overflow:hidden;}
        .tabla-head{background:#6B2D8B;}
        .tabla-head th{color:#fff;font-size:.72rem;font-weight:700;letter-spacing:.5px;
            text-transform:uppercase;padding:.85rem 1rem;white-space:nowrap;}
        tbody tr{border-bottom:1px solid #f5f5f5;transition:background .15s;}
        tbody tr:hover{background:#faf5ff;}
        tbody td{padding:.75rem 1rem;vertical-align:middle;}

        /* ── Avatar ── */
        .av-circle{width:32px;height:32px;border-radius:50%;display:flex;align-items:center;
            justify-content:center;font-weight:700;font-size:.78rem;color:#fff;flex-shrink:0;}

        /* ── Badges ── */
        .badge-accion{display:inline-flex;align-items:center;padding:4px 10px;border-radius:20px;
            font-size:.72rem;font-weight:700;color:#fff;white-space:nowrap;}
        .badge-rol{display:inline-block;padding:3px 10px;border-radius:20px;
            font-size:.72rem;font-weight:600;white-space:nowrap;}

        /* ── Footer tabla ── */
        .tabla-footer{display:flex;justify-content:space-between;align-items:center;
            padding:.8rem 1.2rem;border-top:1px solid #f0f0f0;font-size:.8rem;color:#9e9e9e;}

        /* ── Búsqueda ── */
        .search-wrap{position:relative;min-width:200px;}
        .search-wrap input{width:100%;padding:.4rem 1rem .4rem 2.4rem;border:1.5px solid #e0e0e0;
            border-radius:8px;font-family:'Outfit',sans-serif;font-size:.82rem;outline:none;
            transition:border-color .2s;}
        .search-wrap input:focus{border-color:#6B2D8B;}
        .search-icon{position:absolute;left:.7rem;top:50%;transform:translateY(-50%);
            color:#bdbdbd;font-size:.9rem;pointer-events:none;}

        \@media(max-width:991px){
            #content{margin-left:0!important;}
            .kpi-card{min-width:130px;}
        }
    </style>
</head>
<body>
HTML

require "$FindBin::Bin/_sidebar_admin.pl";

print <<"HTML";
    <div id="content">

        <!-- Top header -->
        <div class="top-header">
            <div>
                <h4><i class="bi bi-journal-text me-2" style="color:#6B2D8B;"></i>Bitácora de Auditoría</h4>
                <p>Registro completo e inmutable de todas las operaciones realizadas en el sistema (RF-06).</p>
            </div>
            <div class="text-muted small d-none d-md-block">Instituto Electoral del Estado de Querétaro</div>
        </div>

        <!-- KPI cards -->
        <div class="kpi-row">
            <div class="kpi-card" style="border-left-color:#6B2D8B;">
                <div class="kpi-val" style="color:#6B2D8B;">$cnt_total</div>
                <div class="kpi-lbl">Total Eventos</div>
            </div>
            <div class="kpi-card" style="border-left-color:#16a34a;">
                <div class="kpi-val" style="color:#16a34a;">$cnt_aprobaciones</div>
                <div class="kpi-lbl">Aprobaciones</div>
            </div>
            <div class="kpi-card" style="border-left-color:#dc2626;">
                <div class="kpi-val" style="color:#dc2626;">$cnt_rechazos</div>
                <div class="kpi-lbl">Rechazos</div>
            </div>
            <div class="kpi-card" style="border-left-color:#d97706;">
                <div class="kpi-val" style="color:#d97706;">$cnt_ediciones</div>
                <div class="kpi-lbl">Ediciones</div>
            </div>
            <div class="kpi-card" style="border-left-color:#ef4444;">
                <div class="kpi-val" style="color:#ef4444;">$cnt_eliminaciones</div>
                <div class="kpi-lbl">Eliminaciones</div>
            </div>
            <div class="kpi-card" style="border-left-color:#059669;">
                <div class="kpi-val" style="color:#059669;">$cnt_cedulas</div>
                <div class="kpi-lbl">Cédulas</div>
            </div>
            <div class="kpi-card" style="border-left-color:#198754;">
                <div class="kpi-val" style="color:#198754;">$cnt_logins</div>
                <div class="kpi-lbl">Inicios Sesión</div>
            </div>
        </div>

        <!-- Leyenda de colores -->
        <div class="legend-row">
            <div class="legend-title"><i class="bi bi-palette me-1"></i>Código de colores</div>
            <div class="legend-pills">
                <span class="legend-pill" style="background:#6B2D8B;"><i class="bi bi-box-arrow-in-right"></i>LOGIN</span>
                <span class="legend-pill" style="background:#6c757d;"><i class="bi bi-box-arrow-right"></i>LOGOUT</span>
                <span class="legend-pill" style="background:#0891b2;"><i class="bi bi-plus-circle-fill"></i>REGISTRO</span>
                <span class="legend-pill" style="background:#d97706;"><i class="bi bi-pencil-fill"></i>EDICIÓN</span>
                <span class="legend-pill" style="background:#ef4444;"><i class="bi bi-trash-fill"></i>ELIMINACIÓN</span>
                <span class="legend-pill" style="background:#059669;"><i class="bi bi-award-fill"></i>APROBACIÓN / CÉDULA</span>
                <span class="legend-pill" style="background:#dc2626;"><i class="bi bi-x-circle-fill"></i>RECHAZO</span>
            </div>
        </div>

        <!-- Filtros de búsqueda -->
        <div class="filters-card">
            <div class="filters-title"><i class="bi bi-funnel"></i>Filtros de búsqueda</div>
            <div class="filters-grid">
                <div class="filter-group">
                    <label for="fDesde">Desde</label>
                    <input type="date" id="fDesde" placeholder="dd/mm/aaaa">
                </div>
                <div class="filter-group">
                    <label for="fHasta">Hasta</label>
                    <input type="date" id="fHasta" placeholder="dd/mm/aaaa">
                </div>
                <div class="filter-group">
                    <label for="fAccion">Tipo de acción</label>
                    <select id="fAccion">
                        <option value="">Todas las acciones</option>
                        <option>LOGIN</option>
                        <option>LOGOUT</option>
                        <option>REGISTRO</option>
                        <option>EDICION</option>
                        <option>APROBACION</option>
                        <option>RECHAZO</option>
                        <option>ELIMINACION</option>
                        <option>GENERACION_CEDULA</option>
                        <option>CONSULTA</option>
                        <option>CREACION_USUARIO</option>
                        <option>PERMISO_ASIGNADO</option>
                    </select>
                </div>
                <div class="filter-group">
                    <label for="fUsuario">Usuario</label>
                    <div class="search-wrap">
                        <i class="bi bi-search search-icon"></i>
                        <input type="text" id="fUsuario" placeholder="Buscar usuario...">
                    </div>
                </div>
                <div class="filter-group" style="flex-direction:row;gap:6px;">
                    <button class="btn-filter btn-aplicar" onclick="aplicarFiltros()">Aplicar</button>
                    <button class="btn-filter btn-limpiar" onclick="limpiarFiltros()">Limpiar</button>
                </div>
            </div>
        </div>

        <!-- Tabla -->
        <div class="table-card">
            <div class="table-responsive">
                <table id="tablaAuditoria" style="width:100%;border-collapse:collapse;">
                    <thead class="tabla-head">
                        <tr>
                            <th>FECHA / HORA</th>
                            <th>USUARIO</th>
                            <th>ROL</th>
                            <th>ACCIÓN</th>
                            <th>MÓDULO</th>
                            <th>REGISTRO AFECTADO</th>
                            <th>DETALLES</th>
                        </tr>
                    </thead>
                    <tbody id="tbodyAuditoria">
                        $table_rows
                    </tbody>
                </table>
            </div>
            <div class="tabla-footer">
                <span>Mostrando <strong id="visibleCount">$cnt_total</strong> de $cnt_total registros</span>
                <span id="filtroInfo" style="color:#6B2D8B;font-weight:600;"></span>
            </div>
        </div>

    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    <script>
    (function(){
        'use strict';

        var allRows = Array.from(document.querySelectorAll('#tbodyAuditoria tr[data-accion]'));

        function actualizarContador() {
            var vis = allRows.filter(function(r){ return r.style.display !== 'none'; }).length;
            document.getElementById('visibleCount').textContent = vis;
        }

        window.aplicarFiltros = function() {
            var desde   = document.getElementById('fDesde').value;
            var hasta   = document.getElementById('fHasta').value;
            var accion  = document.getElementById('fAccion').value.toUpperCase();
            var usuario = document.getElementById('fUsuario').value.toLowerCase().trim();

            allRows.forEach(function(tr) {
                var trAccion  = (tr.getAttribute('data-accion') || '').toUpperCase();
                var trUsuario = (tr.getAttribute('data-usuario') || '').toLowerCase();
                var trFecha   = (tr.getAttribute('data-fecha') || '');   // YYYY-MM-DD

                var okAccion  = !accion  || trAccion  === accion;
                var okUsuario = !usuario || trUsuario.includes(usuario);
                var okDesde   = !desde   || trFecha >= desde;
                var okHasta   = !hasta   || trFecha <= hasta;

                tr.style.display = (okAccion && okUsuario && okDesde && okHasta) ? '' : 'none';
            });

            actualizarContador();
            var fi = document.getElementById('filtroInfo');
            fi.textContent = (accion || usuario || desde || hasta) ? 'Filtros activos' : '';
        };

        window.limpiarFiltros = function() {
            document.getElementById('fDesde').value   = '';
            document.getElementById('fHasta').value   = '';
            document.getElementById('fAccion').value  = '';
            document.getElementById('fUsuario').value = '';
            allRows.forEach(function(tr){ tr.style.display = ''; });
            actualizarContador();
            document.getElementById('filtroInfo').textContent = '';
        };

        /* Aplicar en tiempo real al escribir usuario */
        document.getElementById('fUsuario').addEventListener('input', aplicarFiltros);

    })();
    </script>
</body>
</html>
HTML
