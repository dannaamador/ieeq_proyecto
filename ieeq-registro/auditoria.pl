#!C:\xampp\perl\bin\perl.exe
use strict;
use warnings;
use utf8;
use CGI;
use CGI::Session;
use FindBin;
use Encode qw(decode_utf8);
require "$FindBin::Bin/db.pl";

# Configurar salida UTF-8
binmode(STDOUT, ":utf8");

my $cgi = CGI->new;
my $session = CGI::Session->new(undef, $cgi, {Directory => "$FindBin::Bin/.sesiones"});

my $rol = $session->param('rol') || '';
my $nombre_completo = $session->param('nombre_completo') || '';

if ($rol ne 'administrador') {
    if (!$rol) {
        print $cgi->redirect(-uri => 'login.pl');
    } else {
        print $cgi->redirect(-uri => 'dashboard.pl');
    }
    exit;
}

# ==========================================
# CONSULTAS DE BASE DE DATOS
# ==========================================

# 1. Obtener conteos para las tarjetas KPI
my @kpi_data = execute_query_list("
    SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN accion IN ('APROBACION', 'VALIDACION') THEN 1 ELSE 0 END) as aprobaciones,
        SUM(CASE WHEN accion IN ('RECHAZO', 'OBSERVACION') THEN 1 ELSE 0 END) as rechazos,
        SUM(CASE WHEN accion IN ('EDICION', 'MODIFICACION') THEN 1 ELSE 0 END) as ediciones,
        SUM(CASE WHEN accion IN ('CONSULTA', 'CONSULTA_REPORTE') THEN 1 ELSE 0 END) as consultas,
        SUM(CASE WHEN accion = 'LOGIN' THEN 1 ELSE 0 END) as logins
    FROM bitacora
");

my $count_total = $kpi_data[0]->{total} || 0;
my $count_aprobaciones = $kpi_data[0]->{aprobaciones} || 0;
my $count_rechazos = $kpi_data[0]->{rechazos} || 0;
my $count_ediciones = $kpi_data[0]->{ediciones} || 0;
my $count_consultas = $kpi_data[0]->{consultas} || 0;
my $count_logins = $kpi_data[0]->{logins} || 0;

# 2. Obtener la lista completa de la bitácora
my @log_rows = execute_query_list("
    SELECT 
        b.fecha,
        b.accion,
        b.tabla_afectada,
        b.id_registro,
        b.detalle,
        COALESCE(u.nombre_completo, 'Sistema') as nombre_completo,
        COALESCE(u.username, 'sistema') as username
    FROM bitacora b
    LEFT JOIN usuarios u ON b.id_usuario = u.id_usuario
    ORDER BY b.fecha DESC
");

# ==========================================
# RENDERIZADO DE BADGES Y TABLA
# ==========================================
sub get_badge_html {
    my ($accion) = @_;
    if ($accion eq 'APROBACION' || $accion eq 'VALIDACION') {
        return '<span class="badge d-inline-flex align-items-center gap-1" style="background-color: #20c997; color: white; font-size: 0.75rem; border-radius: 20px; padding: 6px 12px; font-weight: 600;"><i class="bi bi-check-circle-fill"></i> APROBACION</span>';
    } elsif ($accion eq 'RECHAZO' || $accion eq 'OBSERVACION') {
        return '<span class="badge d-inline-flex align-items-center gap-1" style="background-color: #dc3545; color: white; font-size: 0.75rem; border-radius: 20px; padding: 6px 12px; font-weight: 600;"><i class="bi bi-x-circle-fill"></i> RECHAZO</span>';
    } elsif ($accion eq 'CONSULTA' || $accion eq 'CONSULTA_REPORTE') {
        return '<span class="badge d-inline-flex align-items-center gap-1" style="background-color: #0d6efd; color: white; font-size: 0.75rem; border-radius: 20px; padding: 6px 12px; font-weight: 600;"><i class="bi bi-eye-fill"></i> CONSULTA</span>';
    } elsif ($accion eq 'LOGIN') {
        return '<span class="badge d-inline-flex align-items-center gap-1" style="background-color: #6B2D8B; color: white; font-size: 0.75rem; border-radius: 20px; padding: 6px 12px; font-weight: 600;"><i class="bi bi-box-arrow-in-right"></i> LOGIN</span>';
    } elsif ($accion eq 'LOGOUT') {
        return '<span class="badge d-inline-flex align-items-center gap-1" style="background-color: #6c757d; color: white; font-size: 0.75rem; border-radius: 20px; padding: 6px 12px; font-weight: 600;"><i class="bi bi-box-arrow-right"></i> LOGOUT</span>';
    } elsif ($accion eq 'EDICION' || $accion eq 'MODIFICACION') {
        return '<span class="badge d-inline-flex align-items-center gap-1" style="background-color: #fd7e14; color: white; font-size: 0.75rem; border-radius: 20px; padding: 6px 12px; font-weight: 600;"><i class="bi bi-pencil-fill"></i> EDICION</span>';
    } elsif ($accion eq 'REGISTRO') {
        return '<span class="badge d-inline-flex align-items-center gap-1" style="background-color: #0dcaf0; color: black; font-size: 0.75rem; border-radius: 20px; padding: 6px 12px; font-weight: 600;"><i class="bi bi-plus-circle-fill"></i> REGISTRO</span>';
    } elsif ($accion eq 'CREACION_USUARIO') {
        return '<span class="badge d-inline-flex align-items-center gap-1" style="background-color: #6f42c1; color: white; font-size: 0.75rem; border-radius: 20px; padding: 6px 12px; font-weight: 600;"><i class="bi bi-person-plus-fill"></i> CREACION_USUARIO</span>';
    } elsif ($accion eq 'PERMISO_ASIGNADO') {
        return '<span class="badge d-inline-flex align-items-center gap-1" style="background-color: #343a40; color: white; font-size: 0.75rem; border-radius: 20px; padding: 6px 12px; font-weight: 600;"><i class="bi bi-shield-lock-fill"></i> PERMISO_ASIGNADO</span>';
    } else {
        return sprintf('<span class="badge bg-light text-dark border d-inline-flex align-items-center gap-1" style="font-size: 0.75rem; border-radius: 20px; padding: 6px 12px; font-weight: 600;">%s</span>', $accion);
    }
}

sub get_mapped_accion {
    my ($accion) = @_;
    if ($accion eq 'VALIDACION') { return 'APROBACION'; }
    if ($accion eq 'OBSERVACION') { return 'RECHAZO'; }
    if ($accion eq 'CONSULTA_REPORTE') { return 'CONSULTA'; }
    if ($accion eq 'MODIFICACION') { return 'EDICION'; }
    return $accion;
}

my $table_rows = '';
for my $row (@log_rows) {
    my $fecha = $row->{fecha} || '';
    my $username = $row->{username} || 'sistema';
    my $nombre = $row->{nombre_completo} || 'Sistema';
    my $accion = $row->{accion} || '';
    my $modulo = $row->{tabla_afectada} || '-';
    
    # Mapeo de nombres de módulos más amigables
    if ($modulo eq 'personas') { $modulo = 'Verificación de Afiliaciones'; }
    elsif ($modulo eq 'usuarios') { $modulo = 'Gestión de Usuarios'; }
    elsif ($modulo eq 'permisos_usuario') { $modulo = 'Gestión de Permisos'; }
    elsif ($modulo eq 'observaciones') { $modulo = 'Observaciones'; }
    elsif ($modulo eq 'sistema' || $modulo eq '') { $modulo = 'Sistema'; }
    
    my $registro = $row->{id_registro} || '-';
    if ($registro ne '-') {
        if ($row->{detalle} =~ /(INE-\d+)/) {
            $registro = $1;
        } else {
            $registro = "ID: $registro";
        }
    }
    
    my $detalle = $row->{detalle} || '';
    $detalle =~ s/&/&amp;/g;
    $detalle =~ s/</&lt;/g;
    $detalle =~ s/>/&gt;/g;
    
    my $badge = get_badge_html($accion);
    my $mapped_action = get_mapped_accion($accion);
    
    # Generar iniciales del avatar
    my $words = $nombre;
    $words =~ s/^\s+|\s+$//g;
    my @parts = split /\s+/, $words;
    my $initials = 'S';
    if (@parts > 0) {
        $initials = uc(substr($parts[0], 0, 1));
        if (@parts > 1) {
            $initials .= uc(substr($parts[1], 0, 1));
        }
    }
    
    my @colors = ('#6B2D8B', '#0d6efd', '#198754', '#dc3545', '#fd7e14', '#0dcaf0');
    my $color = $colors[ length($nombre || '') % 6 ];
    
    $table_rows .= sprintf(
        '<tr>
            <td class="align-middle text-muted" style="font-size: 0.9rem;">%s</td>
            <td class="align-middle">
                <div class="d-flex align-items-center">
                    <div class="avatar-initials-table rounded-circle text-white d-flex align-items-center justify-content-center fw-bold me-2" style="width: 32px; height: 32px; font-size: 0.8rem; background-color: %s; border: 1px solid rgba(255,255,255,0.1); flex-shrink: 0;">
                        %s
                    </div>
                    <div>
                        <div class="fw-semibold text-dark" style="font-size: 0.9rem;">%s</div>
                        <div class="text-muted" style="font-size: 0.75rem;">%s</div>
                    </div>
                </div>
            </td>
            <td class="align-middle" data-search="%s" data-filter="%s">%s</td>
            <td class="align-middle" style="font-size: 0.9rem;">%s</td>
            <td class="align-middle fw-semibold text-muted" style="font-size: 0.85rem;">%s</td>
            <td class="align-middle text-secondary" style="font-size: 0.85rem; max-width: 300px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;" title="%s">%s</td>
        </tr>',
        $fecha, $color, $initials, $nombre, $username, $mapped_action, $mapped_action, $badge, $modulo, $registro, $detalle, $detalle
    );
}

# Iniciales del Administrador Logueado para la barra lateral
my $words_admin = $nombre_completo;
$words_admin =~ s/^\s+|\s+$//g;
my @parts_admin = split /\s+/, $words_admin;
my $initials_admin = 'U';
if (@parts_admin > 0) {
    $initials_admin = uc(substr($parts_admin[0], 0, 1));
    if (@parts_admin > 1) {
        $initials_admin .= uc(substr($parts_admin[1], 0, 1));
    }
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
    <title>Auditoría - IEEQ</title>
    
    <!-- CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons\@1.11.1/font/bootstrap-icons.css">
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght\@300;400;600;700&display=swap" rel="stylesheet">
    <link href="https://cdn.datatables.net/1.13.6/css/dataTables.bootstrap5.min.css" rel="stylesheet">
    
    <style>
        body { font-family: 'Outfit', sans-serif; background-color: #f8f9fa; overflow-x: hidden; }
        
        /* Sidebar Styling */
        #sidebar {
            width: 280px; height: 100vh; position: fixed; left: 0; top: 0;
            background: linear-gradient(180deg, #6B2D8B 0%, #4a1f61 100%);
            color: white; z-index: 1000; display: flex; flex-direction: column;
        }
        .sidebar-header { padding: 2rem 1.5rem; border-bottom: 1px solid rgba(255,255,255,0.1); }
        .sidebar-header h3 { font-weight: 700; margin: 0; letter-spacing: 1px; }
        .sidebar-header p { margin: 0; font-size: 0.85rem; opacity: 0.8; }
        .nav-link { color: rgba(255,255,255,0.8); padding: 0.8rem 1.5rem; margin: 0.2rem 1rem; border-radius: 8px; transition: all 0.3s; }
        .nav-link:hover { background: rgba(255,255,255,0.1); color: white; transform: translateX(5px); }
        .nav-link.active { background: rgba(255,255,255,0.2); color: white; font-weight: 600; box-shadow: 0 4px 10px rgba(0,0,0,0.1); }
        .user-section { padding: 1.5rem; background: rgba(0,0,0,0.15); margin-top: auto; border-top: 1px solid rgba(255,255,255,0.05); }
        .user-name { font-weight: 600; font-size: 0.9rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; margin-bottom: 2px; }
        .user-role { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 1px; color: #d1a3e6; }

        /* Main Content Styling */
        #content { margin-left: 280px; min-height: 100vh; padding: 2rem; transition: all 0.3s; }
        .top-header {
            background: #ffffff; padding: 1rem 2rem; border-radius: 12px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.03); margin-bottom: 2rem;
            display: flex; justify-content: space-between; align-items: center;
        }
        
        .card-ieeq { border: none; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); background-color: #ffffff; }
        
        /* Custom Table design */
        .table-hover tbody tr:hover { background-color: #fcf9fe; }
        .table thead th { font-weight: 600; color: #495057; border-bottom: 2px solid #dee2e6; }
        
        /* DataTables Custom styling */
        .dataTables_wrapper .dataTables_paginate .paginate_button { padding: 0.3rem 0.6rem; margin-left: 2px; border-radius: 6px; }
        .dataTables_wrapper .dataTables_info { font-size: 0.85rem; color: #6c757d; }
        .pagination { justify-content: flex-end; margin-top: 1rem; }
        
        /* Form inputs customization */
        .form-control:focus, .form-select:focus {
            border-color: #6B2D8B;
            box-shadow: 0 0 0 0.25rem rgba(107, 45, 139, 0.15);
        }
        
        .text-purple { color: #6B2D8B !important; }
        
        .mobile-overlay {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100vw;
            height: 100vh;
            background: rgba(0,0,0,0.5);
            z-index: 999;
        }
        
        /* Responsive adjustments */
        \@media (max-width: 991px) {
            #sidebar { left: -280px; transition: all 0.3s; }
            #sidebar.active { left: 0; }
            #content { margin-left: 0; padding: 1rem; }
            .top-header { flex-direction: column; align-items: flex-start; gap: 1rem; }
            .mobile-overlay.active { display: block; }
        }
    </style>
</head>
<body>
    <div class="mobile-overlay"></div>

    <!-- Sidebar -->
    <nav id="sidebar">
        <div class="sidebar-header">
            <h3>IEEQ</h3><p>Sistema de Registro</p>
        </div>
        <ul class="nav nav-pills flex-column mt-3 mb-auto">
            <li class="nav-item">
                <a href="dashboard.pl" class="nav-link"><i class="bi bi-house-door me-2"></i>Inicio</a>
            </li>
            <li class="nav-item">
                <a href="gestion_usuarios.pl" class="nav-link"><i class="bi bi-people me-2"></i>Gestión de Usuarios</a>
            </li>
            <li class="nav-item">
                <a href="gestion_permisos.pl" class="nav-link"><i class="bi bi-shield-lock me-2"></i>Gestión de Permisos</a>
            </li>
            <li class="nav-item">
                <a href="auditoria.pl" class="nav-link active"><i class="bi bi-journal-text me-2"></i>Auditoría</a>
            </li>
        </ul>
        <div class="user-section">
            <div class="d-flex align-items-center mb-3">
                <div class="flex-shrink-0">
                    <div class="bg-white text-purple rounded-circle d-flex align-items-center justify-content-center fw-bold" style="width: 40px; height: 40px; color: #6B2D8B; font-size: 1rem;">
                        $initials_admin
                    </div>
                </div>
                <div class="flex-grow-1 ms-3" style="min-width: 0;">
                    <div class="user-name" title="$nombre_completo">$nombre_completo</div>
                    <div class="user-role">$rol</div>
                </div>
            </div>
            <a href="dashboard.pl?logout=1" class="btn btn-outline-light btn-sm w-100 d-flex justify-content-center align-items-center">
                <i class="bi bi-box-arrow-right me-2"></i>Cerrar Sesión
            </a>
        </div>
    </nav>

    <!-- Main Content -->
    <div id="content">
        <!-- Top header bar -->
        <div class="top-header">
            <div class="d-flex align-items-center">
                <button class="btn btn-light d-lg-none me-3 shadow-sm" id="sidebarToggle">
                    <i class="bi bi-list fs-4"></i>
                </button>
                <div>
                    <h4 class="mb-0 text-dark fw-bold">Auditoría</h4>
                    <p class="text-muted mb-0 small">Historial completo de acciones realizadas en el sistema</p>
                </div>
            </div>
            <div class="text-muted d-none d-md-block fs-6">
                Instituto Electoral del Estado de Querétaro
            </div>
        </div>

        <h5 class="fw-bold mb-3 text-dark">Registro de Auditoría</h5>

        <!-- KPI summary row -->
        <div class="row row-cols-2 row-cols-md-3 row-cols-xl-6 g-3 mb-4">
            <!-- Total Eventos -->
            <div class="col">
                <div class="card card-ieeq text-center p-3 border-start border-4" style="border-start-color: #6B2D8B !important;">
                    <h2 class="fw-bold mb-1 text-purple">$count_total</h2>
                    <div class="text-muted small fw-semibold">Total Eventos</div>
                </div>
            </div>
            <!-- Aprobaciones -->
            <div class="col">
                <div class="card card-ieeq text-center p-3 border-start border-4" style="border-start-color: #20c997 !important;">
                    <h2 class="fw-bold mb-1" style="color: #20c997;">$count_aprobaciones</h2>
                    <div class="text-muted small fw-semibold">Aprobaciones</div>
                </div>
            </div>
            <!-- Rechazos -->
            <div class="col">
                <div class="card card-ieeq text-center p-3 border-start border-4" style="border-start-color: #dc3545 !important;">
                    <h2 class="fw-bold mb-1" style="color: #dc3545;">$count_rechazos</h2>
                    <div class="text-muted small fw-semibold">Rechazos</div>
                </div>
            </div>
            <!-- Ediciones -->
            <div class="col">
                <div class="card card-ieeq text-center p-3 border-start border-4" style="border-start-color: #fd7e14 !important;">
                    <h2 class="fw-bold mb-1" style="color: #fd7e14;">$count_ediciones</h2>
                    <div class="text-muted small fw-semibold">Ediciones</div>
                </div>
            </div>
            <!-- Consultas -->
            <div class="col">
                <div class="card card-ieeq text-center p-3 border-start border-4" style="border-start-color: #0d6efd !important;">
                    <h2 class="fw-bold mb-1" style="color: #0d6efd;">$count_consultas</h2>
                    <div class="text-muted small fw-semibold">Consultas</div>
                </div>
            </div>
            <!-- Inicios de sesión -->
            <div class="col">
                <div class="card card-ieeq text-center p-3 border-start border-4" style="border-start-color: #198754 !important;">
                    <h2 class="fw-bold mb-1" style="color: #198754;">$count_logins</h2>
                    <div class="text-muted small fw-semibold">Inicios Sesión</div>
                </div>
            </div>
        </div>

        <!-- Table Card -->
        <div class="card card-ieeq">
            <div class="card-body p-4">
                
                <!-- Filters Controls Header -->
                <div class="row g-3 align-items-center mb-4">
                    <!-- Custom search -->
                    <div class="col-md-7 col-lg-8">
                        <div class="input-group shadow-sm" style="border-radius: 20px;">
                            <span class="input-group-text bg-white border-end-0" style="border: 1px solid #ced4da; border-radius: 20px 0 0 20px;">
                                <i class="bi bi-search" style="color: #6c757d;"></i>
                            </span>
                            <input type="text" class="form-control border-start-0" id="searchAuditoria" placeholder="Buscar por usuario, registro o detalles..." style="border: 1px solid #ced4da; border-radius: 0 20px 20px 0; padding: 0.6rem 1.2rem;" autocomplete="off">
                        </div>
                    </div>
                    
                    <!-- Action select filter -->
                    <div class="col-md-5 col-lg-4">
                        <div class="d-flex align-items-center justify-content-md-end gap-2">
                            <label for="filterAccion" class="text-muted small text-nowrap mb-0 fw-semibold">Filtrar por Acción</label>
                            <select class="form-select shadow-sm border" id="filterAccion" style="border-radius: 20px; padding: 0.6rem 1.2rem; min-width: 170px; border-color: #ced4da;">
                                <option value="Todas" selected>Todas</option>
                                <option value="LOGIN">LOGIN</option>
                                <option value="LOGOUT">LOGOUT</option>
                                <option value="REGISTRO">REGISTRO</option>
                                <option value="EDICION">EDICION</option>
                                <option value="APROBACION">APROBACION</option>
                                <option value="RECHAZO">RECHAZO</option>
                                <option value="CONSULTA">CONSULTA</option>
                                <option value="PERMISO_ASIGNADO">PERMISO_ASIGNADO</option>
                                <option value="CREACION_USUARIO">CREACION_USUARIO</option>
                            </select>
                        </div>
                    </div>
                </div>

                <!-- Table element -->
                <div class="table-responsive">
                    <table class="table table-hover align-middle mb-0" id="tablaAuditoria" style="width: 100%;">
                        <thead>
                            <tr class="table-light border-bottom border-2">
                                <th class="py-3 ps-3 text-muted text-uppercase fw-bold" style="font-size: 0.8rem; width: 15%;">Fecha/Hora</th>
                                <th class="py-3 text-muted text-uppercase fw-bold" style="font-size: 0.8rem; width: 15%;">Usuario</th>
                                <th class="py-3 text-muted text-uppercase fw-bold" style="font-size: 0.8rem; width: 15%;">Acción</th>
                                <th class="py-3 text-muted text-uppercase fw-bold" style="font-size: 0.8rem; width: 20%;">Módulo</th>
                                <th class="py-3 text-muted text-uppercase fw-bold" style="font-size: 0.8rem; width: 15%;">Registro Afectado</th>
                                <th class="py-3 text-muted text-uppercase fw-bold" style="font-size: 0.8rem; width: 20%;">Detalles</th>
                            </tr>
                        </thead>
                        <tbody>
                            $table_rows
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>

    <!-- Scripts -->
    <script src="https://code.jquery.com/jquery-3.7.0.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.6/js/dataTables.bootstrap5.min.js"></script>
    
    <script>
        \$(document).ready(function() {
            // Inicializar DataTable
            const table = \$('#tablaAuditoria').DataTable({
                "language": {
                    "url": "https://cdn.datatables.net/plug-ins/1.13.6/i18n/es-ES.json"
                },
                "pageLength": 10,
                "order": [[0, "desc"]],
                "dom": '<"row"<"col-sm-12"tr>><"row mt-3"<"col-sm-12 col-md-5"i><"col-sm-12 col-md-7"p>>',
                "columnDefs": [
                    { "orderable": false, "targets": [4, 5] } // Deshabilitar ordenación para Registro y Detalles
                ]
            });

            // Buscador personalizado en tiempo real
            \$('#searchAuditoria').on('keyup input', function() {
                table.search(this.value).draw();
            });

            // Filtro por acción personalizado
            \$('#filterAccion').on('change', function() {
                const val = \$(this).val();
                if (val === 'Todas') {
                    table.column(2).search('').draw();
                } else {
                    // Búsqueda exacta de regex sobre la columna de Acción (Columna índice 2)
                    table.column(2).search('^' + val + '\$', true, false).draw();
                }
            });

            // Toggle lateral en móvil
            $('#sidebarToggle, .mobile-overlay').on('click', function() {
                $('#sidebar, .mobile-overlay').toggleClass('active');
            });
        });
    </script>
</body>
</html>
HTML
