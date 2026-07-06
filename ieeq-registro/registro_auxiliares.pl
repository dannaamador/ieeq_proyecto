#!C:\xampp\perl\bin\perl.exe
use strict;
use warnings;
use utf8;
use CGI;
use CGI::Session;
use JSON;
use FindBin;
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

if ($rol ne 'integrante_organizacion') {
    print $cgi->redirect(-uri => 'dashboard.pl');
    exit;
}

# ==========================================
# PROCESAR ACCIÓN AJAX POST
# ==========================================
my $accion = $cgi->param('accion') || '';

if ($cgi->request_method() eq 'POST' && $accion eq 'guardar') {
    my $nombre = $cgi->param('nombre') || '';
    my $apellido_paterno = $cgi->param('apellido_paterno') || '';
    my $apellido_materno = $cgi->param('apellido_materno') || '';
    my $credencial_ine = $cgi->param('credencial_ine') || '';
    my $curp = uc($cgi->param('curp') || '');
    my $telefono = $cgi->param('telefono') || '';
    my $correo_electronico = $cgi->param('correo_electronico') || '';
    my $cargo = $cgi->param('cargo') || '';
    my $seccion_electoral = $cgi->param('seccion_electoral') || '';
    my $municipio = $cgi->param('municipio') || '';

    # Validar campos obligatorios
    if (!$nombre || !$apellido_paterno || !$apellido_materno || !$credencial_ine || !$curp || !$telefono || !$correo_electronico || !$cargo || !$seccion_electoral || !$municipio) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'Por favor, complete todos los campos del formulario.' });
        exit;
    }

    # Validar formato CURP
    if ($curp !~ /^[A-Z]{4}\d{6}[HM][A-Z]{5}[A-Z0-9]\d$/) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'El formato del CURP es incorrecto.' });
        exit;
    }

    # Validar duplicados de CURP
    my @dup_curp = execute_query_list("SELECT id_auxiliar FROM auxiliares WHERE curp = ?", $curp);
    if (@dup_curp) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'El CURP ya se encuentra registrado para otro auxiliar.' });
        exit;
    }

    # Validar duplicados de Credencial
    my @dup_cred = execute_query_list("SELECT id_auxiliar FROM auxiliares WHERE credencial_ine = ?", $credencial_ine);
    if (@dup_cred) {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'La Credencial INE ya se encuentra registrada para otro auxiliar.' });
        exit;
    }

    # Insertar auxiliar
    my $sql = "INSERT INTO auxiliares (nombre, apellido_paterno, apellido_materno, credencial_ine, curp, telefono, correo_electronico, cargo, seccion_electoral, municipio, id_registrador, estatus) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'PENDIENTE')";
    
    my $ok = execute_query_write($sql, $nombre, $apellido_paterno, $apellido_materno, $credencial_ine, $curp, $telefono, $correo_electronico, $cargo, $seccion_electoral, $municipio, $id_usuario);

    if ($ok) {
        # Loguear acción en bitácora
        my @last_ids = execute_query_list("SELECT LAST_INSERT_ID() as id");
        my $id_auxiliar = $last_ids[0]->{id} || 0;
        my $ip = $cgi->remote_host() || '127.0.0.1';
        my $detalle = "Registro de auxiliar ($cargo) de: $nombre $apellido_paterno ($curp)";
        
        execute_query_write(
            "INSERT INTO bitacora (id_usuario, accion, tabla_afectada, id_registro, detalle, ip_origen) VALUES (?, 'REGISTRO', 'auxiliares', ?, ?, ?)",
            $id_usuario, $id_auxiliar, $detalle, $ip
        );

        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 1, message => 'Auxiliar registrado exitosamente.' });
        exit;
    } else {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'Error al guardar el registro en la base de datos.' });
        exit;
    }
}

# ==========================================
# OBTENER AUXILIARES RECIENTES E INFORMACIÓN
# ==========================================

# 1. Lista de los últimos 5 auxiliares de hoy
my @auxiliares_recientes = execute_query_list("
    SELECT 
        CONCAT(nombre, ' ', apellido_paterno) as nombre_completo,
        cargo,
        municipio,
        estatus 
    FROM auxiliares 
    WHERE id_registrador = ? AND DATE(fecha_registro) = CURDATE()
    ORDER BY fecha_registro DESC 
    LIMIT 5
");

# 2. Total de auxiliares del día de hoy
my @totales_hoy = execute_query_list("
    SELECT COUNT(*) as total 
    FROM auxiliares 
    WHERE id_registrador = ? AND DATE(fecha_registro) = CURDATE()
");
my $total_hoy = $totales_hoy[0]->{total} || 0;

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

# Generar filas de la tabla de auxiliares recientes
my $filas_recientes_html = '';
if (@auxiliares_recientes) {
    for my $r (@auxiliares_recientes) {
        my $cargo_text = $r->{cargo} || '';
        my $badge_color = '#6B2D8B'; # Default Representante
        my $cargo_short = 'Representante';
        
        if ($cargo_text eq 'Promotor') {
            $badge_color = '#0d6efd';
            $cargo_short = 'Promotor';
        } elsif ($cargo_text eq 'Coordinador') {
            $badge_color = '#198754';
            $cargo_short = 'Coordinador';
        }
        
        $filas_recientes_html .= sprintf(
            '<tr>
                <td class="align-middle">
                    <div class="fw-semibold text-dark text-truncate" style="max-width: 150px; font-size: 0.85rem;" title="%s">%s</div>
                    <div class="text-muted" style="font-size: 0.7rem;">%s</div>
                </td>
                <td class="align-middle text-end">
                    <span class="badge" style="background-color: %s; color: white; font-size: 0.7rem; border-radius: 6px; padding: 4px 8px; font-weight: 600;">%s</span>
                </td>
            </tr>',
            $r->{nombre_completo}, $r->{nombre_completo}, $r->{municipio}, $badge_color, $cargo_short
        );
    }
} else {
    $filas_recientes_html = '<tr><td colspan="2" class="text-center text-muted py-4 small"><i class="bi bi-inbox d-block fs-3 mb-2 opacity-50"></i>Sin auxiliares registrados hoy</td></tr>';
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
    <title>Registro de Auxiliares - IEEQ</title>
    
    <!-- CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons\@1.11.1/font/bootstrap-icons.css">
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght\@300;400;600;700&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/sweetalert2\@11"></script>
    
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

        /* Main Content Styling */
        #content { margin-left: 280px; min-height: 100vh; padding: 2rem; transition: all 0.3s; }
        .top-header {
            background: #ffffff; padding: 1rem 2rem; border-radius: 12px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.03); margin-bottom: 2rem;
            display: flex; justify-content: space-between; align-items: center;
        }
        
        /* Cards */
        .card-ieeq { border: none; border-radius: 16px; box-shadow: 0 4px 20px rgba(0,0,0,0.05); background-color: #ffffff; }
        .card-title-container { display: flex; align-items: center; gap: 1rem; border-bottom: 1px solid #f1f3f5; padding-bottom: 1.25rem; margin-bottom: 1.5rem; }
        .card-icon-wrapper { width: 44px; height: 44px; border-radius: 12px; background-color: #f3e8f8; color: #6B2D8B; display: flex; align-items: center; justify-content: center; }
        
        /* Stepper Styles */
        .stepper-container { display: flex; justify-content: space-between; align-items: center; position: relative; margin-bottom: 2.5rem; }
        .stepper-container::before { content: ''; position: absolute; top: 20px; left: 0; right: 0; height: 3px; background-color: #f1f3f5; z-index: 1; }
        .stepper-progress { position: absolute; top: 20px; left: 0; height: 3px; background-color: #6B2D8B; z-index: 1; transition: width 0.3s ease; width: 0%; }
        .step-item { position: relative; z-index: 2; display: flex; flex-direction: column; align-items: center; text-align: center; flex: 1; }
        .step-circle { width: 40px; height: 40px; border-radius: 50%; background-color: #ffffff; border: 3px solid #f1f3f5; display: flex; align-items: center; justify-content: center; font-weight: 600; color: #adb5bd; transition: all 0.3s ease; font-size: 0.9rem; }
        .step-label { margin-top: 0.5rem; font-size: 0.8rem; font-weight: 600; color: #adb5bd; transition: all 0.3s ease; }
        
        .step-item.active .step-circle { background-color: #ffffff; border-color: #6B2D8B; color: #6B2D8B; box-shadow: 0 0 0 0.25rem rgba(107, 45, 139, 0.15); }
        .step-item.active .step-label { color: #6B2D8B; }
        .step-item.completed .step-circle { background-color: #198754; border-color: #198754; color: #ffffff; }
        .step-item.completed .step-label { color: #198754; }

        /* Form Controls styling */
        .form-control, .form-select { border-radius: 12px; padding: 0.75rem 1rem; border: 1.5px solid #dee2e6; background-color: #ffffff; font-size: 0.95rem; transition: all 0.2s; }
        .form-control:focus, .form-select:focus { border-color: #6B2D8B; box-shadow: 0 0 0 0.25rem rgba(107, 45, 139, 0.15); background-color: #ffffff; }
        .input-group-text { border-radius: 12px 0 0 12px; border: 1.5px solid #dee2e6; background-color: #ffffff; }
        .input-group-text + .form-control { border-radius: 0 12px 12px 0; }
        .form-label { font-weight: 600; color: #495057; margin-bottom: 0.5rem; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.5px; }
        
        /* Summary Grid */
        .summary-title { font-size: 0.8rem; font-weight: 700; color: #8e44ad; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 0.25rem; }
        .summary-value { font-size: 0.95rem; color: #212529; font-weight: 500; margin-bottom: 1.25rem; }
        
        /* Buttons */
        .btn-purple { background-color: #6B2D8B; color: white; border: none; }
        .btn-purple:hover { background-color: #4a1f61; color: white; transform: translateY(-1px); box-shadow: 0 4px 10px rgba(107, 45, 139, 0.25); }
        .btn-purple:active { transform: translateY(0); }
        
        .btn-blue-badge { background-color: #03a9f4; color: white; border: none; }
        .btn-blue-badge:hover { background-color: #0288d1; color: white; }

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
                <a href="registro_afiliados.pl" class="nav-link"><i class="bi bi-person-plus me-2"></i>Registro de Afiliaciones</a>
            </li>
            <li class="nav-item">
                <a href="registro_auxiliares.pl" class="nav-link active"><i class="bi bi-person-vcard me-2"></i>Registro de Auxiliares</a>
            </li>
            <li class="nav-item">
                <a href="consulta_registros.pl" class="nav-link"><i class="bi bi-search me-2"></i>Consulta de Registros</a>
            </li>
        </ul>
        <div class="user-section">
            <div class="d-flex align-items-center mb-3">
                <div class="flex-shrink-0">
                    <div class="bg-white text-purple rounded-circle d-flex align-items-center justify-content-center fw-bold" style="width: 40px; height: 40px; color: #6B2D8B; font-size: 1rem;">
                        $initials_user
                    </div>
                </div>
                <div class="flex-grow-1 ms-3" style="min-width: 0;">
                    <div class="user-name" title="$nombre_completo">$nombre_completo</div>
                    <div class="user-role" style="font-size: 0.7rem; color: #d1a3e6;" title="$username">$username</div>
                </div>
            </div>
            <a href="login.pl?logout=1" class="btn btn-outline-light btn-sm w-100 d-flex justify-content-center align-items-center">
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
                    <h4 class="mb-0 text-dark fw-bold">Registro de Auxiliares</h4>
                    <p class="text-muted mb-0 small">Sistema de registro de auxiliares del partido político</p>
                </div>
            </div>
            <div class="text-muted d-none d-md-block fs-6">
                Instituto Electoral del Estado de Querétaro
            </div>
        </div>

        <div class="row">
            <!-- Form Card (Left Column - 8 cols) -->
            <div class="col-lg-8 mb-4">
                <div class="card card-ieeq p-4">
                    <div class="card-title-container">
                        <div class="card-icon-wrapper">
                            <i class="bi bi-person-vcard fs-4"></i>
                        </div>
                        <div>
                            <h5 class="fw-bold mb-0 text-dark">Nuevo Registro de Auxiliar</h5>
                            <p class="text-muted mb-0 small">Complete el flujo para registrar y asignar un nuevo auxiliar electoral</p>
                        </div>
                    </div>

                    <!-- Custom Stepper -->
                    <div class="stepper-container">
                        <div class="stepper-progress"></div>
                        <div class="step-item active" id="step-1-item">
                            <div class="step-circle" id="step-1-circle">1</div>
                            <div class="step-label">Datos Personales</div>
                        </div>
                        <div class="step-item" id="step-2-item">
                            <div class="step-circle" id="step-2-circle">2</div>
                            <div class="step-label">Datos de Contacto</div>
                        </div>
                        <div class="step-item" id="step-3-item">
                            <div class="step-circle" id="step-3-circle">3</div>
                            <div class="step-label">Asignación</div>
                        </div>
                        <div class="step-item" id="step-4-item">
                            <div class="step-circle" id="step-4-circle">4</div>
                            <div class="step-label">Confirmación</div>
                        </div>
                    </div>

                    <!-- Form Content Wizard -->
                    <form id="wizardForm" autocomplete="off" novalidate>
                        
                        <!-- STEP 1: DATOS PERSONALES -->
                        <div class="wizard-step" id="step-1-content">
                            <div class="row">
                                <div class="col-md-12 mb-3">
                                    <label class="form-label" for="nombre">Nombre(s) *</label>
                                    <input type="text" class="form-control" id="nombre" name="nombre" required placeholder="Ej. Roberto">
                                </div>
                            </div>
                            <div class="row">
                                <div class="col-md-6 mb-3">
                                    <label class="form-label" for="apellido_paterno">Apellido Paterno *</label>
                                    <input type="text" class="form-control" id="apellido_paterno" name="apellido_paterno" required placeholder="Ej. Gómez">
                                </div>
                                <div class="col-md-6 mb-3">
                                    <label class="form-label" for="apellido_materno">Apellido Materno *</label>
                                    <input type="text" class="form-control" id="apellido_materno" name="apellido_materno" required placeholder="Ej. Pérez">
                                </div>
                            </div>
                            <div class="row">
                                <div class="col-md-6 mb-3">
                                    <label class="form-label" for="credencial_ine">Credencial INE *</label>
                                    <div class="input-group">
                                        <span class="input-group-text bg-white"><i class="bi bi-card-image text-muted"></i></span>
                                        <input type="text" class="form-control" id="credencial_ine" name="credencial_ine" required placeholder="Clave de Elector (OCR / ID)" maxlength="18">
                                    </div>
                                </div>
                                <div class="col-md-6 mb-3">
                                    <label class="form-label" for="curp">CURP *</label>
                                    <div class="input-group">
                                        <span class="input-group-text bg-white"><i class="bi bi-lock-fill text-muted"></i></span>
                                        <input type="text" class="form-control" id="curp" name="curp" required placeholder="18 caracteres" maxlength="18" style="text-transform: uppercase;">
                                    </div>
                                </div>
                            </div>
                        </div>

                        <!-- STEP 2: DATOS DE CONTACTO -->
                        <div class="wizard-step d-none" id="step-2-content">
                            <div class="row">
                                <div class="col-md-6 mb-3">
                                    <label class="form-label" for="telefono">Teléfono de Contacto *</label>
                                    <div class="input-group">
                                        <span class="input-group-text bg-white"><i class="bi bi-telephone text-muted"></i></span>
                                        <input type="tel" class="form-control" id="telefono" name="telefono" required placeholder="10 dígitos" maxlength="10">
                                    </div>
                                </div>
                                <div class="col-md-6 mb-3">
                                    <label class="form-label" for="correo_electronico">Correo Electrónico *</label>
                                    <div class="input-group">
                                        <span class="input-group-text bg-white"><i class="bi bi-envelope text-muted"></i></span>
                                        <input type="email" class="form-control" id="correo_electronico" name="correo_electronico" required placeholder="Ej. roberto.gomez\@organizacion.mx">
                                    </div>
                                </div>
                            </div>
                        </div>

                        <!-- STEP 3: ASIGNACIÓN -->
                        <div class="wizard-step d-none" id="step-3-content">
                            <div class="row">
                                <div class="col-md-12 mb-3">
                                    <label class="form-label" for="cargo">Cargo Asignado *</label>
                                    <select class="form-select" id="cargo" name="cargo" required>
                                        <option value="">Seleccione un cargo...</option>
                                        <option value="Representante de Casilla">Representante de Casilla</option>
                                        <option value="Promotor">Promotor</option>
                                        <option value="Coordinador">Coordinador</option>
                                    </select>
                                </div>
                            </div>
                            <div class="row">
                                <div class="col-md-6 mb-3">
                                    <label class="form-label" for="seccion_electoral">Sección Electoral *</label>
                                    <input type="text" class="form-control" id="seccion_electoral" name="seccion_electoral" required placeholder="Ej. 0422" maxlength="4">
                                </div>
                                <div class="col-md-6 mb-3">
                                    <label class="form-label" for="municipio">Municipio Asignado *</label>
                                    <input type="text" class="form-control" id="municipio" name="municipio" required placeholder="Ej. Querétaro">
                                </div>
                            </div>
                        </div>

                        <!-- STEP 4: CONFIRMACIÓN -->
                        <div class="wizard-step d-none" id="step-4-content">
                            <div class="alert alert-success d-flex align-items-center gap-2 mb-4">
                                <i class="bi bi-shield-check fs-5"></i>
                                <div class="fw-semibold">Revise los datos del auxiliar antes de proceder con el registro definitivo.</div>
                            </div>
                            
                            <div class="row p-2">
                                <div class="col-md-6">
                                    <div class="summary-title">Nombre del Auxiliar</div>
                                    <div class="summary-value" id="sum-nombre">-</div>
                                    
                                    <div class="summary-title">Documentos</div>
                                    <div class="summary-value">
                                        <strong>INE:</strong> <span id="sum-ine">-</span><br>
                                        <strong>CURP:</strong> <span id="sum-curp">-</span>
                                    </div>
                                </div>
                                <div class="col-md-6">
                                    <div class="summary-title">Contacto</div>
                                    <div class="summary-value">
                                        <strong>Teléfono:</strong> <span id="sum-telefono">-</span><br>
                                        <strong>Correo:</strong> <span id="sum-correo">-</span>
                                    </div>

                                    <div class="summary-title">Asignación Electoral</div>
                                    <div class="summary-value">
                                        <strong>Cargo:</strong> <span id="sum-cargo">-</span><br>
                                        <strong>Sección:</strong> <span id="sum-seccion">-</span><br>
                                        <strong>Municipio:</strong> <span id="sum-municipio">-</span>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <!-- Wizard Footer Action Buttons -->
                        <div class="d-flex justify-content-between border-top pt-4 mt-4">
                            <button type="button" class="btn btn-outline-secondary rounded-pill px-4 invisible" id="btnAnterior">
                                <i class="bi bi-chevron-left me-2"></i>Anterior
                            </button>
                            <button type="button" class="btn btn-outline-danger rounded-pill px-4" id="btnLimpiar">
                                <i class="bi bi-x-lg me-2"></i>Limpiar
                            </button>
                            <button type="button" class="btn btn-purple rounded-pill px-4 fw-semibold" id="btnSiguiente">
                                Siguiente<i class="bi bi-chevron-right ms-2"></i>
                            </button>
                            <button type="submit" class="btn btn-success rounded-pill px-4 fw-bold d-none" id="btnConfirmar">
                                <i class="bi bi-check-circle-fill me-2"></i>Confirmar y Registrar
                            </button>
                        </div>

                    </form>
                </div>
            </div>

            <!-- Recent Auxiliares Panel (Right Column - 4 cols) -->
            <div class="col-lg-4 mb-4">
                <div class="card card-ieeq p-4 h-100 d-flex flex-column">
                    <h5 class="fw-bold text-dark mb-3">Auxiliares Recientes</h5>
                    <p class="text-muted small mb-4">Últimos auxiliares registrados y asignados hoy.</p>
                    
                    <div class="table-responsive flex-grow-1">
                        <table class="table table-hover align-middle" style="font-size: 0.9rem;">
                            <thead>
                                <tr class="table-light">
                                    <th style="width: 60%;">Nombre</th>
                                    <th class="text-end" style="width: 40%;">Cargo</th>
                                </tr>
                            </thead>
                            <tbody>
                                $filas_recientes_html
                            </tbody>
                        </table>
                    </div>

                    <!-- Total count indicator -->
                    <div class="mt-4 pt-3 border-top text-center">
                        <button class="btn btn-blue-badge rounded-pill px-4 w-100 py-2 fw-semibold" style="cursor: default; background-color: #00bcd4;">
                            Total hoy: $total_hoy auxiliares
                        </button>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Scripts -->
    <script src="https://code.jquery.com/jquery-3.7.0.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    
    <script>
        \$(document).ready(function() {
            let currentStep = 1;

            // Toggle lateral en móvil
            \$('#sidebarToggle, .mobile-overlay').on('click', function() {
                \$('#sidebar, .mobile-overlay').toggleClass('active');
            });

            // Función para cambiar de paso
            function goToStep(step) {
                // Validar paso actual antes de avanzar
                if (step > currentStep && !validateStep(currentStep)) {
                    return;
                }

                // Ocultar paso actual, mostrar nuevo paso
                \$(`#step-\${currentStep}-content`).addClass('d-none');
                \$(`#step-\${step}-content`).removeClass('d-none');

                // Actualizar clases del Stepper
                for (let i = 1; i <= 4; i++) {
                    const stepCircle = \$(`#step-\${i}-circle`);
                    const stepItem = \$(`#step-\${i}-item`);

                    if (i < step) {
                        stepItem.removeClass('active').addClass('completed');
                        stepCircle.html('<i class="bi bi-check-lg"></i>');
                    } else if (i === step) {
                        stepItem.removeClass('completed').addClass('active');
                        stepCircle.html(i);
                    } else {
                        stepItem.removeClass('completed active');
                        stepCircle.html(i);
                    }
                }

                // Actualizar barra de progreso del stepper
                const progressWidth = ((step - 1) / 3) * 100;
                \$('.stepper-progress').css('width', `\${progressWidth}%`);

                currentStep = step;

                // Visibilidad de botones
                if (currentStep === 1) {
                    \$('#btnAnterior').addClass('invisible');
                } else {
                    \$('#btnAnterior').removeClass('invisible');
                }

                if (currentStep === 4) {
                    // Cargar valores para el resumen
                    \$('#sum-nombre').text(\$('#nombre').val() + ' ' + \$('#apellido_paterno').val() + ' ' + \$('#apellido_materno').val());
                    \$('#sum-ine').text(\$('#credencial_ine').val());
                    \$('#sum-curp').text(\$('#curp').val().toUpperCase());
                    \$('#sum-telefono').text(\$('#telefono').val());
                    \$('#sum-correo').text(\$('#correo_electronico').val());
                    \$('#sum-cargo').text(\$('#cargo').val());
                    \$('#sum-seccion').text(\$('#seccion_electoral').val());
                    \$('#sum-municipio').text(\$('#municipio').val());

                    \$('#btnSiguiente').addClass('d-none');
                    \$('#btnConfirmar').removeClass('d-none');
                } else {
                    \$('#btnSiguiente').removeClass('d-none');
                    \$('#btnConfirmar').addClass('d-none');
                }
            }

            // Validar campos del paso
            function validateStep(step) {
                let isValid = true;
                let errorMsg = '';

                // Quitar errores previos
                \$(`#step-\${step}-content .form-control, #step-\${step}-content .form-select`).removeClass('is-invalid');

                if (step === 1) {
                    const fields = ['#nombre', '#apellido_paterno', '#apellido_materno', '#credencial_ine', '#curp'];
                    fields.forEach(function(field) {
                        const val = \$(field).val().trim();
                        if (!val) {
                            \$(field).addClass('is-invalid');
                            isValid = false;
                        }
                    });

                    // Validar CURP regex
                    const curp = \$('#curp').val().trim().toUpperCase();
                    const curpRegex = /^[A-Z]{4}\\d{6}[HM][A-Z]{5}[A-Z0-9]\\d\$/;
                    if (curp && !curpRegex.test(curp)) {
                        \$('#curp').addClass('is-invalid');
                        isValid = false;
                        errorMsg = 'La CURP ingresada no cuenta con un formato oficial válido.';
                    }
                } 
                else if (step === 2) {
                    const tel = \$('#telefono').val().trim();
                    const email = \$('#correo_electronico').val().trim();

                    if (!tel) {
                        \$('#telefono').addClass('is-invalid');
                        isValid = false;
                    }
                    if (!email) {
                        \$('#correo_electronico').addClass('is-invalid');
                        isValid = false;
                    }

                    // Validar correo
                    if (email && !/^\\S+\@\\S+\\.\\S+\$/.test(email)) {
                        \$('#correo_electronico').addClass('is-invalid');
                        isValid = false;
                        errorMsg = 'El correo electrónico ingresado no tiene un formato válido.';
                    }

                    // Validar teléfono
                    if (tel && tel.length !== 10) {
                        \$('#telefono').addClass('is-invalid');
                        isValid = false;
                        errorMsg = 'El teléfono debe contener exactamente 10 dígitos.';
                    }
                } 
                else if (step === 3) {
                    const fields = ['#cargo', '#seccion_electoral', '#municipio'];
                    fields.forEach(function(field) {
                        const val = \$(field).val();
                        if (!val || val.trim() === '') {
                            \$(field).addClass('is-invalid');
                            isValid = false;
                        }
                    });

                    // Validar sección electoral (numérico de 4 dígitos)
                    const seccion = \$('#seccion_electoral').val().trim();
                    if (seccion && !/^\\d{4}\$/.test(seccion)) {
                        \$('#seccion_electoral').addClass('is-invalid');
                        isValid = false;
                        errorMsg = 'La Sección Electoral debe contener exactamente 4 caracteres numéricos.';
                    }
                }

                if (!isValid) {
                    Swal.fire({
                        icon: 'warning',
                        title: 'Campos incompletos o incorrectos',
                        text: errorMsg || 'Por favor, complete todos los campos requeridos en este paso.',
                        confirmButtonColor: '#6B2D8B'
                    });
                }

                return isValid;
            }

            // Anterior click
            \$('#btnAnterior').on('click', function() {
                if (currentStep > 1) {
                    goToStep(currentStep - 1);
                }
            });

            // Siguiente click
            \$('#btnSiguiente').on('click', function() {
                if (currentStep < 4) {
                    goToStep(currentStep + 1);
                }
            });

            // Limpiar click
            \$('#btnLimpiar').on('click', function() {
                Swal.fire({
                    title: '¿Limpiar formulario?',
                    text: "Se borrarán todos los datos capturados en el paso actual.",
                    icon: 'question',
                    showCancelButton: true,
                    confirmButtonColor: '#dc3545',
                    cancelButtonColor: '#6c757d',
                    confirmButtonText: 'Sí, limpiar',
                    cancelButtonText: 'Cancelar'
                }).then((result) => {
                    if (result.isConfirmed) {
                        \$(`#step-\${currentStep}-content input, #step-\${currentStep}-content select`).val('');
                        \$(`#step-\${currentStep}-content .form-control, #step-\${currentStep}-content .form-select`).removeClass('is-invalid');
                    }
                });
            });

            // Envío por AJAX
            \$('#wizardForm').on('submit', function(e) {
                e.preventDefault();

                if (!validateStep(4)) return;

                const formData = new FormData(this);
                formData.append('accion', 'guardar');
                
                \$('#btnConfirmar').html('<span class="spinner-border spinner-border-sm me-2"></span>Registrando...').prop('disabled', true);

                fetch('registro_auxiliares.pl', {
                    method: 'POST',
                    body: formData
                })
                .then(response => response.json())
                .then(data => {
                    \$('#btnConfirmar').html('<i class="bi bi-check-circle-fill me-2"></i>Confirmar y Registrar').prop('disabled', false);
                    
                    if (data.success) {
                        Swal.fire({
                            title: '¡Registro Exitoso!',
                            text: data.message,
                            icon: 'success',
                            confirmButtonColor: '#198754'
                        }).then(() => {
                            \$('#wizardForm')[0].reset();
                            goToStep(1);
                            
                            // Recargar página para actualizar la tabla lateral
                            window.location.reload();
                        });
                    } else {
                        Swal.fire({
                            title: 'Error de Registro',
                            text: data.message,
                            icon: 'error',
                            confirmButtonColor: '#6B2D8B'
                        });
                    }
                })
                .catch(error => {
                    \$('#btnConfirmar').html('<i class="bi bi-check-circle-fill me-2"></i>Confirmar y Registrar').prop('disabled', false);
                    
                    Swal.fire({
                        title: 'Error de Red',
                        text: 'No se pudo establecer comunicación con el servidor. Intente más tarde.',
                        icon: 'error',
                        confirmButtonColor: '#6B2D8B'
                    });
                });
            });

            // Prevenir submit automático con Enter
            \$(window).keydown(function(event){
                if(event.keyCode == 13) {
                  event.preventDefault();
                  return false;
                }
            });
        });
    </script>
</body>
</html>
HTML
