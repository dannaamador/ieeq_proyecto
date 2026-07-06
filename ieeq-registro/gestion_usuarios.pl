#!C:\xampp\perl\bin\perl.exe
use strict;
use warnings;
use utf8;
use CGI;
use CGI::Session;
use FindBin;
require "$FindBin::Bin/db.pl";
use Digest::SHA qw(sha256_hex);

my $cgi = CGI->new;

# Configurar salida UTF-8
binmode(STDOUT, ":utf8");

my $session = CGI::Session->new(undef, $cgi, {Directory=>"$FindBin::Bin/.sesiones"});

if (!$session->param('id_usuario')) {
    print $cgi->redirect(-uri => 'login.pl');
    exit;
}

my $rol_actual = $session->param('rol') || '';
if ($rol_actual ne 'administrador') {
    print $cgi->redirect(-uri => 'dashboard.pl');
    exit;
}

# Manejo de acciones (POST)
if ($cgi->request_method() eq 'POST') {
    my $accion = $cgi->param('accion') || '';
    
    if ($accion eq 'crear') {
        my $nombre = $cgi->param('nombre') || '';
        my $apellido_paterno = $cgi->param('apellido_paterno') || '';
        my $apellido_materno = $cgi->param('apellido_materno') || '';
        my $correo = $cgi->param('correo_electronico') || '';
        my $password = $cgi->param('password') || '';
        my $tipo_usuario = $cgi->param('tipo_usuario') || '';
        my $activo = $cgi->param('activo') ? 1 : 0;
        
        # Limpieza de espacios
        $nombre =~ s/^\s+|\s+$//g;
        $apellido_paterno =~ s/^\s+|\s+$//g;
        $apellido_materno =~ s/^\s+|\s+$//g;
        $correo =~ s/^\s+|\s+$//g;
        $tipo_usuario =~ s/^\s+|\s+$//g;
        
        if ($nombre && $apellido_paterno && $correo && $password && $tipo_usuario) {
            # Verificar duplicado de correo
            my @exists = execute_query_list("SELECT id_usuario FROM usuarios WHERE correo_electronico = ?", $correo);
            if (@exists) {
                print $cgi->header(-type => 'application/json', -charset => 'utf-8');
                print '{"success":false,"message":"El correo electrónico ya se encuentra registrado."}';
                exit;
            }
            
            # Autogenerar username como prefijo de correo electrónico
            my ($username) = split /@/, $correo;
            
            my $hash = sha256_hex($password);
            my $sql = "INSERT INTO usuarios (correo_electronico, contrasena, nombre, apellido_paterno, apellido_materno, tipo_usuario, activo) VALUES (?, ?, ?, ?, ?, ?, ?)";
            
            if (execute_query_write($sql, $correo, $hash, $nombre, $apellido_paterno, $apellido_materno, $tipo_usuario, $activo)) {
                print $cgi->header(-type => 'application/json', -charset => 'utf-8');
                print '{"success":true,"message":"Usuario creado exitosamente."}';
                exit;
            } else {
                print $cgi->header(-type => 'application/json', -charset => 'utf-8');
                print '{"success":false,"message":"Error al registrar el usuario en la base de datos."}';
                exit;
            }
        } else {
            print $cgi->header(-type => 'application/json', -charset => 'utf-8');
            print '{"success":false,"message":"Por favor complete todos los campos obligatorios."}';
            exit;
        }
    }
    elsif ($accion eq 'editar') {
        my $id = $cgi->param('id_usuario') || '';
        my $nombre = $cgi->param('nombre') || '';
        my $apellido_paterno = $cgi->param('apellido_paterno') || '';
        my $apellido_materno = $cgi->param('apellido_materno') || '';
        my $correo = $cgi->param('correo_electronico') || '';
        my $password = $cgi->param('password') || '';
        my $tipo_usuario = $cgi->param('tipo_usuario') || '';
        my $activo = $cgi->param('activo') ? 1 : 0;
        
        $nombre =~ s/^\s+|\s+$//g;
        $apellido_paterno =~ s/^\s+|\s+$//g;
        $apellido_materno =~ s/^\s+|\s+$//g;
        $correo =~ s/^\s+|\s+$//g;
        $tipo_usuario =~ s/^\s+|\s+$//g;
        
        if ($id && $nombre && $apellido_paterno && $correo && $tipo_usuario) {
            # Verificar duplicado de correo excluyendo al mismo usuario
            my @exists = execute_query_list("SELECT id_usuario FROM usuarios WHERE correo_electronico = ? AND id_usuario != ?", $correo, $id);
            if (@exists) {
                print $cgi->header(-type => 'application/json', -charset => 'utf-8');
                print '{"success":false,"message":"El correo electrónico ya está registrado por otro usuario."}';
                exit;
            }
            
            my ($username) = split /@/, $correo;
            my $sql;
            my @params;
            
            if ($password) {
                my $hash = sha256_hex($password);
                $sql = "UPDATE usuarios SET correo_electronico = ?, nombre = ?, apellido_paterno = ?, apellido_materno = ?, tipo_usuario = ?, activo = ?, contrasena = ? WHERE id_usuario = ?";
                @params = ($correo, $nombre, $apellido_paterno, $apellido_materno, $tipo_usuario, $activo, $hash, $id);
            } else {
                $sql = "UPDATE usuarios SET correo_electronico = ?, nombre = ?, apellido_paterno = ?, apellido_materno = ?, tipo_usuario = ?, activo = ? WHERE id_usuario = ?";
                @params = ($correo, $nombre, $apellido_paterno, $apellido_materno, $tipo_usuario, $activo, $id);
            }
            
            if (execute_query_write($sql, @params)) {
                print $cgi->header(-type => 'application/json', -charset => 'utf-8');
                print '{"success":true,"message":"Usuario actualizado exitosamente."}';
                exit;
            } else {
                print $cgi->header(-type => 'application/json', -charset => 'utf-8');
                print '{"success":false,"message":"Error al actualizar los datos en la base de datos."}';
                exit;
            }
        } else {
            print $cgi->header(-type => 'application/json', -charset => 'utf-8');
            print '{"success":false,"message":"Por favor complete todos los campos obligatorios."}';
            exit;
        }
    }
    elsif ($accion eq 'toggle_activo') {
        my $id = $cgi->param('id_usuario') || '';
        my $activo = $cgi->param('activo') ? 1 : 0;
        
        if ($id) {
            my $sql = "UPDATE usuarios SET activo = ? WHERE id_usuario = ?";
            if (execute_query_write($sql, $activo, $id)) {
                my @counts = execute_query_list("SELECT COUNT(*) AS total, SUM(activo) AS activos FROM usuarios");
                my $total = $counts[0]->{total} || 0;
                my $activos = $counts[0]->{activos} || 0;
                
                print $cgi->header(-type => 'application/json', -charset => 'utf-8');
                print qq|{"success":true,"total":$total,"activos":$activos}|;
                exit;
            } else {
                print $cgi->header(-type => 'application/json', -charset => 'utf-8');
                print '{"success":false,"message":"Error al actualizar el estatus."}';
                exit;
            }
        }
    }
}

# Obtener estadísticas reales
my @counts_res = execute_query_list("SELECT COUNT(*) AS total, SUM(activo) AS activos FROM usuarios");
my $total_usuarios = $counts_res[0]->{total} || 0;
my $activos_usuarios = $counts_res[0]->{activos} || 0;

# Obtener listado de usuarios de base de datos v3
my @usuarios = execute_query_list("SELECT id_usuario, correo_electronico, nombre, apellido_paterno, apellido_materno, tipo_usuario, activo FROM usuarios ORDER BY id_usuario DESC");

my $filas_html = '';
for my $u (@usuarios) {
    my $id = $u->{id_usuario};
    my $activo = $u->{activo};
    
    # Clases y texto de estatus
    my $status_class = $activo == 1 ? 'badge-active' : 'badge-inactive';
    my $status_text = $activo == 1 ? 'Activo' : 'Inactivo';
    
    # Nombre completo concatenado
    my $nom_completo = $u->{nombre} . ' ' . $u->{apellido_paterno};
    $nom_completo .= ' ' . $u->{apellido_materno} if $u->{apellido_materno};
    
    # Iniciales del avatar
    my $initials = uc(substr($u->{nombre} || '', 0, 1)) . uc(substr($u->{apellido_paterno} || '', 0, 1));
    $initials ||= 'U';
    
    # Colores elegantes de avatares
    my @avatar_colors = ('#6B2D8B', '#d97706', '#0d9488', '#2563eb', '#ea580c', '#059669', '#db2777');
    my $color = $avatar_colors[ $id % scalar(@avatar_colors) ];
    
    # Extraer nombre de usuario de correo
    my ($username) = split /@/, $u->{correo_electronico};
    
    # Badge del tipo de usuario
    my $tipo_badge_class = '';
    my $tipo_text = '';
    if ($u->{tipo_usuario} eq 'ADMINISTRADOR') {
        $tipo_badge_class = 'badge-admin';
        $tipo_text = 'Administrador';
    } elsif ($u->{tipo_usuario} eq 'FUNCIONARIO_IEEQ') {
        $tipo_badge_class = 'badge-funcionario';
        $tipo_text = 'Funcionario IEEQ';
    } else {
        $tipo_badge_class = 'badge-auxiliar';
        $tipo_text = 'Auxiliar';
    }
    
    # Escapar campos de texto para uso en JS
    my $esc_nombre = $u->{nombre} || '';
    my $esc_paterno = $u->{apellido_paterno} || '';
    my $esc_materno = $u->{apellido_materno} || '';
    my $esc_correo = $u->{correo_electronico} || '';
    $esc_nombre =~ s/'/\\'/g;
    $esc_paterno =~ s/'/\\'/g;
    $esc_materno =~ s/'/\\'/g;
    $esc_correo =~ s/'/\\'/g;
    
    my $checked_attr = $activo == 1 ? 'checked' : '';
    
    $filas_html .= <<"ROW";
    <tr data-id="$id">
        <td class="ps-4 fw-semibold text-secondary align-middle">#$id</td>
        <td class="align-middle">
            <div class="d-flex align-items-center">
                <div class="rounded-circle d-flex align-items-center justify-content-center text-white me-3 fw-semibold shadow-sm flex-shrink-0" style="width: 40px; height: 40px; background-color: $color; font-size: 0.9rem;">
                    $initials
                </div>
                <div class="fw-semibold text-dark">$nom_completo</div>
            </div>
        </td>
        <td class="align-middle">
            <div class="fw-semibold text-secondary" style="font-size: 0.9rem;">\@$username</div>
            <div class="text-muted" style="font-size: 0.8rem;">$u->{correo_electronico}</div>
        </td>
        <td class="align-middle">
            <span class="badge $tipo_badge_class px-3 py-2 rounded-pill" style="font-size: 0.825rem;">$tipo_text</span>
        </td>
        <td class="align-middle">
            <span id="status-badge-$id" class="badge $status_class px-3 py-2 rounded-pill d-inline-flex align-items-center" style="font-size: 0.825rem;">
                <span class="me-1">●</span> <span class="status-text">$status_text</span>
            </span>
        </td>
        <td class="pe-4 align-middle">
            <div class="d-flex align-items-center gap-3">
                <button class="btn btn-edit-user p-1" onclick="abrirModalEditar($id, '$esc_nombre', '$esc_paterno', '$esc_materno', '$esc_correo', '$u->{tipo_usuario}', $activo)" title="Editar Usuario">
                    <i class="bi bi-pencil" style="font-size: 1.1rem;"></i>
                </button>
                <div class="form-check form-switch mb-0">
                    <input class="form-check-input" type="checkbox" role="switch" id="switch-$id" $checked_attr onchange="toggleUsuarioActivo($id, this)">
                </div>
            </div>
        </td>
    </tr>
ROW
}

# Cabeceras anti-caché
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
    <title>Gestión de Usuarios - IEEQ</title>
    <!-- Bootstrap 5 -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons\@1.11.3/font/bootstrap-icons.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght\@300;400;500;600;700&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/sweetalert2\@11"></script>
    <style>
        body { font-family: 'Outfit', sans-serif; background-color: #f4f6f9; overflow-x: hidden; }
        
        #content { padding: 2rem; }
        
        .top-header {
            background: #fff;
            padding: 1.25rem 2rem;
            border-bottom: 1px solid #eef2f6;
            margin-bottom: 2rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .text-purple {
            color: #6B2D8B !important;
        }
        
        .btn-ieeq {
            background-color: #6B2D8B;
            color: white;
            font-weight: 600;
            padding: 0.6rem 1.5rem;
            border-radius: 50px;
            transition: all 0.3s;
            border: none;
        }
        .btn-ieeq:hover {
            background-color: #55246f;
            color: white;
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(107, 45, 139, 0.25);
        }
        
        .counts-pill {
            background-color: #ffffff;
            border: 1px solid #e5e7eb;
            border-radius: 50px;
            padding: 0.5rem 1.2rem;
            font-size: 0.9rem;
            display: inline-flex;
            align-items: center;
            box-shadow: 0 1px 3px rgba(0,0,0,0.02);
        }
        
        #usuariosTable thead tr {
            background-color: #6B2D8B !important;
            color: #ffffff !important;
        }
        #usuariosTable thead th {
            border: none !important;
            font-weight: 600;
            text-transform: uppercase;
            font-size: 0.8rem;
            letter-spacing: 0.5px;
            padding: 14px 16px;
        }
        #usuariosTable thead th:first-child {
            border-top-left-radius: 12px;
        }
        #usuariosTable thead th:last-child {
            border-top-right-radius: 12px;
        }
        
        .table-hover tbody tr:hover {
            background-color: #f9fafb;
        }
        
        .table > :not(caption) > * > * {
            padding: 1rem 1rem;
            border-bottom: 1px solid #f3f4f6;
        }
        
        .badge-admin {
            background-color: #F3E8FF !important;
            color: #6B2D8B !important;
            font-weight: 600;
        }
        .badge-auxiliar {
            background-color: #DBEAFE !important;
            color: #2563EB !important;
            font-weight: 600;
        }
        .badge-funcionario {
            background-color: #D1FAE5 !important;
            color: #059669 !important;
            font-weight: 600;
        }
        .badge-active {
            background-color: #D1FAE5 !important;
            color: #059669 !important;
            font-weight: 600;
        }
        .badge-inactive {
            background-color: #FEE2E2 !important;
            color: #EF4444 !important;
            font-weight: 600;
        }
        
        .btn-edit-user {
            background: none;
            border: none;
            color: #9ca3af;
            padding: 6px;
            transition: all 0.2s;
        }
        .btn-edit-user:hover {
            color: #6B2D8B;
            transform: scale(1.15);
        }
        
        .form-switch .form-check-input {
            width: 2.8em;
            height: 1.5em;
            cursor: pointer;
            border-color: #d1d5db;
        }
        .form-switch .form-check-input:checked {
            background-color: #10B981;
            border-color: #10B981;
        }
        .form-switch .form-check-input:focus {
            box-shadow: 0 0 0 0.25rem rgba(16, 185, 129, 0.25);
            border-color: #10B981;
        }
        
        .search-container input {
            height: 52px;
            font-size: 0.95rem;
            border: 1px solid #e5e7eb;
            background-color: #ffffff;
            transition: all 0.3s;
        }
        .search-container input:focus {
            border-color: #6B2D8B;
            box-shadow: 0 0 0 0.25rem rgba(107, 45, 139, 0.15);
        }
        
        .modal-content {
            border-radius: 16px;
            border: none;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        .modal-header {
            border-bottom: 1px solid #f3f4f6;
            padding: 1.5rem 1.75rem;
        }
        .modal-body {
            padding: 1.75rem;
        }
        .modal-footer {
            border-top: 1px solid #f3f4f6;
            padding: 1.25rem 1.75rem;
        }
        .form-control, .form-select {
            border-radius: 10px;
            padding: 10px 14px;
            border: 1px solid #d1d5db;
        }
        .form-control:focus, .form-select:focus {
            border-color: #6B2D8B;
            box-shadow: 0 0 0 0.25rem rgba(107, 45, 139, 0.15);
        }
        
        \@media (max-width: 991px) {
            #content { padding: 1rem; }
        }
    </style>
</head>
<body>
HTML

# Sidebar compartido de Administrador
require "$FindBin::Bin/_sidebar_admin.pl";

print <<"HTML";
    <!-- Contenido Principal -->
    <div id="content">
        <!-- Cabecera de Página superior -->
        <div class="top-header">
            <div class="d-flex align-items-center">
                <button class="btn btn-light d-md-none me-3 shadow-sm" id="sidebarToggle">
                    <i class="bi bi-list fs-4"></i>
                </button>
                <h4 class="mb-0 text-dark fw-bold">Gestión de Usuarios</h4>
            </div>
            <div class="text-muted d-none d-md-block">Instituto Electoral del Estado de Querétaro</div>
        </div>

        <!-- Encabezado de la Sección y Botón -->
        <div class="d-flex justify-content-between align-items-start mb-2">
            <div>
                <h2 class="fw-bold text-dark mb-1">Gestión de Usuarios</h2>
                <p class="text-muted mb-0">Administra los accesos al sistema IEEQ.</p>
            </div>
            <button class="btn btn-ieeq px-4" onclick="abrirModalCrear()">
                <i class="bi bi-plus-lg me-2"></i>Nuevo Usuario
            </button>
        </div>

        <!-- Contador Real de Usuarios -->
        <div class="d-flex align-items-center gap-2 mb-4" style="font-size: 0.95rem;">
            <div class="counts-pill">
                <i class="bi bi-person text-purple me-2"></i>
                <span class="fw-semibold me-1" id="countTotal">$total_usuarios</span> usuarios registrados
            </div>
            <span class="text-muted">·</span>
            <span class="text-muted"><span id="countActivos" class="fw-semibold text-dark">$activos_usuarios</span> activos</span>
        </div>

        <!-- Buscador general de la tabla -->
        <div class="position-relative mb-4 search-container">
            <i class="bi bi-search position-absolute top-50 start-0 translate-middle-y ms-4 text-muted" style="font-size: 1.15rem;"></i>
            <input type="text" id="searchInput" class="form-control rounded-pill ps-5 border-0 shadow-sm" placeholder="Buscar por nombre, usuario o correo electrónico..." style="padding-left: 3.2rem !important;">
        </div>

        <!-- Card con Tabla de Usuarios -->
        <div class="card border-0 shadow-sm rounded-4 overflow-hidden mb-5">
            <div class="card-body p-0">
                <div class="table-responsive">
                    <table id="usuariosTable" class="table table-hover align-middle mb-0 w-100">
                        <thead>
                            <tr>
                                <th class="ps-4" style="width: 8%;">ID</th>
                                <th style="width: 32%;">Nombre Completo</th>
                                <th style="width: 25%;">Usuario / Correo</th>
                                <th style="width: 15%;">Tipo de Usuario</th>
                                <th style="width: 12%;">Estatus</th>
                                <th class="pe-4" style="width: 8%;">Acciones</th>
                            </tr>
                        </thead>
                        <tbody>
                            $filas_html
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>

    <!-- Modal Nuevo Usuario -->
    <div class="modal fade" id="modalCrear" tabindex="-1" aria-hidden="true">
        <div class="modal-dialog modal-dialog-centered modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title fw-bold text-purple"><i class="bi bi-person-plus me-2"></i>Nuevo Usuario</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <form id="formCrear" class="needs-validation" novalidate onsubmit="event.preventDefault(); submitForm(this, 'modalCrear');">
                    <input type="hidden" name="accion" value="crear">
                    <div class="modal-body">
                        <div class="row g-3">
                            <div class="col-md-4">
                                <label class="form-label fw-semibold">Nombre(s) <span class="text-danger">*</span></label>
                                <input type="text" class="form-control" name="nombre" placeholder="Ej. María" required>
                                <div class="invalid-feedback">Por favor, ingrese el nombre.</div>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label fw-semibold">Apellido Paterno <span class="text-danger">*</span></label>
                                <input type="text" class="form-control" name="apellido_paterno" placeholder="Ej. González" required>
                                <div class="invalid-feedback">Por favor, ingrese el apellido paterno.</div>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label fw-semibold">Apellido Materno</label>
                                <input type="text" class="form-control" name="apellido_materno" placeholder="Ej. Pérez">
                            </div>
                            
                            <div class="col-md-6">
                                <label class="form-label fw-semibold">Correo Electrónico <span class="text-danger">*</span></label>
                                <input type="email" class="form-control" name="correo_electronico" placeholder="Ej. correo\@asociacion.org" required>
                                <div class="invalid-feedback">Por favor, ingrese un correo válido.</div>
                            </div>
                            
                            <div class="col-md-6">
                                <label class="form-label fw-semibold">Tipo de Usuario <span class="text-danger">*</span></label>
                                <select class="form-select" name="tipo_usuario" required>
                                    <option value="" disabled selected>Seleccione...</option>
                                    <option value="ADMINISTRADOR">Administrador</option>
                                    <option value="FUNCIONARIO_IEEQ">Funcionario IEEQ</option>
                                    <option value="AUXILIAR">Auxiliar</option>
                                </select>
                                <div class="invalid-feedback">Por favor, seleccione un tipo de usuario.</div>
                            </div>
                            
                            <div class="col-md-12">
                                <label class="form-label fw-semibold">Contraseña <span class="text-danger">*</span></label>
                                <input type="password" class="form-control" name="password" placeholder="Mínimo 8 caracteres" required minlength="8">
                                <div class="invalid-feedback">La contraseña es requerida (mínimo 8 caracteres).</div>
                            </div>
                            
                            <div class="col-md-12">
                                <div class="form-check form-switch p-3 bg-light rounded-3 mt-2">
                                    <input class="form-check-input ms-0 mt-1 me-2" type="checkbox" name="activo" value="1" id="checkActivoCrear" checked>
                                    <label class="form-check-label fw-semibold ms-2" for="checkActivoCrear">Habilitar cuenta inmediatamente</label>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-light rounded-pill px-4" data-bs-dismiss="modal">Cancelar</button>
                        <button type="submit" class="btn btn-ieeq">Guardar Usuario</button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <!-- Modal Editar Usuario -->
    <div class="modal fade" id="modalEditar" tabindex="-1" aria-hidden="true">
        <div class="modal-dialog modal-dialog-centered modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title fw-bold text-purple"><i class="bi bi-pencil-square me-2"></i>Modificar Usuario</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <form id="formEditar" class="needs-validation" novalidate onsubmit="event.preventDefault(); submitForm(this, 'modalEditar');">
                    <input type="hidden" name="accion" value="editar">
                    <input type="hidden" name="id_usuario" id="edit_id">
                    <div class="modal-body">
                        <div class="row g-3">
                            <div class="col-md-4">
                                <label class="form-label fw-semibold">Nombre(s) <span class="text-danger">*</span></label>
                                <input type="text" class="form-control" name="nombre" id="edit_nombre" required>
                                <div class="invalid-feedback">Por favor, ingrese el nombre.</div>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label fw-semibold">Apellido Paterno <span class="text-danger">*</span></label>
                                <input type="text" class="form-control" name="apellido_paterno" id="edit_paterno" required>
                                <div class="invalid-feedback">Por favor, ingrese el apellido paterno.</div>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label fw-semibold">Apellido Materno</label>
                                <input type="text" class="form-control" name="apellido_materno" id="edit_materno">
                            </div>
                            
                            <div class="col-md-6">
                                <label class="form-label fw-semibold">Correo Electrónico <span class="text-danger">*</span></label>
                                <input type="email" class="form-control" name="correo_electronico" id="edit_correo" required>
                                <div class="invalid-feedback">Por favor, ingrese un correo válido.</div>
                            </div>
                            
                            <div class="col-md-6">
                                <label class="form-label fw-semibold">Tipo de Usuario <span class="text-danger">*</span></label>
                                <select class="form-select" name="tipo_usuario" id="edit_tipo" required>
                                    <option value="ADMINISTRADOR">Administrador</option>
                                    <option value="FUNCIONARIO_IEEQ">Funcionario IEEQ</option>
                                    <option value="AUXILIAR">Auxiliar</option>
                                </select>
                                <div class="invalid-feedback">Por favor, seleccione un tipo de usuario.</div>
                            </div>
                            
                            <div class="col-md-12">
                                <label class="form-label fw-semibold text-danger">Nueva Contraseña (Opcional)</label>
                                <input type="password" class="form-control" name="password" placeholder="Dejar en blanco para conservar actual (mínimo 8 caracteres)" minlength="8">
                                <div class="invalid-feedback">La nueva contraseña debe tener al menos 8 caracteres.</div>
                            </div>
                            
                            <div class="col-md-12">
                                <div class="form-check form-switch p-3 bg-light rounded-3 mt-2">
                                    <input class="form-check-input ms-0 mt-1 me-2" type="checkbox" name="activo" value="1" id="edit_activo">
                                    <label class="form-check-label fw-semibold ms-2" for="edit_activo">Cuenta Activa</label>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-light rounded-pill px-4" data-bs-dismiss="modal">Cancelar</button>
                        <button type="submit" class="btn btn-ieeq">Actualizar Datos</button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <!-- Scripts -->
    <script src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.6/js/dataTables.bootstrap5.min.js"></script>
    <script>
        var table;
        \$(document).ready(function() {
            // Inicialización de DataTable en español con personalización de layout
            table = \$('#usuariosTable').DataTable({
                "dom": "rt<'p-4 border-top d-flex justify-content-between align-items-center'ip>",
                "language": {
                    "url": "https://cdn.datatables.net/plug-ins/1.13.6/i18n/es-ES.json"
                },
                "pageLength": 10,
                "ordering": true,
                "columnDefs": [
                    { "orderable": false, "targets": [5] } // Deshabilitar ordenación en Acciones
                ]
            });

            // Vinculación del buscador personalizado
            \$('#searchInput').on('keyup', function() {
                table.search(this.value).draw();
            });

            // Toggle del sidebar en móvil
            \$('#sidebarToggle, .mobile-overlay').click(function() {
                \$('#sidebar, .mobile-overlay').toggleClass('active');
            });
        });

        // Abrir modales limpios
        function abrirModalCrear() {
            const form = document.getElementById('formCrear');
            form.reset();
            form.classList.remove('was-validated');
            const modal = new bootstrap.Modal(document.getElementById('modalCrear'));
            modal.show();
        }

        function abrirModalEditar(id, nombre, paterno, materno, correo, tipo, activo) {
            const form = document.getElementById('formEditar');
            form.reset();
            form.classList.remove('was-validated');
            
            document.getElementById('edit_id').value = id;
            document.getElementById('edit_nombre').value = nombre;
            document.getElementById('edit_paterno').value = paterno;
            document.getElementById('edit_materno').value = materno;
            document.getElementById('edit_correo').value = correo;
            document.getElementById('edit_tipo').value = tipo;
            document.getElementById('edit_activo').checked = (activo == 1);
            
            const modal = new bootstrap.Modal(document.getElementById('modalEditar'));
            modal.show();
        }

        // Envío asíncrono de Formularios
        function submitForm(form, modalId) {
            if (!form.checkValidity()) {
                form.classList.add('was-validated');
                return;
            }
            
            const formData = \$(form).serialize();
            const submitBtn = \$(form).find('button[type="submit"]');
            const originalText = submitBtn.html();
            
            submitBtn.html('<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Guardando...').prop('disabled', true);
            
            \$.ajax({
                url: 'gestion_usuarios.pl',
                type: 'POST',
                data: formData,
                dataType: 'json',
                success: function(response) {
                    submitBtn.html(originalText).prop('disabled', false);
                    if (response.success) {
                        bootstrap.Modal.getInstance(document.getElementById(modalId)).hide();
                        
                        const Toast = Swal.mixin({
                            toast: true,
                            position: 'top-end',
                            showConfirmButton: false,
                            timer: 1500,
                            timerProgressBar: true
                        });
                        Toast.fire({
                            icon: 'success',
                            title: response.message
                        }).then(() => {
                            location.reload();
                        });
                    } else {
                        Swal.fire({
                            icon: 'error',
                            title: 'Error',
                            text: response.message || 'Hubo un error al guardar los cambios.'
                        });
                    }
                },
                error: function() {
                    submitBtn.html(originalText).prop('disabled', false);
                    Swal.fire({
                        icon: 'error',
                        title: 'Error de red',
                        text: 'No se pudo establecer comunicación con el servidor.'
                    });
                }
            });
        }

        // Toggle del estatus activo/inactivo vía AJAX
        function toggleUsuarioActivo(id, checkbox) {
            const activo = checkbox.checked ? 1 : 0;
            checkbox.disabled = true;
            
            \$.ajax({
                url: 'gestion_usuarios.pl',
                type: 'POST',
                data: {
                    accion: 'toggle_activo',
                    id_usuario: id,
                    activo: activo
                },
                dataType: 'json',
                success: function(response) {
                    checkbox.disabled = false;
                    if (response.success) {
                        \$('#countTotal').text(response.total);
                        \$('#countActivos').text(response.activos);
                        
                        const badge = \$(`#status-badge-\${id}`);
                        const text = badge.find('.status-text');
                        
                        if (activo === 1) {
                            badge.removeClass('badge-inactive').addClass('badge-active');
                            text.text('Activo');
                        } else {
                            badge.removeClass('badge-active').addClass('badge-inactive');
                            text.text('Inactivo');
                        }
                        
                        const Toast = Swal.mixin({
                            toast: true,
                            position: 'top-end',
                            showConfirmButton: false,
                            timer: 2000,
                            timerProgressBar: true
                        });
                        Toast.fire({
                            icon: 'success',
                            title: 'Estatus actualizado exitosamente.'
                        });
                    } else {
                        checkbox.checked = !checkbox.checked;
                        Swal.fire({
                            icon: 'error',
                            title: 'Error',
                            text: response.message || 'No se pudo actualizar el estatus.'
                        });
                    }
                },
                error: function() {
                    checkbox.disabled = false;
                    checkbox.checked = !checkbox.checked;
                    Swal.fire({
                        icon: 'error',
                        title: 'Error de red',
                        text: 'Hubo un problema de conexión con el servidor.'
                    });
                }
            });
        }
    </script>
</body>
</html>
HTML
