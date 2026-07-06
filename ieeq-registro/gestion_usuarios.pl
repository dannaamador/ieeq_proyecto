#!/usr/bin/perl
use strict;
use warnings;
use CGI;
use CGI::Session;
use FindBin;
require "$FindBin::Bin/db.pl";
use Digest::SHA qw(sha256_hex);

my $cgi = CGI->new;
my $session = CGI::Session->new(undef, $cgi, {Directory=>"$FindBin::Bin/.sesiones"});

# Validar que exista una sesión activa; si no, redirigir al login
if (!$session->param('id_usuario')) {
    print $cgi->redirect(-uri => 'login.pl');
    exit;
}

# Verificar que el usuario tenga rol de administrador para acceder a este módulo
my $rol_actual = $session->param('rol') || '';
if ($rol_actual ne 'administrador') {
    print $cgi->redirect(-uri => 'dashboard.pl');
    exit;
}

# Obtener nombre completo de la sesión para mostrarlo en la interfaz
my $nombre_completo = $session->param('nombre_completo');

# Variables para manejar mensajes de retroalimentación al usuario
my $mensaje = '';
my $tipo_mensaje = '';

# Manejo de acciones POST (Crear, Editar, Habilitar/Deshabilitar)
if ($cgi->request_method() eq 'POST') {
    my $accion = $cgi->param('accion');
    
    # Acción para crear un nuevo usuario
    if ($accion eq 'crear') {
        # Recibir parámetros del formulario de creación
        my $username = $cgi->param('username');
        my $nombre = $cgi->param('nombre_completo');
        my $password = $cgi->param('password');
        my $rol = $cgi->param('rol');
        my $activo = $cgi->param('activo') ? 1 : 0;
        my $correo = $cgi->param('correo_electronico');
        my $curp = uc($cgi->param('curp') || '');
        my $clave = $cgi->param('clave_elector');
        my $tel = $cgi->param('telefono_movil');
        
        # Validar que los campos obligatorios existan
        if ($username && $nombre && $password && $rol && $correo && $curp && $clave && $tel) {
            # Verificar duplicado de correo
            my @dup_correo = execute_query_list("SELECT id_usuario FROM usuarios WHERE correo_electronico = ?", $correo);
            # Verificar duplicado de CURP
            my @dup_curp = execute_query_list("SELECT id_usuario FROM usuarios WHERE curp = ?", $curp);

            if (@dup_correo) {
                $mensaje = "El correo electronico ya esta registrado.";
                $tipo_mensaje = "error";
            } elsif (@dup_curp) {
                $mensaje = "La CURP ya esta registrada.";
                $tipo_mensaje = "error";
            } else {
                my $hash = sha256_hex($password);
                my $sql = "INSERT INTO usuarios (username, contrasena, nombre_completo, rol, activo, correo_electronico, curp, clave_elector, telefono_movil) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
                if (execute_query_write($sql, $username, $hash, $nombre, $rol, $activo, $correo, $curp, $clave, $tel)) {
                    $mensaje = "Usuario creado exitosamente.";
                    $tipo_mensaje = "success";
                } else {
                    $mensaje = "Error al crear usuario.";
                    $tipo_mensaje = "error";
                }
            }
        } else {
            $mensaje = "Por favor, completa todos los campos requeridos.";
            $tipo_mensaje = "warning";
        }
    }
    # Acción para editar un usuario existente
    elsif ($accion eq 'editar') {
        # Recibir parámetros del formulario de edición
        my $id = $cgi->param('id_usuario');
        my $username = $cgi->param('username');
        my $nombre = $cgi->param('nombre_completo');
        my $password = $cgi->param('password');
        my $rol = $cgi->param('rol');
        my $activo = $cgi->param('activo') ? 1 : 0;
        my $correo = $cgi->param('correo_electronico');
        my $curp = uc($cgi->param('curp') || '');
        my $clave = $cgi->param('clave_elector');
        my $tel = $cgi->param('telefono_movil');
        
        # Validar campos requeridos incluyendo los nuevos
        if ($id && $username && $nombre && $rol && $correo && $curp && $clave && $tel) {
            # Verificar duplicado de correo excluyendo al usuario actual
            my @dup_correo = execute_query_list("SELECT id_usuario FROM usuarios WHERE correo_electronico = ? AND id_usuario != ?", $correo, $id);
            # Verificar duplicado de CURP excluyendo al usuario actual
            my @dup_curp = execute_query_list("SELECT id_usuario FROM usuarios WHERE curp = ? AND id_usuario != ?", $curp, $id);

            if (@dup_correo) {
                $mensaje = "El correo electronico ya pertenece a otro usuario.";
                $tipo_mensaje = "error";
            } elsif (@dup_curp) {
                $mensaje = "La CURP ya pertenece a otro usuario.";
                $tipo_mensaje = "error";
            } elsif ($password) {
                my $hash = sha256_hex($password);
                my $sql = "UPDATE usuarios SET username=?, nombre_completo=?, rol=?, activo=?, contrasena=?, correo_electronico=?, curp=?, clave_elector=?, telefono_movil=? WHERE id_usuario=?";
                if (execute_query_write($sql, $username, $nombre, $rol, $activo, $hash, $correo, $curp, $clave, $tel, $id)) {
                    $mensaje = "Usuario actualizado exitosamente.";
                    $tipo_mensaje = "success";
                } else {
                    $mensaje = "Error al actualizar.";
                    $tipo_mensaje = "error";
                }
            } else {
                my $sql = "UPDATE usuarios SET username=?, nombre_completo=?, rol=?, activo=?, correo_electronico=?, curp=?, clave_elector=?, telefono_movil=? WHERE id_usuario=?";
                if (execute_query_write($sql, $username, $nombre, $rol, $activo, $correo, $curp, $clave, $tel, $id)) {
                    $mensaje = "Usuario actualizado exitosamente.";
                    $tipo_mensaje = "success";
                } else {
                    $mensaje = "Error al actualizar.";
                    $tipo_mensaje = "error";
                }
            }
        } else {
            $mensaje = "Por favor, completa todos los campos requeridos.";
            $tipo_mensaje = "warning";
        }
    }
    # Acción para alternar el estatus activo/inactivo (botón de actualización rápida)
    elsif ($accion eq 'toggle_activo') {
        my $id = $cgi->param('id_usuario');
        my $estado_actual = $cgi->param('estado_actual');
        my $nuevo_estado = $estado_actual == 1 ? 0 : 1;
        
        if ($id) {
            my $sql = "UPDATE usuarios SET activo=? WHERE id_usuario=?";
            execute_query_write($sql, $nuevo_estado, $id);
            $mensaje = "Estatus actualizado exitosamente.";
            $tipo_mensaje = "success";
        }
    }
}

# Obtener la lista completa de usuarios para renderizar en la tabla HTML
my @usuarios = execute_query_list("SELECT id_usuario, username, nombre_completo, rol, activo, correo_electronico, curp, clave_elector, telefono_movil FROM usuarios ORDER BY id_usuario DESC");

my $filas_html = '';
for my $u (@usuarios) {
    my $badge_class = $u->{activo} == 1 ? 'bg-success' : 'bg-danger';
    my $estado_texto = $u->{activo} == 1 ? 'Activo' : 'Inactivo';
    
    my $correo = $u->{correo_electronico} || '';
    my $curp   = $u->{curp} || '';
    my $clave  = $u->{clave_elector} || '';
    my $tel    = $u->{telefono_movil} || '';

    # Escapar caracteres especiales HTML para atributos data-*
    for my $ref (\$correo, \$curp, \$clave, \$tel) {
        $$ref =~ s/&/&amp;/g;
        $$ref =~ s/"/&quot;/g;
        $$ref =~ s/'/&#39;/g;
        $$ref =~ s/</&lt;/g;
        $$ref =~ s/>/&gt;/g;
    }
    my $nombre_esc = $u->{nombre_completo} || '';
    $nombre_esc =~ s/&/&amp;/g;
    $nombre_esc =~ s/"/&quot;/g;
    $nombre_esc =~ s/'/&#39;/g;
    my $user_esc = $u->{username} || '';
    $user_esc =~ s/&/&amp;/g;
    $user_esc =~ s/"/&quot;/g;

    my @words = split /\s+/, ($u->{nombre_completo} || '');
    my $initials = uc(substr($words[0] || '', 0, 1));
    $initials .= uc(substr($words[1], 0, 1)) if @words > 1;
    my @colors = ('#6B2D8B', '#0d6efd', '#198754', '#dc3545', '#fd7e14', '#0dcaf0');
    my $color = $colors[ length($u->{nombre_completo} || '') % 6 ];
    
    my $avatar = <<"AVATAR";
    <div class="d-flex align-items-center">
        <div class="rounded-circle d-flex align-items-center justify-content-center text-white me-3 fw-bold shadow-sm flex-shrink-0" style="width: 40px; height: 40px; background-color: $color; font-size: 0.9rem;">
            $initials
        </div>
        <div>$nombre_esc</div>
    </div>
AVATAR

    my %colores_rol = (
        'administrador' => 'bg-ieeq-purple',
        'operador' => 'bg-primary',
        'validador' => 'bg-warning',
        'lectura' => 'bg-secondary'
    );
    my $rol_badge_class = $colores_rol{$u->{rol}} || 'bg-dark';

    $filas_html .= <<"ROW";
    <tr>
        <td class="ps-4 fw-semibold text-secondary align-middle">$u->{id_usuario}</td>
        <td class="align-middle">$avatar</td>
        <td class="align-middle"><strong>$user_esc</strong><br><small class="text-muted">$correo</small></td>
        <td class="text-capitalize align-middle"><span class="badge $rol_badge_class px-2 py-1">$u->{rol}</span></td>
        <td class="align-middle"><span class="badge $badge_class px-3 py-2 rounded-pill">$estado_texto</span></td>
        <td class="pe-4 align-middle text-center">
            <button class="btn btn-sm btn-outline-primary me-1 btn-editar"
                data-id="$u->{id_usuario}"
                data-username="$user_esc"
                data-nombre="$nombre_esc"
                data-rol="$u->{rol}"
                data-activo="$u->{activo}"
                data-correo="$correo"
                data-curp="$curp"
                data-clave="$clave"
                data-tel="$tel"
                title="Editar">
                <i class="bi bi-pencil-square"></i>
            </button>
            <form method="POST" style="display:inline;">
                <input type="hidden" name="accion" value="toggle_activo">
                <input type="hidden" name="id_usuario" value="$u->{id_usuario}">
                <input type="hidden" name="estado_actual" value="$u->{activo}">
                <button type="submit" class="btn btn-sm btn-outline-secondary" title="Cambiar Estatus">
                    <i class="bi bi-arrow-repeat"></i>
                </button>
            </form>
        </td>
    </tr>
ROW
}

my $swal_script = '';
if ($mensaje) {
    $mensaje =~ s/'/\\'/g;
    $swal_script = qq|
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            const Toast = Swal.mixin({
              toast: true,
              position: 'bottom-end',
              showConfirmButton: false,
              timer: 3000,
              timerProgressBar: true
            });
            Toast.fire({icon: '$tipo_mensaje', title: '$mensaje'});
        });
    </script>
    |;
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
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons\@1.11.1/font/bootstrap-icons.css">
    <link href="https://cdn.jsdelivr.net/npm/sweetalert2\@11/dist/sweetalert2.min.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght\@300;400;600;700&display=swap" rel="stylesheet">
    <!-- DataTables CSS -->
    <link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/dataTables.bootstrap5.min.css">
    <link rel="stylesheet" href="https://cdn.datatables.net/responsive/2.5.0/css/responsive.bootstrap5.min.css">
    <style>
        body { font-family: 'Outfit', sans-serif; background-color: #f4f6f9; overflow-x: hidden; }
        #sidebar { width: 280px; height: 100vh; background-color: #6B2D8B; color: #ffffff; position: fixed; top: 0; left: 0; z-index: 1000; box-shadow: 4px 0 10px rgba(0,0,0,0.1); }
        .sidebar-header { padding: 2rem 1.5rem; text-align: center; border-bottom: 1px solid rgba(255,255,255,0.1); }
        .sidebar-header h3 { font-weight: 700; letter-spacing: 2px; margin-bottom: 5px; }
        .nav-pills .nav-link { border-radius: 0; padding: 15px 20px; font-weight: 400; opacity: 0.85; transition: all 0.2s; color: white; }
        .nav-pills .nav-link:hover { opacity: 1; background-color: rgba(255,255,255,0.1); border-left: 4px solid #ffffff; color: white; }
        .nav-pills .nav-link.active { background-color: rgba(255,255,255,0.2); opacity: 1; border-left: 4px solid #ffffff; font-weight: 600; color: white; }
        .user-section { position: absolute; bottom: 0; width: 100%; padding: 1.5rem; background-color: rgba(0,0,0,0.15); border-top: 1px solid rgba(255,255,255,0.1); }
        .user-name { font-weight: 600; font-size: 0.9rem; }
        .user-role { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 1px; color: #d1a3e6; }
        #content { margin-left: 280px; min-height: 100vh; padding: 2rem; }
        .top-header { background: #ffffff; padding: 1rem 2rem; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.03); margin-bottom: 2rem; display: flex; justify-content: space-between; align-items: center; }
        .btn-ieeq { background-color: #6B2D8B; color: white; transition: all 0.3s; }
        .btn-ieeq:hover { background-color: #4a1f61; color: white; transform: translateY(-2px); box-shadow: 0 4px 10px rgba(107,45,139,0.3); }
        .bg-ieeq-purple { background-color: #6B2D8B !important; color: white; }
        .table-hover tbody tr:hover { background-color: #f8f9fa; }

        /* Buscador personalizado */
        .search-box { position: relative; }
        .search-box .form-control { border-radius: 50px; padding-left: 2.8rem; border: 1px solid #dee2e6; transition: all 0.3s; }
        .search-box .form-control:focus { border-color: #6B2D8B; box-shadow: 0 0 0 0.25rem rgba(107,45,139,0.15); }
        .search-box .search-icon { position: absolute; left: 1rem; top: 50%; transform: translateY(-50%); color: #9b6db5; }

        /* Responsive Sidebar */
        \@media (max-width: 768px) {
            #sidebar { transform: translateX(-100%); transition: transform 0.3s ease-in-out; }
            #sidebar.active { transform: translateX(0); }
            #content { margin-left: 0; padding: 1rem; transition: margin-left 0.3s ease-in-out; }
            .mobile-overlay { display: none; position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; background: rgba(0,0,0,0.5); z-index: 999; }
            .mobile-overlay.active { display: block; }
        }
        \@media (min-width: 769px) {
            #sidebar { transform: translateX(0); transition: transform 0.3s ease-in-out; }
            #content { margin-left: 280px; transition: margin-left 0.3s ease-in-out; }
            .mobile-overlay { display: none !important; }
        }

        /* DataTables Custom Styling */
        .dataTables_wrapper { padding: 1.5rem; }
        .dataTables_length select { border-radius: 8px; border: 1px solid #dee2e6; padding: 0.375rem 2.25rem 0.375rem 0.75rem; margin-left: 0.5rem; margin-right: 0.5rem; }
        /* Ocultar buscador nativo de DataTables - usamos el personalizado */
        .dataTables_filter { display: none !important; }
        .dataTables_filter input:focus, .dataTables_length select:focus { border-color: #6B2D8B; box-shadow: 0 0 0 0.25rem rgba(107,45,139,0.25); outline: none; }
        .page-item.active .page-link { background-color: #6B2D8B !important; border-color: #6B2D8B !important; color: white !important; }
        .page-link { color: #6B2D8B; }
        .page-link:hover { color: #4a1f61; }
        table.dataTable { margin-top: 0 !important; margin-bottom: 0 !important; }
        .table > :not(caption) > * > * { padding: 1rem 0.5rem; }
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
                <a href="gestion_usuarios.pl" class="nav-link active"><i class="bi bi-people me-2"></i>Gestión de Usuarios</a>
            </li>
            <li class="nav-item"><a href="#" class="nav-link"><i class="bi bi-person-plus me-2"></i>Registrar Persona</a></li>
            <li class="nav-item"><a href="#" class="nav-link"><i class="bi bi-check2-square me-2"></i>Validación</a></li>
            <li class="nav-item"><a href="#" class="nav-link"><i class="bi bi-file-earmark-bar-graph me-2"></i>Reportes</a></li>
        </ul>
        <div class="user-section">
            <div class="d-flex align-items-center mb-3">
                <div class="flex-shrink-0">
                    <div class="bg-white text-purple rounded-circle d-flex align-items-center justify-content-center fw-bold" style="width: 40px; height: 40px; color: #6B2D8B;">
                        <i class="bi bi-person-fill fs-5"></i>
                    </div>
                </div>
                <div class="flex-grow-1 ms-3">
                    <div class="user-name">$nombre_completo</div>
                    <div class="user-role">administrador</div>
                </div>
            </div>
            <button type="button" class="btn btn-outline-light btn-sm w-100 d-flex justify-content-center align-items-center" data-bs-toggle="modal" data-bs-target="#logoutModal">
                <i class="bi bi-box-arrow-right me-2"></i>Cerrar Sesión
            </button>
        </div>
    </nav>

    <!-- Main Content -->
    <div id="content">
        <div class="top-header">
            <div class="d-flex align-items-center">
                <button class="btn btn-light d-md-none me-3 shadow-sm" id="sidebarToggle">
                    <i class="bi bi-list fs-4"></i>
                </button>
                <h4 class="mb-0 text-dark fw-bold">Gestión de Usuarios</h4>
            </div>
            <div class="text-muted d-none d-md-block">Instituto Electoral del Estado de Querétaro</div>
        </div>

        <div class="card border-0 shadow-sm rounded-4">
            <div class="card-header bg-white p-4 border-0 border-bottom">
                <div class="d-flex flex-wrap justify-content-between align-items-center gap-3">
                    <div>
                        <h5 class="mb-0 fw-bold text-dark">Usuarios del Sistema</h5>
                        <small class="text-muted">Administra los accesos al sistema IEEQ</small>
                    </div>
                    <div class="d-flex align-items-center gap-3 flex-wrap">
                        <!-- Buscador personalizado que filtra el DataTable -->
                        <div class="search-box" style="min-width: 260px;">
                            <i class="bi bi-search search-icon"></i>
                            <input type="text" id="buscadorTabla" class="form-control" placeholder="Buscar usuario, correo, rol...">
                        </div>
                        <button class="btn btn-ieeq rounded-pill px-4" data-bs-toggle="modal" data-bs-target="#modalCrear">
                            <i class="bi bi-plus-lg me-2"></i>Nuevo Usuario
                        </button>
                    </div>
                </div>
            </div>
            <div class="card-body p-0">
                <div class="table-responsive" style="overflow-x: auto;">
                    <table id="usuariosTable" class="table table-hover align-middle mb-0 w-100" style="font-size: 0.95rem;">
                        <thead>
                            <tr class="bg-ieeq-purple text-white">
                                <th class="ps-4 border-0 py-3 fw-semibold rounded-top-start" style="width: 5%;">ID</th>
                                <th class="border-0 py-3 fw-semibold" style="width: 30%;">Nombre Completo</th>
                                <th class="border-0 py-3 fw-semibold" style="width: 20%;">Username</th>
                                <th class="border-0 py-3 fw-semibold" style="width: 15%;">Rol</th>
                                <th class="border-0 py-3 fw-semibold" style="width: 15%;">Estatus</th>
                                <th class="pe-4 border-0 py-3 fw-semibold rounded-top-end text-center" style="width: 15%;">Acciones</th>
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

    <!-- Modal Crear -->
    <div class="modal fade" id="modalCrear" tabindex="-1">
        <div class="modal-dialog modal-lg">
            <div class="modal-content border-0 shadow">
                <div class="modal-header border-bottom-0 bg-light">
                    <h5 class="modal-title fw-bold" style="color: #6B2D8B;">Crear Nuevo Usuario</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <form method="POST" id="formCrearUsuario" class="needs-validation" novalidate>
                    <div class="modal-body p-4">
                        <input type="hidden" name="accion" value="crear">
                        
                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Nombre Completo</label>
                                <input type="text" class="form-control" name="nombre_completo" required placeholder="Ej. Juan Pérez">
                                <div class="invalid-feedback">Ingresa el nombre completo.</div>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Username</label>
                                <input type="text" class="form-control" name="username" required placeholder="Ej. juan.perez">
                                <div class="invalid-feedback">Ingresa un nombre de usuario.</div>
                            </div>
                        </div>

                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Correo Electrónico</label>
                                <input type="email" class="form-control" name="correo_electronico" id="crear_correo" required placeholder="Ej. correo\@dominio.com">
                                <div class="invalid-feedback">Ingresa un correo válido.</div>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Teléfono móvil</label>
                                <input type="tel" class="form-control" name="telefono_movil" id="crear_tel" required maxlength="15" placeholder="Ej. 4421234567">
                                <div class="invalid-feedback">Ingresa el teléfono móvil.</div>
                            </div>
                        </div>

                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">CURP</label>
                                <input type="text" class="form-control" name="curp" id="crear_curp" required maxlength="18" style="text-transform: uppercase;" placeholder="18 caracteres alfanuméricos" pattern="[A-Z0-9]{18}">
                                <div class="invalid-feedback">La CURP debe tener 18 caracteres en mayúsculas.</div>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Clave de elector</label>
                                <input type="text" class="form-control" name="clave_elector" id="crear_clave" required maxlength="20" placeholder="Máximo 20 caracteres">
                                <div class="invalid-feedback">Ingresa la clave de elector.</div>
                            </div>
                        </div>

                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Contraseña</label>
                                <input type="password" class="form-control" name="password" id="crear_pass" required onkeyup="checkStrength(this.value, 'crear')">
                                <div class="invalid-feedback">Crea una contraseña.</div>
                                <div class="progress mt-2" style="height: 5px;">
                                    <div id="passStrength_crear" class="progress-bar bg-danger" role="progressbar" style="width: 0%"></div>
                                </div>
                                <small id="passText_crear" class="text-muted" style="font-size: 0.75rem;">Fortaleza de contraseña</small>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Confirmar Contraseña</label>
                                <input type="password" class="form-control" id="crear_pass_confirm" required placeholder="Repite la contraseña">
                                <div class="invalid-feedback">Confirma la contraseña.</div>
                            </div>
                        </div>

                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Tipo de Usuario</label>
                                <select class="form-select" name="rol" required>
                                    <option value="">Selecciona un tipo...</option>
                                    <option value="administrador">Administrador del Sistema</option>
                                    <option value="operador">Funcionariado del IEEQ</option>
                                    <option value="validador">Integrante de la Organización</option>
                                    <option value="lectura">Solo Lectura</option>
                                </select>
                                <div class="invalid-feedback">Selecciona el tipo de usuario.</div>
                            </div>
                        </div>
                        
                        <div class="form-check form-switch p-3 bg-light rounded-3 mt-2">
                            <input class="form-check-input ms-0 mt-1 me-2" type="checkbox" name="activo" id="checkActivoCrear" checked style="transform: scale(1.3);">
                            <label class="form-check-label fw-semibold ms-2" for="checkActivoCrear">Habilitar cuenta inmediatamente</label>
                        </div>
                    </div>
                    <div class="modal-footer border-top-0 bg-light">
                        <button type="button" class="btn btn-link text-secondary text-decoration-none" data-bs-dismiss="modal">Cancelar</button>
                        <button type="submit" class="btn btn-ieeq rounded-pill px-4">Guardar Usuario</button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <!-- Modal Editar -->
    <div class="modal fade" id="modalEditar" tabindex="-1">
        <div class="modal-dialog modal-lg">
            <div class="modal-content border-0 shadow">
                <div class="modal-header border-bottom-0 bg-light">
                    <h5 class="modal-title fw-bold" style="color: #6B2D8B;">Modificar Usuario</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <form method="POST" id="formEditarUsuario" class="needs-validation" novalidate>
                    <div class="modal-body p-4">
                        <input type="hidden" name="accion" value="editar">
                        <input type="hidden" name="id_usuario" id="edit_id">
                        
                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Nombre Completo</label>
                                <input type="text" class="form-control" name="nombre_completo" id="edit_nombre" required>
                                <div class="invalid-feedback">Ingresa el nombre completo.</div>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Username</label>
                                <input type="text" class="form-control" name="username" id="edit_username" required>
                                <div class="invalid-feedback">Ingresa un nombre de usuario.</div>
                            </div>
                        </div>

                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Correo Electrónico</label>
                                <input type="email" class="form-control" name="correo_electronico" id="edit_correo" required placeholder="Ej. correo\@dominio.com">
                                <div class="invalid-feedback">Ingresa un correo válido.</div>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Teléfono móvil</label>
                                <input type="tel" class="form-control" name="telefono_movil" id="edit_tel" required maxlength="15" placeholder="Ej. 4421234567">
                                <div class="invalid-feedback">Ingresa el teléfono móvil.</div>
                            </div>
                        </div>

                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">CURP</label>
                                <input type="text" class="form-control" name="curp" id="edit_curp" required maxlength="18" style="text-transform: uppercase;" placeholder="18 caracteres alfanuméricos" pattern="[A-Z0-9]{18}">
                                <div class="invalid-feedback">La CURP debe tener 18 caracteres en mayúsculas.</div>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Clave de elector</label>
                                <input type="text" class="form-control" name="clave_elector" id="edit_clave" required maxlength="20" placeholder="Máximo 20 caracteres">
                                <div class="invalid-feedback">Ingresa la clave de elector.</div>
                            </div>
                        </div>

                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold text-muted">Nueva Contraseña <small>(opcional)</small></label>
                                <input type="password" class="form-control" name="password" id="edit_pass" placeholder="Dejar en blanco para conservar" onkeyup="checkStrength(this.value, 'editar')">
                                <div class="progress mt-2" style="height: 5px;">
                                    <div id="passStrength_editar" class="progress-bar bg-danger" role="progressbar" style="width: 0%"></div>
                                </div>
                                <small id="passText_editar" class="text-muted" style="font-size: 0.75rem;">Fortaleza de contraseña</small>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold text-muted">Confirmar Contraseña <small>(opcional)</small></label>
                                <input type="password" class="form-control" id="edit_pass_confirm" placeholder="Repite si cambiaste la contraseña">
                            </div>
                        </div>

                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold">Tipo de Usuario</label>
                                <select class="form-select" name="rol" id="edit_rol" required>
                                    <option value="administrador">Administrador del Sistema</option>
                                    <option value="operador">Funcionariado del IEEQ</option>
                                    <option value="validador">Integrante de la Organización</option>
                                    <option value="lectura">Solo Lectura</option>
                                </select>
                            </div>
                        </div>

                        <div class="form-check form-switch p-3 bg-light rounded-3 mt-2">
                            <input class="form-check-input ms-0 mt-1 me-2" type="checkbox" name="activo" id="edit_activo" style="transform: scale(1.3);">
                            <label class="form-check-label fw-semibold ms-2" for="edit_activo">Cuenta Activa</label>
                        </div>
                    </div>
                    <div class="modal-footer border-top-0 bg-light">
                        <button type="button" class="btn btn-link text-secondary text-decoration-none" data-bs-dismiss="modal">Cancelar</button>
                        <button type="submit" class="btn btn-ieeq rounded-pill px-4">Actualizar Datos</button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <!-- Logout Modal -->
    <div class="modal fade" id="logoutModal" tabindex="-1">
        <div class="modal-dialog modal-dialog-centered">
            <div class="modal-content border-0 shadow">
                <div class="modal-header border-bottom-0 bg-light">
                    <h5 class="modal-title fw-bold" style="color: #6B2D8B;">Cerrar Sesión</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <div class="modal-body p-4 text-center">
                    <p class="mb-0 fs-5">¿Estás seguro que deseas cerrar sesión?</p>
                </div>
                <div class="modal-footer border-top-0 bg-light justify-content-center">
                    <button type="button" class="btn btn-outline-secondary px-4 rounded-pill" data-bs-dismiss="modal">Cancelar</button>
                    <a href="dashboard.pl?logout=1" class="btn text-white px-4 rounded-pill" style="background-color: #6B2D8B;">Sí, cerrar sesión</a>
                </div>
            </div>
        </div>
    </div>
HTML

print <<'JS_HTML';
    <script src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/sweetalert2\@11/dist/sweetalert2.all.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.6/js/dataTables.bootstrap5.min.js"></script>
    <script src="https://cdn.datatables.net/responsive/2.5.0/js/dataTables.responsive.min.js"></script>
    <script src="https://cdn.datatables.net/responsive/2.5.0/js/responsive.bootstrap5.min.js"></script>
    <script>
        // ===== HANDLER EDITAR =====
        // Se registra ANTES del ready de DataTables para garantizar
        // que funcione incluso cuando DataTables recrea las filas en paginacion
        $(document).on('click', '.btn-editar', function(e) {
            e.preventDefault();
            var btn = $(this);
            // Leer los datos del usuario desde los atributos data-* del boton
            document.getElementById('edit_id').value       = btn.attr('data-id');
            document.getElementById('edit_username').value = btn.attr('data-username');
            document.getElementById('edit_nombre').value   = btn.attr('data-nombre');
            document.getElementById('edit_correo').value   = btn.attr('data-correo');
            document.getElementById('edit_curp').value     = btn.attr('data-curp');
            document.getElementById('edit_clave').value    = btn.attr('data-clave');
            document.getElementById('edit_tel').value      = btn.attr('data-tel');
            document.getElementById('edit_rol').value      = btn.attr('data-rol');
            document.getElementById('edit_activo').checked = (btn.attr('data-activo') === '1');
            // Limpiar campos de contrasena
            document.getElementById('edit_pass').value         = '';
            document.getElementById('edit_pass_confirm').value = '';
            document.getElementById('passStrength_editar').style.width = '0%';
            document.getElementById('passText_editar').innerText = 'Fortaleza de contrasena';
            // Abrir el modal
            var modal = new bootstrap.Modal(document.getElementById('modalEditar'));
            modal.show();
        });

        $(document).ready(function() {
            // ===== DATATABLES =====
            var tabla = $('#usuariosTable').DataTable({
                "responsive": true,
                "language": {
                    "url": "//cdn.datatables.net/plug-ins/1.13.6/i18n/es-ES.json"
                },
                "dom": "<'row mb-3 align-items-center'<'col-sm-12 col-md-6 d-flex align-items-center justify-content-start'l><'col-sm-12 col-md-6 d-flex align-items-center justify-content-end'f>>" +
                       "<'row'<'col-sm-12'tr>>" +
                       "<'row mt-3 align-items-center'<'col-sm-12 col-md-5'i><'col-sm-12 col-md-7'p>>",
                "pageLength": 10,
                "ordering": true,
                "columnDefs": [
                    { "orderable": false, "targets": -1 }
                ]
            });

            // ===== BUSCADOR PERSONALIZADO =====
            $('#buscadorTabla').on('keyup input', function() {
                tabla.search($(this).val()).draw();
            });

            // ===== SIDEBAR MOVIL =====
            $('#sidebarToggle').on('click', function() {
                $('#sidebar').addClass('active');
                $('.mobile-overlay').addClass('active');
            });
            $('.mobile-overlay').on('click', function() {
                $('#sidebar').removeClass('active');
                $('.mobile-overlay').removeClass('active');
            });
        });

        // ===== VALIDACION BOOTSTRAP (solo forms con clase needs-validation, no toggle_activo) =====
        document.querySelectorAll('.needs-validation').forEach(function(form) {
            form.addEventListener('submit', function(event) {
                if (!form.checkValidity()) {
                    event.preventDefault();
                    event.stopPropagation();
                }
                form.classList.add('was-validated');
            }, false);
        });

        // ===== FORTALEZA DE CONTRASENA =====
        // Debil: < 6 caracteres (rojo)
        // Media: 6-9 caracteres (amarillo)
        // Fuerte: 10+ con letras y numeros (verde)
        function checkStrength(password, tipo) {
            var bar  = document.getElementById('passStrength_' + tipo);
            var text = document.getElementById('passText_' + tipo);
            var len  = password.length;
            if (len === 0) {
                bar.style.width = '0%'; bar.className = 'progress-bar bg-danger';
                text.innerText = 'Vacia';
            } else if (len < 6) {
                bar.style.width = '33%'; bar.className = 'progress-bar bg-danger';
                text.innerText = 'Debil';
            } else if (len < 10) {
                bar.style.width = '66%'; bar.className = 'progress-bar bg-warning';
                text.innerText = 'Media';
            } else {
                var tieneLetras = /[a-zA-Z]/.test(password);
                var tieneNumeros = /[0-9]/.test(password);
                if (tieneLetras && tieneNumeros) {
                    bar.style.width = '100%'; bar.className = 'progress-bar bg-success';
                    text.innerText = 'Fuerte';
                } else {
                    bar.style.width = '66%'; bar.className = 'progress-bar bg-warning';
                    text.innerText = 'Media';
                }
            }
        }

        // ===== TOAST SWEETALERT2 =====
        function mostrarToast(icon, title) {
            const Toast = Swal.mixin({
                toast: true, position: 'bottom-end',
                showConfirmButton: false, timer: 3000, timerProgressBar: true
            });
            Toast.fire({ icon: icon, title: title });
        }

        // ===== VALIDACION FORMULARIO CREAR =====
        document.getElementById('formCrearUsuario').addEventListener('submit', function(e) {
            var correo = document.getElementById('crear_correo').value.trim();
            var curp   = document.getElementById('crear_curp').value.trim().toUpperCase();
            var pass   = document.getElementById('crear_pass').value;
            var passC  = document.getElementById('crear_pass_confirm').value;
            if (correo.indexOf('@') === -1 || correo.indexOf('.') === -1 || correo.length < 6) {
                e.preventDefault(); mostrarToast('error', 'El correo no tiene formato valido.'); return;
            }
            if (!/^[A-Z0-9]{18}$/.test(curp)) {
                e.preventDefault(); mostrarToast('error', 'La CURP debe tener 18 caracteres en mayusculas.'); return;
            }
            if (pass !== passC) {
                e.preventDefault(); mostrarToast('error', 'Las contrasenas no coinciden.'); return;
            }
        });

        // ===== VALIDACION FORMULARIO EDITAR =====
        document.getElementById('formEditarUsuario').addEventListener('submit', function(e) {
            var correo = document.getElementById('edit_correo').value.trim();
            var curp   = document.getElementById('edit_curp').value.trim().toUpperCase();
            var pass   = document.getElementById('edit_pass').value;
            var passC  = document.getElementById('edit_pass_confirm').value;
            if (correo.indexOf('@') === -1 || correo.indexOf('.') === -1 || correo.length < 6) {
                e.preventDefault(); mostrarToast('error', 'El correo no tiene formato valido.'); return;
            }
            if (!/^[A-Z0-9]{18}$/.test(curp)) {
                e.preventDefault(); mostrarToast('error', 'La CURP debe tener 18 caracteres en mayusculas.'); return;
            }
            if (pass && pass !== passC) {
                e.preventDefault(); mostrarToast('error', 'Las contrasenas no coinciden.'); return;
            }
        });
    </script>
JS_HTML
print $swal_script;
print <<'END_HTML';
</body>
</html>
END_HTML
