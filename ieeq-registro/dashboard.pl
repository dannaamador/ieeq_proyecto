#!C:\xampp\perl\bin\perl.exe
use strict;
use warnings;
use CGI;
use CGI::Session;
use FindBin;

my $cgi = CGI->new;

# Leer sesión desde el directorio local .sesiones
my $session = CGI::Session->new(undef, $cgi, {Directory=>"$FindBin::Bin/.sesiones"});

# Si no hay un id_usuario válido en la sesión, expulsar al login por seguridad
if (!$session->param('id_usuario')) {
    print $cgi->redirect(-uri => 'login.pl');
    exit;
}

# Manejo del logout manual desde el panel
# Elimina la sesión actual y redirige a la pantalla de autenticación
if ($cgi->param('logout')) {
    $session->delete();
    $session->flush();
    print $cgi->redirect(-uri => 'login.pl');
    exit;
}

# Recuperar datos del usuario
my $nombre_completo = $session->param('nombre_completo');
my $rol = $session->param('rol');

# Generar elementos dinámicos del menú lateral basándose en los permisos del rol
my $menu_html = '';

if ($rol eq 'administrador') {
    # El administrador tiene acceso total al sistema
    $menu_html .= <<'MENU';
        <li class="nav-item">
            <a class="nav-link text-white" href="gestion_usuarios.pl"><i class="bi bi-people me-2"></i>Gestión de Usuarios</a>
        </li>
        <li class="nav-item">
            <a class="nav-link text-white" href="#"><i class="bi bi-person-plus me-2"></i>Registrar Persona</a>
        </li>
        <li class="nav-item">
            <a class="nav-link text-white" href="#"><i class="bi bi-check2-square me-2"></i>Validación</a>
        </li>
        <li class="nav-item">
            <a class="nav-link text-white" href="#"><i class="bi bi-file-earmark-bar-graph me-2"></i>Reportes</a>
        </li>
MENU
} elsif ($rol eq 'operador') {
    # El operador solo puede registrar personas
    $menu_html .= <<'MENU';
        <li class="nav-item">
            <a class="nav-link text-white" href="#"><i class="bi bi-person-plus me-2"></i>Registrar Persona</a>
        </li>
MENU
} elsif ($rol eq 'validador') {
    # El validador aprueba registros y ve reportes
    $menu_html .= <<'MENU';
        <li class="nav-item">
            <a class="nav-link text-white" href="#"><i class="bi bi-check2-square me-2"></i>Validación</a>
        </li>
        <li class="nav-item">
            <a class="nav-link text-white" href="#"><i class="bi bi-file-earmark-bar-graph me-2"></i>Reportes</a>
        </li>
MENU
} elsif ($rol eq 'lectura') {
    # Rol de solo lectura para reportes
    $menu_html .= <<'MENU';
        <li class="nav-item">
            <a class="nav-link text-white" href="#"><i class="bi bi-file-earmark-bar-graph me-2"></i>Reportes</a>
        </li>
MENU
}

# Cabeceras anti-caché de alta seguridad
print $cgi->header(
    -type => 'text/html', 
    -charset => 'utf-8',
    -expires => 'now',
    -Cache_Control => 'no-store, no-cache, must-revalidate, max-age=0',
    -Pragma => 'no-cache'
);

# Usamos comillas dobles <<"HTML" para que Perl interpole las variables correctamente
print <<"HTML";
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard - IEEQ</title>
    <!-- Bootstrap 5 -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <!-- Bootstrap Icons -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons\@1.11.1/font/bootstrap-icons.css">
    <!-- Google Fonts -->
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght\@300;400;600;700&display=swap" rel="stylesheet">
    <style>
        body {
            font-family: 'Outfit', sans-serif;
            background-color: #f4f6f9;
            overflow-x: hidden;
        }
        /* Sidebar Styling */
        #sidebar {
            width: 280px;
            height: 100vh;
            background-color: #6B2D8B; /* Morado Institucional IEEQ */
            color: #ffffff;
            position: fixed;
            top: 0;
            left: 0;
            z-index: 1000;
            transition: all 0.3s;
            box-shadow: 4px 0 10px rgba(0,0,0,0.1);
        }
        .sidebar-header {
            padding: 2rem 1.5rem;
            text-align: center;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .sidebar-header h3 {
            font-weight: 700;
            letter-spacing: 2px;
            margin-bottom: 5px;
        }
        .sidebar-header p {
            font-size: 0.85rem;
            opacity: 0.8;
            margin: 0;
        }
        .nav-pills .nav-link {
            border-radius: 0;
            padding: 15px 20px;
            font-weight: 400;
            opacity: 0.85;
            transition: all 0.2s;
        }
        .nav-pills .nav-link:hover {
            opacity: 1;
            background-color: rgba(255,255,255,0.1);
            border-left: 4px solid #ffffff;
        }
        .nav-pills .nav-link.active {
            background-color: rgba(255,255,255,0.2);
            opacity: 1;
            border-left: 4px solid #ffffff;
            font-weight: 600;
        }
        
        /* User Profile Section in Sidebar */
        .user-section {
            position: absolute;
            bottom: 0;
            width: 100%;
            padding: 1.5rem;
            background-color: rgba(0,0,0,0.15);
            border-top: 1px solid rgba(255,255,255,0.1);
        }
        .user-name {
            font-weight: 600;
            font-size: 0.9rem;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            margin-bottom: 2px;
        }
        .user-role {
            font-size: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 1px;
            color: #d1a3e6;
        }

        /* Main Content Styling */
        #content {
            margin-left: 280px;
            min-height: 100vh;
            padding: 2rem;
            transition: all 0.3s;
        }
        .top-header {
            background: #ffffff;
            padding: 1rem 2rem;
            border-radius: 12px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.03);
            margin-bottom: 2rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        /* Mobile fixes */
        \@media (max-width: 768px) {
            #sidebar {
                transform: translateX(-100%);
            }
            #content {
                margin-left: 0;
            }
        }
    </style>
</head>
<body>

    <!-- Sidebar -->
    <nav id="sidebar">
        <div class="sidebar-header">
            <h3>IEEQ</h3>
            <p>Sistema de Registro</p>
        </div>

        <ul class="nav nav-pills flex-column mt-3 mb-auto">
            <li class="nav-item">
                <a href="#" class="nav-link text-white active" aria-current="page">
                    <i class="bi bi-house-door me-2"></i>Inicio
                </a>
            </li>
            
            <!-- Renderizado dinámico del menú basado en rol -->
            $menu_html

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
            <button type="button" class="btn btn-outline-light btn-sm w-100 d-flex justify-content-center align-items-center" data-bs-toggle="modal" data-bs-target="#logoutModal">
                <i class="bi bi-box-arrow-right me-2"></i>Cerrar Sesión
            </button>
        </div>
    </nav>

    <!-- Main Content -->
    <div id="content">
        <div class="top-header">
            <h4 class="mb-0 text-dark fw-bold">Dashboard Principal</h4>
            <div class="text-muted d-none d-md-block">
                Instituto Electoral del Estado de Querétaro
            </div>
        </div>

        <!-- Panel de Bienvenida -->
        <div class="row">
            <div class="col-12">
                <div class="card border-0 shadow-sm rounded-4 overflow-hidden">
                    <div class="card-body p-5 position-relative">
                        <div class="position-absolute top-0 end-0 p-4 opacity-25" style="font-size: 8rem; line-height: 1; color: #6B2D8B; transform: rotate(-15deg); margin-top: -20px; margin-right: -20px;">
                            <i class="bi bi-award-fill"></i>
                        </div>
                        <h2 class="display-5 fw-bold text-dark mb-3">¡Hola, $nombre_completo! 👋</h2>
                        <p class="lead text-secondary mb-4" style="max-width: 800px;">
                            Bienvenido al Sistema de Registro de Personas con INE. Has ingresado con el perfil de <strong><span class="text-uppercase" style="color: #6B2D8B;">$rol</span></strong>. 
                            Utiliza el menú lateral para acceder a las herramientas correspondientes a tus permisos.
                        </p>
                        
                        <div class="d-inline-flex px-4 py-2 rounded-pill bg-light border align-items-center shadow-sm">
                            <span class="badge rounded-pill bg-success me-2">Sesión Activa</span>
                            <small class="text-muted fw-semibold">Protegida bajo estándares del IEEQ</small>
                        </div>
                    </div>
                </div>
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
                    <a href="?logout=1" class="btn text-white px-4 rounded-pill" style="background-color: #6B2D8B;">Sí, cerrar sesión</a>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
HTML
