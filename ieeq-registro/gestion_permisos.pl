#!C:\xampp\perl\bin\perl.exe
use strict;
use warnings;
use CGI;
use CGI::Session;
use JSON;
use FindBin;
require "$FindBin::Bin/db.pl";

my $cgi = CGI->new;
my $session = CGI::Session->new(undef, $cgi, {Directory => "$FindBin::Bin/.sesiones"});

my $rol = $session->param('rol') || '';
my $nombre_completo = $session->param('nombre_completo') || '';

if ($rol ne 'administrador') {
    print $cgi->redirect(-uri => 'dashboard.pl');
    exit;
}

my $accion = $cgi->param('accion') || '';

# ==========================================
# ENDPOINT: get_permisos
# ==========================================
if ($accion eq 'get_permisos') {
    my $id_usuario = $cgi->param('id_usuario');
    if ($id_usuario) {
        my @permisos = execute_query_list("SELECT id_opcion, puede_ver, puede_editar FROM permisos_usuario WHERE id_usuario = ?", $id_usuario);
        my %perm_hash;
        for my $p (@permisos) {
            $perm_hash{$p->{id_opcion}} = {
                puede_ver    => $p->{puede_ver} ? 1 : 0,
                puede_editar => $p->{puede_editar} ? 1 : 0
            };
        }
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 1, permisos => \%perm_hash });
        exit;
    }
    print $cgi->header(-type => 'application/json', -charset => 'utf-8');
    print encode_json({ success => 0, message => 'ID de usuario no proporcionado' });
    exit;
}
# ==========================================
# ENDPOINT: save_permisos
# ==========================================
elsif ($accion eq 'save_permisos') {
    my $id_usuario = $cgi->param('id_usuario');
    my $permisos_json = $cgi->param('permisos_json');
    
    if ($id_usuario && $permisos_json) {
        my $permisos;
        eval {
            $permisos = decode_json($permisos_json);
        };
        if ($@) {
            print $cgi->header(-type => 'application/json', -charset => 'utf-8');
            print encode_json({ success => 0, message => 'JSON inválido' });
            exit;
        }
        
        my $errors = 0;
        my @existentes = execute_query_list("SELECT id_opcion FROM permisos_usuario WHERE id_usuario = ?", $id_usuario);
        my %tiene_opcion;
        $tiene_opcion{$_->{id_opcion}} = 1 for @existentes;
        
        for my $p (@$permisos) {
            my $id_op = $p->{id_opcion};
            my $ver = $p->{puede_ver} ? 1 : 0;
            my $editar = $p->{puede_editar} ? 1 : 0;
            
            if ($tiene_opcion{$id_op}) {
                my $sql = "UPDATE permisos_usuario SET puede_ver=?, puede_editar=? WHERE id_usuario=? AND id_opcion=?";
                $errors++ unless execute_query_write($sql, $ver, $editar, $id_usuario, $id_op);
            } else {
                my $sql = "INSERT INTO permisos_usuario (id_usuario, id_opcion, puede_ver, puede_editar) VALUES (?, ?, ?, ?)";
                $errors++ unless execute_query_write($sql, $id_usuario, $id_op, $ver, $editar);
            }
        }
        
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        if ($errors == 0) {
            print encode_json({ success => 1, message => 'Permisos actualizados correctamente' });
        } else {
            print encode_json({ success => 0, message => "Se guardaron con $errors errores" });
        }
        exit;
    }
    print $cgi->header(-type => 'application/json', -charset => 'utf-8');
    print encode_json({ success => 0, message => 'Faltan parámetros requeridos' });
    exit;
}

# ==========================================
# RENDER HTML
# ==========================================
my @todos_usuarios = execute_query_list("SELECT id_usuario, nombre_completo, correo_electronico, rol FROM usuarios ORDER BY nombre_completo ASC");
my $usuarios_json = encode_json(\@todos_usuarios);
my $usuarios_json_escaped = $usuarios_json;
$usuarios_json_escaped =~ s/&/&amp;/g;
$usuarios_json_escaped =~ s/"/&quot;/g;
$usuarios_json_escaped =~ s/'/&#39;/g;
$usuarios_json_escaped =~ s/</&lt;/g;
$usuarios_json_escaped =~ s/>/&gt;/g;

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
    <title>Gestión de Permisos - IEEQ</title>
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

        /* Main Content Styling */
        #content { margin-left: 280px; min-height: 100vh; padding: 2rem; transition: all 0.3s; }
        .top-header {
            background: #ffffff; padding: 1rem 2rem; border-radius: 12px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.03); margin-bottom: 2rem;
            display: flex; justify-content: space-between; align-items: center;
        }
        .card-ieeq { border: none; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); }
        .card-ieeq .card-header { background-color: #fff; border-bottom: 1px solid #f0f0f0; padding: 1.5rem; border-radius: 12px 12px 0 0; }
        .form-select { border-radius: 20px; padding: 0.6rem 1.2rem; border: 1px solid #6B2D8B; }
        .form-select:focus { box-shadow: 0 0 0 0.25rem rgba(107, 45, 139, 0.25); border-color: #6B2D8B; }
        .btn-ieeq { background-color: #6B2D8B; color: white; border: none; }
        .btn-ieeq:hover { background-color: #4a1f61; color: white; }
        
        .avatar-circle { width: 60px; height: 60px; border-radius: 50%; background-color: #e9ecef; color: #6B2D8B; display: flex; align-items: center; justify-content: center; font-size: 1.5rem; font-weight: bold; margin-bottom: 1rem; }
        
        /* Table Styles */
        .table-permissions th { font-weight: 600; color: #495057; border-bottom: 2px solid #dee2e6; }
        .table-permissions td { vertical-align: middle; }
        .section-row td { background-color: #f8f9fa; font-weight: 600; color: #6B2D8B; letter-spacing: 0.5px; }
        
        /* Switch Styles */
        .form-switch .form-check-input { width: 3em; height: 1.5em; cursor: pointer; }
        .form-switch .form-check-input:checked { background-color: #6B2D8B; border-color: #6B2D8B; }
        
        /* Levels Panel */
        .level-item { display: flex; align-items: center; margin-bottom: 1.2rem; }
        .level-icon { width: 40px; height: 40px; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin-right: 1rem; color: white; }
        .level-icon.write { background-color: #20c997; }
        .level-icon.read { background-color: #ffc107; }
        .level-icon.none { background-color: #dc3545; }
        
        /* Loader Overlay */
        .loader-overlay {
            position: absolute; top: 0; left: 0; right: 0; bottom: 0;
            background: rgba(255,255,255,0.8); z-index: 10;
            display: none; align-items: center; justify-content: center; flex-direction: column;
            border-radius: 12px;
        }
        .empty-state {
            display: flex; flex-direction: column; align-items: center; justify-content: center;
            height: 100%; min-height: 400px; color: #6c757d; text-align: center;
        }
        .empty-state i { font-size: 4rem; color: #e9ecef; margin-bottom: 1rem; }
        
        /* Search results styling */
        .user-search-item {
            display: flex;
            align-items: center;
            padding: 0.75rem 1rem;
            border-bottom: 1px solid #f0f0f0;
            cursor: pointer;
            transition: all 0.2s ease;
        }
        .user-search-item:last-child {
            border-bottom: none;
        }
        .user-search-item:hover {
            background-color: #f8f0fc;
        }
        .avatar-initials-small {
            width: 36px;
            height: 36px;
            border-radius: 50%;
            background-color: #f3e8f8;
            color: #6B2D8B;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 0.85rem;
            font-weight: 700;
        }
    </style>
</head>
<body>

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
                <a href="gestion_permisos.pl" class="nav-link active"><i class="bi bi-shield-lock me-2"></i>Gestión de Permisos</a>
            </li>
            <li class="nav-item">
                <a href="auditoria.pl" class="nav-link"><i class="bi bi-journal-text me-2"></i>Auditoría</a>
            </li>
        </ul>
        <div class="user-section">
            <div class="d-flex align-items-center mb-3">
                <div class="flex-shrink-0">
                    <div class="bg-white text-purple rounded-circle d-flex align-items-center justify-content-center fw-bold" style="width: 40px; height: 40px; color: #6B2D8B;">
                        <i class="bi bi-person-fill fs-5"></i>
                    </div>
                </div>
                <div class="flex-grow-1 ms-3" style="min-width: 0;">
                    <div class="user-name">$nombre_completo</div>
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
        <div class="top-header">
            <div>
                <h4 class="mb-0 text-dark fw-bold">Gestión de Permisos</h4>
                <p class="text-muted mb-0 small">Configure los niveles de acceso para cada usuario del sistema</p>
            </div>
            <div class="text-muted d-none d-md-block">
                Instituto Electoral del Estado de Querétaro
            </div>
        </div>

        <div class="row">
            <!-- Left Column: User Selection -->
            <div class="col-lg-4 mb-4">
                <div class="card card-ieeq mb-4">
                    <div class="card-body p-4">
                        <h6 class="fw-bold mb-3">Seleccionar Usuario</h6>
                        <div class="position-relative">
                            <div class="input-group">
                                <span class="input-group-text bg-white border-end-0" style="border: 1px solid #6B2D8B; border-radius: 20px 0 0 20px;">
                                    <i class="bi bi-search" style="color: #6B2D8B;"></i>
                                </span>
                                <input type="text" class="form-control border-start-0" id="searchUsuario" placeholder="Buscar usuario por nombre o correo..." style="border: 1px solid #6B2D8B; border-radius: 0 20px 20px 0; padding: 0.6rem 1.2rem;" autocomplete="off">
                            </div>
                            
                            <input type="hidden" id="selectUsuario" value="">
                            
                            <!-- Resultados de Búsqueda -->
                            <div id="searchResultsList" class="position-absolute w-100 bg-white border rounded shadow-lg d-none" style="z-index: 1050; max-height: 280px; overflow-y: auto; top: 100%; margin-top: 5px;">
                            </div>
                        </div>
                        
                        <!-- Contenedor oculto con los datos en formato JSON -->
                        <div id="usersData" data-json="$usuarios_json_escaped" class="d-none"></div>
                        
                        <div id="userInfoPanel" class="mt-4 text-center d-none">
                            <div class="d-flex justify-content-center">
                                <div class="avatar-circle" id="userAvatar">U</div>
                            </div>
                            <h5 class="fw-bold mb-1" id="userFullName">Nombre del Usuario</h5>
                            <p class="text-muted mb-2 small" id="userEmail">correo\@ieeq.mx</p>
                            <span class="badge bg-purple" style="background-color: #6B2D8B;" id="userRoleBadge">Rol</span>
                        </div>
                    </div>
                </div>

                <div class="card card-ieeq">
                    <div class="card-body p-4">
                        <h6 class="fw-bold mb-4">Niveles de Permiso</h6>
                        
                        <div class="level-item">
                            <div class="level-icon write"><i class="bi bi-unlock-fill"></i></div>
                            <div>
                                <div class="fw-bold small">ESCRITURA</div>
                                <div class="text-muted small">Lectura y modificación</div>
                            </div>
                        </div>
                        
                        <div class="level-item">
                            <div class="level-icon read"><i class="bi bi-lock-fill"></i></div>
                            <div>
                                <div class="fw-bold small">LECTURA</div>
                                <div class="text-muted small">Solo consulta</div>
                            </div>
                        </div>
                        
                        <div class="level-item mb-0">
                            <div class="level-icon none"><i class="bi bi-slash-circle"></i></div>
                            <div>
                                <div class="fw-bold small">NINGUNO</div>
                                <div class="text-muted small">Sin acceso</div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Right Column: Permission Matrix -->
            <div class="col-lg-8">
                <div class="card card-ieeq position-relative h-100" style="min-height: 500px;">
                    
                    <!-- Empty State -->
                    <div id="emptyState" class="empty-state">
                        <div class="avatar-circle mb-3 mx-auto" style="width: 80px; height: 80px; background-color: #f3e8f8;"><i class="bi bi-lock-fill text-purple" style="color: #6B2D8B;"></i></div>
                        <h5 class="fw-bold">Seleccione un usuario</h5>
                        <p class="text-muted">Para configurar sus permisos de acceso al sistema</p>
                    </div>

                    <!-- Loader -->
                    <div id="loaderOverlay" class="loader-overlay">
                        <div class="spinner-border" style="color: #6B2D8B; width: 3rem; height: 3rem;" role="status"></div>
                        <div class="mt-3 fw-semibold text-muted">Cargando permisos...</div>
                    </div>

                    <!-- Permissions Matrix -->
                    <div id="permissionsPanel" class="d-none d-flex flex-column h-100">
                        <div class="card-body p-0 flex-grow-1">
                            <div class="table-responsive">
                                <table class="table table-permissions mb-0">
                                    <thead class="table-light">
                                        <tr>
                                            <th class="ps-4 py-3" style="width: 50%;">Opción del Sistema</th>
                                            <th class="text-center py-3">Lectura</th>
                                            <th class="text-center py-3">Escritura</th>
                                        </tr>
                                    </thead>
                                    <tbody id="permissionsTbody">
                                        
                                        <!-- ADMINISTRACIÓN -->
                                        <tr class="section-row"><td colspan="3" class="ps-4 py-2"><i class="bi bi-gear-fill me-2"></i>Administración</td></tr>
                                        <tr data-id="6">
                                            <td class="ps-5">Gestión de Usuarios</td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-read" type="checkbox" role="switch"></div></td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-write" type="checkbox" role="switch"></div></td>
                                        </tr>
                                        <tr data-id="7">
                                            <td class="ps-5">Gestión de Permisos</td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-read" type="checkbox" role="switch"></div></td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-write" type="checkbox" role="switch"></div></td>
                                        </tr>
                                        <tr data-id="8">
                                            <td class="ps-5">Auditoría</td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-read" type="checkbox" role="switch"></div></td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-write" type="checkbox" role="switch"></div></td>
                                        </tr>
                                        
                                        <!-- FUNCIONARIOS -->
                                        <tr class="section-row"><td colspan="3" class="ps-4 py-2"><i class="bi bi-person-badge-fill me-2"></i>Funcionarios</td></tr>
                                        <tr data-id="9">
                                            <td class="ps-5">Verificación de Afiliación</td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-read" type="checkbox" role="switch"></div></td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-write" type="checkbox" role="switch"></div></td>
                                        </tr>
                                        <tr data-id="10">
                                            <td class="ps-5">Verificación de Auxiliares</td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-read" type="checkbox" role="switch"></div></td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-write" type="checkbox" role="switch"></div></td>
                                        </tr>
                                        <tr data-id="11">
                                            <td class="ps-5">Consulta de Registros</td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-read" type="checkbox" role="switch"></div></td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-write" type="checkbox" role="switch"></div></td>
                                        </tr>
                                        <tr data-id="12">
                                            <td class="ps-5">Reportes</td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-read" type="checkbox" role="switch"></div></td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-write" type="checkbox" role="switch"></div></td>
                                        </tr>

                                        <!-- ORGANIZACIÓN -->
                                        <tr class="section-row"><td colspan="3" class="ps-4 py-2"><i class="bi bi-building me-2"></i>Organización</td></tr>
                                        <tr data-id="13">
                                            <td class="ps-5">Registro de Afiliados</td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-read" type="checkbox" role="switch"></div></td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-write" type="checkbox" role="switch"></div></td>
                                        </tr>
                                        <tr data-id="14">
                                            <td class="ps-5">Registro de Auxiliares</td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-read" type="checkbox" role="switch"></div></td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-write" type="checkbox" role="switch"></div></td>
                                        </tr>
                                        <tr data-id="15">
                                            <td class="ps-5">Consulta de Registros</td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-read" type="checkbox" role="switch"></div></td>
                                            <td class="text-center"><div class="form-check form-switch d-flex justify-content-center"><input class="form-check-input perm-write" type="checkbox" role="switch"></div></td>
                                        </tr>
                                        
                                    </tbody>
                                </table>
                            </div>
                        </div>
                        <div class="card-footer bg-white border-top p-4 d-flex justify-content-end">
                            <button class="btn btn-ieeq rounded-pill px-4" id="btnGuardar">
                                <i class="bi bi-save me-2"></i>Guardar Permisos
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Bootstrap JS -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            const selectUsuario = document.getElementById('selectUsuario');
            const searchUsuario = document.getElementById('searchUsuario');
            const searchResultsList = document.getElementById('searchResultsList');
            const emptyState = document.getElementById('emptyState');
            const permissionsPanel = document.getElementById('permissionsPanel');
            const loaderOverlay = document.getElementById('loaderOverlay');
            const userInfoPanel = document.getElementById('userInfoPanel');
            const btnGuardar = document.getElementById('btnGuardar');
            
            const usersDataEl = document.getElementById('usersData');
            const allUsers = JSON.parse(usersDataEl ? usersDataEl.getAttribute('data-json') : '[]');
            
            // Lógica de Toggles (Cascada Escritura -> Lectura)
            const rows = document.querySelectorAll('#permissionsTbody tr[data-id]');
            rows.forEach(row => {
                const readToggle = row.querySelector('.perm-read');
                const writeToggle = row.querySelector('.perm-write');
                
                if(readToggle && writeToggle) {
                    writeToggle.addEventListener('change', function() {
                        if(this.checked) {
                            readToggle.checked = true; // Escritura activa -> Lectura activa
                        }
                    });
                    
                    readToggle.addEventListener('change', function() {
                        if(!this.checked) {
                            writeToggle.checked = false; // Lectura inactiva -> Escritura inactiva
                        }
                    });
                }
            });

            // Renderizar resultados del buscador
            function renderResults(filteredUsers) {
                searchResultsList.innerHTML = '';
                if(filteredUsers.length === 0) {
                    searchResultsList.innerHTML = '<div class="p-3 text-center text-muted small">No se encontraron usuarios</div>';
                    return;
                }
                
                filteredUsers.forEach(user => {
                    const nombre = user.nombre_completo;
                    const words = nombre.split(' ').filter(w => w.length > 0);
                    let initials = words.length > 0 ? words[0].charAt(0).toUpperCase() : 'U';
                    if(words.length > 1) { initials += words[1].charAt(0).toUpperCase(); }
                    
                    let badgeClass = 'bg-secondary text-white';
                    let roleDisplay = 'ORGANIZACIÓN';
                    if (user.rol === 'administrador') {
                        badgeClass = '';
                        roleDisplay = 'ADMINISTRADOR';
                    } else if (user.rol === 'funcionario') {
                        badgeClass = 'bg-info text-dark';
                        roleDisplay = 'FUNCIONARIO';
                    }
                    
                    const badgeStyle = user.rol === 'administrador' ? 'background-color: #6B2D8B;' : '';
                    
                    const item = document.createElement('div');
                    item.className = 'user-search-item d-flex align-items-center';
                    item.innerHTML = 
                        '<div class="avatar-initials-small fw-bold me-3">' + initials + '</div>' +
                        '<div class="flex-grow-1" style="min-width: 0;">' +
                            '<div class="fw-bold text-dark text-truncate" style="font-size: 0.9rem;">' + nombre + '</div>' +
                            '<div class="text-muted text-truncate" style="font-size: 0.75rem;">' + (user.correo_electronico || '') + '</div>' +
                        '</div>' +
                        '<span class="badge rounded-pill ' + badgeClass + ' ms-2" style="' + badgeStyle + ' font-size: 0.65rem;">' + roleDisplay + '</span>';
                    
                    item.addEventListener('click', function() {
                        searchUsuario.value = nombre;
                        selectUsuario.value = user.id_usuario;
                        searchResultsList.classList.add('d-none');
                        // Disparar evento change para cargar los permisos
                        selectUsuario.dispatchEvent(new Event('change'));
                    });
                    
                    searchResultsList.appendChild(item);
                });
            }
            
            // Eventos del Input de Búsqueda
            searchUsuario.addEventListener('input', function() {
                const query = this.value.toLowerCase().trim();
                if(query === '') {
                    renderResults(allUsers);
                    searchResultsList.classList.remove('d-none');
                    return;
                }
                
                const filtered = allUsers.filter(u => {
                    const nombre = (u.nombre_completo || '').toLowerCase();
                    const correo = (u.correo_electronico || '').toLowerCase();
                    return nombre.includes(query) || correo.includes(query);
                });
                
                renderResults(filtered);
                searchResultsList.classList.remove('d-none');
            });
            
            searchUsuario.addEventListener('focus', function() {
                this.select();
                const query = this.value.toLowerCase().trim();
                const filtered = query === '' ? allUsers : allUsers.filter(u => {
                    const nombre = (u.nombre_completo || '').toLowerCase();
                    const correo = (u.correo_electronico || '').toLowerCase();
                    return nombre.includes(query) || correo.includes(query);
                });
                renderResults(filtered);
                searchResultsList.classList.remove('d-none');
            });
            
            // Cerrar la lista al hacer clic fuera
            document.addEventListener('click', function(e) {
                if(!searchUsuario.contains(e.target) && !searchResultsList.contains(e.target)) {
                    searchResultsList.classList.add('d-none');
                }
            });

            // Seleccionar usuario y cargar permisos
            selectUsuario.addEventListener('change', function() {
                const userId = this.value;
                if(!userId) return;
                
                // Actualizar Info del Usuario (Avatar y text)
                const user = allUsers.find(u => u.id_usuario == userId);
                if(!user) return;
                const nombre = user.nombre_completo;
                const rol = user.rol;
                const correo = user.correo_electronico || '';
                
                document.getElementById('userFullName').innerText = nombre;
                document.getElementById('userEmail').innerText = correo;
                document.getElementById('userRoleBadge').innerText = rol.toUpperCase();
                
                // Generar Avatar Initials
                const words = nombre.split(' ').filter(w => w.length > 0);
                let initials = words.length > 0 ? words[0].charAt(0).toUpperCase() : 'U';
                if(words.length > 1) { initials += words[1].charAt(0).toUpperCase(); }
                document.getElementById('userAvatar').innerText = initials;
                
                userInfoPanel.classList.remove('d-none');
                emptyState.classList.add('d-none');
                permissionsPanel.classList.add('d-none');
                loaderOverlay.style.display = 'flex';
                
                // Cargar Permisos via AJAX
                const formData = new FormData();
                formData.append('accion', 'get_permisos');
                formData.append('id_usuario', userId);
                
                fetch('gestion_permisos.pl', {
                    method: 'POST',
                    body: formData
                })
                .then(response => response.json())
                .then(data => {
                    if(data.success) {
                        // Limpiar todos los toggles
                        document.querySelectorAll('.perm-read, .perm-write').forEach(el => el.checked = false);
                        
                        // Llenar con la respuesta
                        const perms = data.permisos;
                        for(const id_op in perms) {
                            const row = document.querySelector(`tr[data-id="\${id_op}"]`);
                            if(row) {
                                const p = perms[id_op];
                                row.querySelector('.perm-read').checked = (p.puede_ver === 1);
                                row.querySelector('.perm-write').checked = (p.puede_editar === 1);
                            }
                        }
                        
                        loaderOverlay.style.display = 'none';
                        permissionsPanel.classList.remove('d-none');
                    } else {
                        throw new Error(data.message || 'Error al cargar permisos');
                    }
                })
                .catch(error => {
                    loaderOverlay.style.display = 'none';
                    emptyState.classList.remove('d-none');
                    Swal.fire({
                        icon: 'error',
                        title: 'Oops...',
                        text: error.message
                    });
                });
            });

            // Guardar Permisos
            btnGuardar.addEventListener('click', function() {
                const userId = selectUsuario.value;
                if(!userId) return;
                
                // Recopilar configuración de matriz
                const newPerms = [];
                const optionRows = document.querySelectorAll('#permissionsTbody tr[data-id]');
                optionRows.forEach(row => {
                    const idOp = row.getAttribute('data-id');
                    const isRead = row.querySelector('.perm-read').checked ? 1 : 0;
                    const isWrite = row.querySelector('.perm-write').checked ? 1 : 0;
                    
                    if(isRead || isWrite) {
                        newPerms.push({
                            id_opcion: idOp,
                            puede_ver: isRead,
                            puede_editar: isWrite
                        });
                    } else {
                        // Even if it's 0, we should send it to update existing records to 0
                        newPerms.push({
                            id_opcion: idOp,
                            puede_ver: 0,
                            puede_editar: 0
                        });
                    }
                });
                
                // Mostrar loading en botón
                const btnOriginalHTML = btnGuardar.innerHTML;
                btnGuardar.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Guardando...';
                btnGuardar.disabled = true;
                
                const formData = new FormData();
                formData.append('accion', 'save_permisos');
                formData.append('id_usuario', userId);
                formData.append('permisos_json', JSON.stringify(newPerms));
                
                fetch('gestion_permisos.pl', {
                    method: 'POST',
                    body: formData
                })
                .then(response => response.json())
                .then(data => {
                    btnGuardar.innerHTML = btnOriginalHTML;
                    btnGuardar.disabled = false;
                    
                    if(data.success) {
                        Swal.fire({
                            toast: true,
                            position: 'top-end',
                            icon: 'success',
                            title: 'Permisos actualizados con éxito',
                            showConfirmButton: false,
                            timer: 3000,
                            timerProgressBar: true
                        });
                    } else {
                        throw new Error(data.message || 'Error al guardar');
                    }
                })
                .catch(error => {
                    btnGuardar.innerHTML = btnOriginalHTML;
                    btnGuardar.disabled = false;
                    
                    Swal.fire({
                        icon: 'error',
                        title: 'Error',
                        text: error.message
                    });
                });
            });
        });
    </script>
</body>
</html>
HTML
