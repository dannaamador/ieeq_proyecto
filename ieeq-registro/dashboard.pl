#!C:\xampp\perl\bin\perl.exe
use strict;
use warnings;
use utf8;
use CGI;
use CGI::Session;
use FindBin;
use Encode qw(decode_utf8);
require "$FindBin::Bin/db.pl";

my $cgi = CGI->new;

# Configurar salida UTF-8
binmode(STDOUT, ":utf8");

# Leer sesión desde el directorio local .sesiones
my $session = CGI::Session->new(undef, $cgi, {Directory=>"$FindBin::Bin/.sesiones"});

# Si no hay un id_usuario válido en la sesión, expulsar al login
my $id_usuario = $session->param('id_usuario');
if (!$id_usuario) {
    print $cgi->redirect(-uri => 'login.pl');
    exit;
}

# Manejo del logout
if ($cgi->param('logout')) {
    $session->delete();
    $session->flush();
    print $cgi->redirect(-uri => 'login.pl');
    exit;
}

# Recuperar datos del usuario
my $nombre_completo = $session->param('nombre_completo') || 'Usuario';
my $rol = $session->param('rol') || '';

# Mapear rol a español para el mensaje de bienvenida y menú
my $rol_es = '';
if ($rol eq 'administrador') {
    $rol_es = 'ADMINISTRADOR DE ASOCIACIÓN';
} elsif ($rol eq 'funcionario') {
    $rol_es = 'FUNCIONARIO IEEQ';
} elsif ($rol eq 'integrante_organizacion') {
    $rol_es = 'AUXILIAR';
} else {
    $rol_es = uc($rol);
}

# ==========================================
# FUNCIONES AUXILIARES Y DE FORMATO
# ==========================================
sub format_number {
    my $number = shift // 0;
    $number =~ s/(\d)(?=(\d{3})+(?!\d))/$1,/g;
    return $number;
}

sub get_user_initials {
    my $name = shift || '';
    $name =~ s/^\s+|\s+$//g;
    my @parts = split /\s+/, $name;
    my $initials = '';
    if (@parts > 0) {
        $initials .= uc(substr($parts[0], 0, 1));
        if (@parts > 1) {
            $initials .= uc(substr($parts[1], 0, 1));
        }
    }
    return $initials || 'U';
}

sub get_avatar_color {
    my $name = shift || '';
    my @colors = ('#d97706', '#2563eb', '#059669', '#7c3aed', '#db2777', '#0dcaf0', '#6f42c1');
    my $sum = 0;
    $sum += ord($_) for split //, $name;
    return $colors[$sum % scalar(@colors)];
}

sub get_dashboard_badge {
    my ($accion) = @_;
    $accion = uc($accion || '');
    if ($accion eq 'REGISTRO') {
        return '<span class="badge rounded-pill bg-primary bg-opacity-10 text-primary border border-primary border-opacity-25 px-3 py-1.5" style="font-size: 0.72rem; font-weight: 600;">REGISTRO</span>';
    } elsif ($accion eq 'APROBACION' || $accion eq 'VALIDACION' || $accion eq 'APROBACIÓN') {
        return '<span class="badge rounded-pill bg-success bg-opacity-10 text-success border border-success border-opacity-25 px-3 py-1.5" style="font-size: 0.72rem; font-weight: 600;">APROBACIÓN</span>';
    } elsif ($accion eq 'GENERACION_CEDULA' || $accion eq 'GENERACIÓN_CÉDULA' || $accion eq 'CEDULA') {
        return '<span class="badge rounded-pill bg-purple bg-opacity-10 text-purple border border-purple border-opacity-25 px-3 py-1.5" style="font-size: 0.72rem; font-weight: 600; background-color: #f3e8ff; color: #6B2D8B; border: 1px solid #e9d5ff;">GENERACIÓN_CÉDULA</span>';
    } elsif ($accion eq 'EDICION' || $accion eq 'MODIFICACION' || $accion eq 'EDICIÓ' || $accion eq 'EDICIÓN') {
        return '<span class="badge rounded-pill bg-warning bg-opacity-10 text-warning border border-warning border-opacity-25 px-3 py-1.5" style="font-size: 0.72rem; font-weight: 600;">EDICIÓN</span>';
    } elsif ($accion eq 'RECHAZO' || $accion eq 'OBSERVACION') {
        return '<span class="badge rounded-pill bg-danger bg-opacity-10 text-danger border border-danger border-opacity-25 px-3 py-1.5" style="font-size: 0.72rem; font-weight: 600;">RECHAZO</span>';
    } else {
        return sprintf('<span class="badge rounded-pill bg-light text-dark border px-3 py-1.5" style="font-size: 0.72rem; font-weight: 600;">%s</span>', $accion);
    }
}

sub get_friendly_modulo {
    my ($tabla) = @_;
    $tabla = lc($tabla || '');
    if ($tabla eq 'afiliaciones' || $tabla eq 'registro de afiliaciones' || $tabla eq 'registro_afiliaciones') { return 'Registro de Afiliaciones'; }
    if ($tabla eq 'auxiliares' || $tabla eq 'registro de auxiliares' || $tabla eq 'registro_auxiliares') { return 'Registro de Auxiliares'; }
    if ($tabla eq 'usuarios' || $tabla eq 'gestión de usuarios' || $tabla eq 'gestion_usuarios') { return 'Gestión de Usuarios'; }
    if ($tabla eq 'permisos_usuario' || $tabla eq 'gestión de permisos' || $tabla eq 'gestion_permisos') { return 'Gestión de Permisos'; }
    if ($tabla eq 'personas' || $tabla eq 'padrón electoral' || $tabla eq 'padron_electoral') { return 'Padrón Electoral'; }
    return $tabla ? ucfirst($tabla) : 'Sistema';
}

# Iniciales del usuario para la barra lateral
my $initials_user = get_user_initials($nombre_completo);
my $avatar_color_user = get_avatar_color($nombre_completo);

# Página activa para el sidebar compartido
my $pagina_activa = 'INICIO';

# ==========================================
# GENERAR ELEMENTOS DINÁMICOS DEL MENÚ
# ==========================================
my $menu_html = '';

if ($rol eq 'administrador') {
    $menu_html .= <<'HTML';
        <li class="nav-item">
            <a href="dashboard.pl" class="nav-link text-white d-flex align-items-center justify-content-between active">
                <div><i class="bi bi-grid me-2"></i>Inicio</div>
                <i class="bi bi-chevron-right opacity-75" style="font-size: 0.75rem;"></i>
            </a>
        </li>
        <li class="nav-item">
            <a href="gestion_usuarios.pl" class="nav-link text-white">
                <i class="bi bi-people me-2"></i>Gestión de Usuarios
            </a>
        </li>
        <li class="nav-item">
            <a href="gestion_permisos.pl" class="nav-link text-white">
                <i class="bi bi-shield-lock me-2"></i>Gestión de Permisos
            </a>
        </li>
        <li class="nav-item">
            <a href="asociacion.pl" class="nav-link text-white">
                <i class="bi bi-building me-2"></i>Asociación
            </a>
        </li>
        <li class="nav-item">
            <a href="listado_afiliados.pl" class="nav-link text-white">
                <i class="bi bi-list-ul me-2"></i>Listado de Afiliados
            </a>
        </li>
        <li class="nav-item">
            <a href="cedulas.pl" class="nav-link text-white">
                <i class="bi bi-award me-2"></i>Cédulas
            </a>
        </li>
        <li class="nav-item">
            <a href="auditoria.pl" class="nav-link text-white">
                <i class="bi bi-journal-text me-2"></i>Bitácora
            </a>
        </li>
HTML
} elsif ($rol eq 'funcionario') {
    $menu_html .= <<'HTML';
        <li class="nav-item">
            <a href="dashboard.pl" class="nav-link text-white d-flex align-items-center justify-content-between active">
                <div><i class="bi bi-grid me-2"></i>Inicio</div>
                <i class="bi bi-chevron-right opacity-75" style="font-size: 0.75rem;"></i>
            </a>
        </li>
        <li class="nav-item">
            <a href="verificacion_afiliacion.pl" class="nav-link text-white">
                <i class="bi bi-person-check me-2"></i>Verificación de Afiliación
            </a>
        </li>
        <li class="nav-item">
            <a href="verificacion_auxiliares.pl" class="nav-link text-white">
                <i class="bi bi-person-badge me-2"></i>Verificación de Auxiliares
            </a>
        </li>
        <li class="nav-item">
            <a href="consulta_registros.pl" class="nav-link text-white">
                <i class="bi bi-search me-2"></i>Consulta de Registros
            </a>
        </li>
        <li class="nav-item">
            <a href="reportes.pl" class="nav-link text-white">
                <i class="bi bi-file-earmark-bar-graph me-2"></i>Reportes
            </a>
        </li>
HTML
} elsif ($rol eq 'integrante_organizacion') {
    $menu_html .= <<'HTML';
        <li class="nav-item">
            <a href="dashboard.pl" class="nav-link text-white d-flex align-items-center justify-content-between active">
                <div><i class="bi bi-grid me-2"></i>Inicio</div>
                <i class="bi bi-chevron-right opacity-75" style="font-size: 0.75rem;"></i>
            </a>
        </li>
        <li class="nav-item">
            <a href="registro_afiliados.pl" class="nav-link text-white">
                <i class="bi bi-person-plus me-2"></i>Registro de Afiliados
            </a>
        </li>
        <li class="nav-item">
            <a href="registro_auxiliares.pl" class="nav-link text-white">
                <i class="bi bi-person-vcard me-2"></i>Registro de Auxiliares
            </a>
        </li>
        <li class="nav-item">
            <a href="consulta_registros.pl" class="nav-link text-white">
                <i class="bi bi-search me-2"></i>Consulta de Registros
            </a>
        </li>
HTML
}

# ==========================================
# GENERAR CONTENIDO DINÁMICO POR ROL
# ==========================================
my $dashboard_content = '';
my $pct_avance_fmt = 0.0;

if ($rol eq 'administrador') {
    # 1. Obtener conteo de afiliaciones (Total, Nuevas, Verificadas)
    my ($total_afiliaciones, $nuevas, $verificadas, $rechazadas) = (0, 0, 0, 0);
    my $padron_reference = 1500000;
    my $porcentaje_minimo = 0.0013;

    my @counts_data = execute_query_list("
        SELECT 
            COUNT(*) as total,
            SUM(CASE WHEN estatus = 'NUEVA' THEN 1 ELSE 0 END) as nuevas,
            SUM(CASE WHEN estatus = 'VERIFICADO' THEN 1 ELSE 0 END) as verificadas
        FROM afiliaciones
        WHERE fecha_eliminacion IS NULL
    ");
    if (@counts_data) {
        $total_afiliaciones = $counts_data[0]->{total} || 0;
        $nuevas = $counts_data[0]->{nuevas} || 0;
        $verificadas = $counts_data[0]->{verificadas} || 0;
    }

    # 2. Obtener conteo de rechazadas (afiliaciones cuya última decisión fue RECHAZADO)
    my @rechazadas_data = execute_query_list("
        SELECT COUNT(DISTINCT a.id_afiliacion) as rechazadas
        FROM afiliaciones a
        JOIN verificaciones_afiliaciones v1 ON a.id_afiliacion = v1.id_afiliacion
        WHERE a.fecha_eliminacion IS NULL
          AND v1.id_verificacion = (
              SELECT MAX(v2.id_verificacion) 
              FROM verificaciones_afiliaciones v2 
              WHERE v2.id_afiliacion = a.id_afiliacion
          )
          AND v1.decision = 'RECHAZADO'
    ");
    if (@rechazadas_data) {
        $rechazadas = $rechazadas_data[0]->{rechazadas} || 0;
    }

    # 3. Obtener datos del padrón electoral
    my @padron_data = execute_query_list("
        SELECT total_padron, porcentaje_minimo 
        FROM padron_electoral 
        WHERE activo = 1 
        LIMIT 1
    ");
    if (@padron_data) {
        $padron_reference = $padron_data[0]->{total_padron} || 1500000;
        $porcentaje_minimo = $padron_data[0]->{porcentaje_minimo} || 0.0013;
    }

    my $minimo_reglamentario = int($padron_reference * $porcentaje_minimo);
    my $pct_verificadas = $total_afiliaciones > 0 ? ($verificadas / $total_afiliaciones) * 100 : 0.0;
    my $pct_verificadas_fmt = sprintf("%.1f", $pct_verificadas);

    # Porcentaje para la barra de progreso (avance hacia el mínimo)
    my $pct_avance = $minimo_reglamentario > 0 ? ($total_afiliaciones / $minimo_reglamentario) * 100 : 0.0;
    $pct_avance_fmt = sprintf("%.1f", $pct_avance);

    my $restantes = $minimo_reglamentario - $total_afiliaciones;
    $restantes = 0 if $restantes < 0;

    my $padron_formatted = format_number($padron_reference);
    my $minimo_formatted = format_number($minimo_reglamentario);
    my $total_afiliaciones_formatted = format_number($total_afiliaciones);
    my $restantes_formatted = format_number($restantes);
    my $porcentaje_minimo_fmt = sprintf("%.2f", $porcentaje_minimo * 100);

    # 4. Obtener actividad reciente para la tabla
    my $rows_recientes_html = '';
    my @recent_logs = execute_query_list("
        SELECT 
            b.fecha,
            b.accion,
            b.modulo,
            b.detalles as detalle,
            COALESCE(CONCAT(u.nombre, ' ', u.apellido_paterno), 'Sistema') as nombre_completo,
            COALESCE(u.correo_electronico, 'sistema') as username
        FROM bitacora b
        LEFT JOIN usuarios u ON b.id_usuario = u.id_usuario
        ORDER BY b.fecha DESC
        LIMIT 5
    ");
    if (@recent_logs) {
        for my $log (@recent_logs) {
            my $fecha = $log->{fecha} || '';
            my $nombre = $log->{nombre_completo} || 'Sistema';
            my $usr = $log->{username} || 'sistema';
            my $accion_badge = get_dashboard_badge($log->{accion});
            my $friendly_mod = get_friendly_modulo($log->{modulo});
            my $detalle = $log->{detalle} || '';
            
            my $initials = get_user_initials($nombre);
            my $color = get_avatar_color($nombre);
            
            $rows_recientes_html .= sprintf(
                '<tr>
                    <td class="align-middle text-secondary font-monospace" style="font-size: 0.85rem;">%s</td>
                    <td class="align-middle">
                        <div class="d-flex align-items-center">
                            <div class="rounded-circle text-white d-flex align-items-center justify-content-center fw-bold me-2" style="width: 32px; height: 32px; background-color: %s; font-size: 0.85rem;">
                                %s
                            </div>
                            <span class="fw-semibold text-dark" style="font-size: 0.9rem;">%s</span>
                        </div>
                    </td>
                    <td class="align-middle">%s</td>
                    <td class="align-middle text-secondary fw-semibold" style="font-size: 0.85rem;">%s</td>
                    <td class="align-middle text-dark" style="font-size: 0.85rem;" title="%s">%s</td>
                </tr>',
                $fecha, $color, $initials, $nombre, $accion_badge, $friendly_mod, $detalle, $detalle
            );
        }
    } else {
        $rows_recientes_html = '<tr><td colspan="5" class="text-center text-muted py-4"><i class="bi bi-info-circle me-2"></i>No hay registros en la bitácora.</td></tr>';
    }

    my $first_name = 'Usuario';
    if ($nombre_completo) {
        my @parts = split /\s+/, $nombre_completo;
        $first_name = $parts[0] if @parts > 0;
    }

    $dashboard_content = <<"HTML";
        <!-- Welcome Card -->
        <div class="card border-0 shadow-sm rounded-4 mb-4">
            <div class="card-body p-4 p-md-5">
                <div class="row align-items-center">
                    <div class="col-lg-7 mb-4 mb-lg-0">
                        <div class="d-flex align-items-center mb-2 flex-wrap gap-2">
                            <h2 class="fw-bold text-dark mb-0">¡Hola, $first_name! 👋</h2>
                            <span class="badge rounded-pill bg-success-subtle text-success border border-success-subtle px-3 py-1.5" style="font-size: 0.75rem; font-weight: 500;">
                                <span class="d-inline-block rounded-circle bg-success me-1.5" style="width: 8px; height: 8px; animation: pulse 1.5s infinite;"></span>Sesión Activa
                            </span>
                        </div>
                        <p class="text-secondary mb-3 fs-6">
                            Bienvenido al Sistema de Registro de Afiliaciones del IEEQ. Tu rol es <strong>Administrador de Asociación</strong>.
                        </p>
                        <span class="badge rounded-pill px-3 py-1.5" style="background-color: #f3e8ff; color: #6B2D8B; font-weight: 600; font-size: 0.75rem; border: 1px solid #e9d5ff;">Administrador</span>
                    </div>
                    <div class="col-lg-5 text-lg-end d-flex gap-2 justify-content-lg-end flex-wrap">
                        <a href="listado_afiliados.pl" class="btn btn-ieeq px-4 py-2.5 rounded-pill d-inline-flex align-items-center gap-2">
                            <i class="bi bi-people-fill"></i> Listado de Afiliados
                        </a>
                        <a href="cedulas.pl" class="btn px-4 py-2.5 rounded-pill d-inline-flex align-items-center gap-2" style="background-color: #3b174a; color: white; border: 1px solid #3b174a;">
                            <i class="bi bi-award-fill"></i> Generar Cédulas
                        </a>
                    </div>
                </div>
            </div>
        </div>

        <!-- KPI Cards Grid -->
        <div class="row mb-4 g-3">
            <div class="col-lg-3 col-sm-6">
                <div class="card border-0 shadow-sm rounded-4 text-white h-100 position-relative overflow-hidden" style="background-color: #4C1D95; padding: 1.5rem;">
                    <div class="d-flex justify-content-between align-items-start mb-3">
                        <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 44px; height: 44px; background-color: rgba(255, 255, 255, 0.2) !important;">
                            <i class="bi bi-people fs-4 text-white"></i>
                        </div>
                        <div class="text-white-50"><i class="bi bi-arrow-up-right fs-5 opacity-75"></i></div>
                    </div>
                    <h3 class="display-5 fw-bold mb-1 font-monospace">$total_afiliaciones_formatted</h3>
                    <div class="fw-bold mb-1" style="font-size: 0.95rem;">Total Afiliaciones</div>
                    <span class="text-white-50" style="font-size: 0.75rem;">en el sistema</span>
                </div>
            </div>
            <div class="col-lg-3 col-sm-6">
                <div class="card border-0 shadow-sm rounded-4 text-white h-100 position-relative overflow-hidden" style="background-color: #F59E0B; padding: 1.5rem;">
                    <div class="d-flex justify-content-between align-items-start mb-3">
                        <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 44px; height: 44px; background-color: rgba(255, 255, 255, 0.2) !important;">
                            <i class="bi bi-clock fs-4 text-white"></i>
                        </div>
                        <div class="text-white-50"><i class="bi bi-arrow-up-right fs-5 opacity-75"></i></div>
                    </div>
                    <h3 class="display-5 fw-bold mb-1 font-monospace">$nuevas</h3>
                    <div class="fw-bold mb-1" style="font-size: 0.95rem;">Pendientes de enviar</div>
                    <span class="text-white-50" style="font-size: 0.75rem;">requieren tu acción</span>
                </div>
            </div>
            <div class="col-lg-3 col-sm-6">
                <div class="card border-0 shadow-sm rounded-4 text-white h-100 position-relative overflow-hidden" style="background-color: #10B981; padding: 1.5rem;">
                    <div class="d-flex justify-content-between align-items-start mb-3">
                        <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 44px; height: 44px; background-color: rgba(255, 255, 255, 0.2) !important;">
                            <i class="bi bi-check-circle fs-4 text-white"></i>
                        </div>
                        <div class="text-white-50"><i class="bi bi-arrow-up-right fs-5 opacity-75"></i></div>
                    </div>
                    <h3 class="display-5 fw-bold mb-1 font-monospace">$verificadas</h3>
                    <div class="fw-bold mb-1" style="font-size: 0.95rem;">Verificadas</div>
                    <span class="text-white-50" style="font-size: 0.75rem;">$pct_verificadas_fmt% del total</span>
                </div>
            </div>
            <div class="col-lg-3 col-sm-6">
                <div class="card border-0 shadow-sm rounded-4 text-white h-100 position-relative overflow-hidden" style="background-color: #EF4444; padding: 1.5rem;">
                    <div class="d-flex justify-content-between align-items-start mb-3">
                        <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 44px; height: 44px; background-color: rgba(255, 255, 255, 0.2) !important;">
                            <i class="bi bi-x-circle fs-4 text-white"></i>
                        </div>
                        <div class="text-white-50"><i class="bi bi-arrow-up-right fs-5 opacity-75"></i></div>
                    </div>
                    <h3 class="display-5 fw-bold mb-1 font-monospace">$rechazadas</h3>
                    <div class="fw-bold mb-1" style="font-size: 0.95rem;">Rechazadas</div>
                    <span class="text-white-50" style="font-size: 0.75rem;">no aptas para registro</span>
                </div>
            </div>
        </div>

        <!-- Acciones Rápidas and Capacidades Grid -->
        <div class="row mb-4 g-3">
            <div class="col-lg-5">
                <div class="card border-0 shadow-sm rounded-4 p-4 h-100">
                    <h5 class="fw-bold text-dark mb-4">Acciones rápidas</h5>
                    <div class="d-flex flex-column gap-3">
                        <a href="listado_afiliados.pl" class="quick-action-card d-flex align-items-center justify-content-between p-3 rounded-4 text-decoration-none transition" style="background-color: #FAF5FF; border: 1px solid #F3E8FF;">
                            <div class="d-flex align-items-center">
                                <div class="rounded-circle d-flex align-items-center justify-content-center text-white" style="width: 44px; height: 44px; background-color: #6B2D8B;">
                                    <i class="bi bi-people-fill fs-5"></i>
                                </div>
                                <div class="ms-3">
                                    <div class="fw-bold text-dark" style="font-size: 0.95rem;">Listado de Afiliados</div>
                                    <div class="text-secondary" style="font-size: 0.75rem;">Ver y gestionar registros</div>
                                </div>
                            </div>
                            <i class="bi bi-arrow-right text-secondary fs-5 me-1"></i>
                        </a>
                        <a href="cedulas.pl" class="quick-action-card d-flex align-items-center justify-content-between p-3 rounded-4 text-decoration-none transition" style="background-color: #FAF5FF; border: 1px solid #F3E8FF;">
                            <div class="d-flex align-items-center">
                                <div class="rounded-circle d-flex align-items-center justify-content-center text-white" style="width: 44px; height: 44px; background-color: #6B2D8B;">
                                    <i class="bi bi-award-fill fs-5"></i>
                                </div>
                                <div class="ms-3">
                                    <div class="fw-bold text-dark" style="font-size: 0.95rem;">Generar Cédulas</div>
                                    <div class="text-secondary" style="font-size: 0.75rem;">Cédulas de afiliados verificados</div>
                                </div>
                            </div>
                            <i class="bi bi-arrow-right text-secondary fs-5 me-1"></i>
                        </a>
                        <a href="gestion_usuarios.pl" class="quick-action-card d-flex align-items-center justify-content-between p-3 rounded-4 text-decoration-none transition" style="background-color: #FAF5FF; border: 1px solid #F3E8FF;">
                            <div class="d-flex align-items-center">
                                <div class="rounded-circle d-flex align-items-center justify-content-center text-white" style="width: 44px; height: 44px; background-color: #6B2D8B;">
                                    <i class="bi bi-shield-lock-fill fs-5"></i>
                                </div>
                                <div class="ms-3">
                                    <div class="fw-bold text-dark" style="font-size: 0.95rem;">Gestión de Usuarios</div>
                                    <div class="text-secondary" style="font-size: 0.75rem;">Administrar accesos al sistema</div>
                                </div>
                            </div>
                            <i class="bi bi-arrow-right text-secondary fs-5 me-1"></i>
                        </a>
                    </div>
                </div>
            </div>
            <div class="col-lg-7">
                <div class="card border-0 shadow-sm rounded-4 p-4 h-100">
                    <h5 class="fw-bold text-dark mb-4">Capacidades de tu rol</h5>
                    <div class="row g-3">
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA;">
                                <div class="text-success me-3 fs-4 d-flex align-items-center justify-content-center bg-success bg-opacity-10 rounded-circle" style="width: 36px; height: 36px; color: #6B2D8B !important; background-color: rgba(107,45,139,0.1) !important;">
                                    <i class="bi bi-check-circle-fill"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Capturar afiliaciones</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Registrar nuevos afiliados</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA;">
                                <div class="text-success me-3 fs-4 d-flex align-items-center justify-content-center bg-success bg-opacity-10 rounded-circle" style="width: 36px; height: 36px; color: #6B2D8B !important; background-color: rgba(107,45,139,0.1) !important;">
                                    <i class="bi bi-check-circle-fill"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Gestionar usuarios</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Crear, editar y desactivar usuarios</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA;">
                                <div class="text-success me-3 fs-4 d-flex align-items-center justify-content-center bg-success bg-opacity-10 rounded-circle" style="width: 36px; height: 36px; color: #6B2D8B !important; background-color: rgba(107,45,139,0.1) !important;">
                                    <i class="bi bi-check-circle-fill"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Enviar a revisión IEEQ</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Enviar afiliaciones al Instituto</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA;">
                                <div class="text-success me-3 fs-4 d-flex align-items-center justify-content-center bg-success bg-opacity-10 rounded-circle" style="width: 36px; height: 36px; color: #6B2D8B !important; background-color: rgba(107,45,139,0.1) !important;">
                                    <i class="bi bi-check-circle-fill"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Generar cédulas</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Emitir cédulas de afiliados</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA;">
                                <div class="text-success me-3 fs-4 d-flex align-items-center justify-content-center bg-success bg-opacity-10 rounded-circle" style="width: 36px; height: 36px; color: #6B2D8B !important; background-color: rgba(107,45,139,0.1) !important;">
                                    <i class="bi bi-check-circle-fill"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Ver bitácora completa</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Historial de operaciones</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA; opacity: 0.6;">
                                <div class="text-secondary me-3 fs-4 d-flex align-items-center justify-content-center bg-secondary bg-opacity-10 rounded-circle" style="width: 36px; height: 36px;">
                                    <i class="bi bi-dash-circle"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Verificar en padrón</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Solo para el Funcionariado IEEQ</div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Avance Mínimo Requerido Card -->
        <div class="card border-0 shadow-sm rounded-4 p-4 mb-4 bg-white">
            <div class="d-flex justify-content-between align-items-center mb-2 flex-wrap">
                <div>
                    <h5 class="fw-bold text-dark mb-1">Avance hacia el mínimo requerido</h5>
                    <small class="text-secondary">Padrón de referencia: <strong class="text-dark">$padron_formatted</strong> electores · Mínimo reglamentario: <strong class="text-dark">$minimo_formatted ($porcentaje_minimo_fmt%)</strong></small>
                </div>
                <div class="text-end">
                    <span id="contadorPorcentaje" class="display-6 fw-bold" style="color: #6B2D8B;">0.0%</span>
                </div>
            </div>
            
            <div class="progress mb-3" style="height: 12px; background-color: #e9ecef; border-radius: 6px;">
                <div id="barraProgreso" class="progress-bar progress-bar-striped progress-bar-animated" role="progressbar" style="width: 0%; background-color: #6B2D8B; border-radius: 6px; transition: none;"></div>
            </div>
            
            <div class="d-flex justify-content-between text-secondary" style="font-size: 0.85rem;">
                <div><strong>$total_afiliaciones_formatted</strong> afiliaciones registradas</div>
                <div><strong>$restantes_formatted</strong> restantes para el mínimo</div>
            </div>
        </div>

        <!-- Recent Activity Table Card -->
        <div class="card border-0 shadow-sm rounded-4 p-4 bg-white mb-4">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h5 class="fw-bold text-dark mb-0">Actividad Reciente</h5>
                <a href="auditoria.pl" class="text-decoration-none fw-semibold" style="color: #6B2D8B; font-size: 0.9rem;">Ver bitácora completa &rarr;</a>
            </div>
            <div class="table-responsive">
                <table class="table table-hover align-middle mb-0">
                    <thead>
                        <tr class="table-light">
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Fecha / Hora</th>
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Usuario</th>
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Acción</th>
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Módulo</th>
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Detalle</th>
                        </tr>
                    </thead>
                    <tbody>
                        $rows_recientes_html
                    </tbody>
                </table>
            </div>
        </div>
HTML
} elsif ($rol eq 'integrante_organizacion') {
    # 1. Obtener conteo de afiliaciones del integrante
    my @mis_counts = execute_query_list("
        SELECT 
            COUNT(*) as total,
            SUM(CASE WHEN estatus = 'NUEVA' THEN 1 ELSE 0 END) as nuevas
        FROM afiliaciones
        WHERE id_registrador = ? AND fecha_eliminacion IS NULL
    ", $id_usuario);
    my $mis_afiliaciones = $mis_counts[0]->{total} || 0;
    my $mis_nuevas       = $mis_counts[0]->{nuevas} || 0;

    # 2. Obtener estadísticas globales del sistema
    my @global_counts = execute_query_list("
        SELECT 
            COUNT(*) as total,
            SUM(CASE WHEN estatus = 'VERIFICADO' THEN 1 ELSE 0 END) as verificadas
        FROM afiliaciones
        WHERE fecha_eliminacion IS NULL
    ");
    my $total_afiliaciones_sistema = $global_counts[0]->{total} || 0;
    my $total_verificadas_sistema  = $global_counts[0]->{verificadas} || 0;

    # 3. Datos del padrón electoral
    my $padron_reference = 1432874;
    my $porcentaje_minimo = 0.0013;
    my @padron_data = execute_query_list("
        SELECT total_padron, porcentaje_minimo 
        FROM padron_electoral 
        WHERE activo = 1 
        LIMIT 1
    ");
    if (@padron_data) {
        $padron_reference = $padron_data[0]->{total_padron} || 1432874;
        $porcentaje_minimo = $padron_data[0]->{porcentaje_minimo} || 0.0013;
    }
    my $minimo_reglamentario = int($padron_reference * $porcentaje_minimo);

    # Avance hacia el mínimo
    my $pct_avance = $minimo_reglamentario > 0 ? ($total_afiliaciones_sistema / $minimo_reglamentario) * 100 : 0.0;
    $pct_avance_fmt = sprintf("%.1f", $pct_avance);

    my $restantes = $minimo_reglamentario - $total_afiliaciones_sistema;
    $restantes = 0 if $restantes < 0;

    my $padron_formatted = format_number($padron_reference);
    my $minimo_formatted = format_number($minimo_reglamentario);
    my $total_sistema_formatted = format_number($total_afiliaciones_sistema);
    my $restantes_formatted = format_number($restantes);
    my $porcentaje_minimo_fmt = sprintf("%.2f", $porcentaje_minimo * 100);

    # 4. Actividad Reciente (global)
    my $rows_recientes_html = '';
    my @recent_logs = execute_query_list("
        SELECT 
            b.fecha,
            b.accion,
            b.modulo,
            b.detalles as detalle,
            COALESCE(CONCAT(u.nombre, ' ', u.apellido_paterno), 'Sistema') as nombre_completo,
            COALESCE(u.correo_electronico, 'sistema') as username
        FROM bitacora b
        LEFT JOIN usuarios u ON b.id_usuario = u.id_usuario
        ORDER BY b.fecha DESC
        LIMIT 5
    ");
    if (@recent_logs) {
        for my $log (@recent_logs) {
            my $fecha = $log->{fecha} || '';
            my $nombre = $log->{nombre_completo} || 'Sistema';
            my $usr = $log->{username} || 'sistema';
            my $accion_badge = get_dashboard_badge($log->{accion});
            my $friendly_mod = get_friendly_modulo($log->{modulo});
            my $detalle = $log->{detalle} || '';
            
            my $initials = get_user_initials($nombre);
            my $color = get_avatar_color($nombre);
            
            $rows_recientes_html .= sprintf(
                '<tr>
                    <td class="align-middle text-secondary font-monospace" style="font-size: 0.85rem;">%s</td>
                    <td class="align-middle">
                        <div class="d-flex align-items-center">
                            <div class="rounded-circle text-white d-flex align-items-center justify-content-center fw-bold me-2" style="width: 32px; height: 32px; background-color: %s; font-size: 0.85rem;">
                                %s
                            </div>
                            <span class="fw-semibold text-dark" style="font-size: 0.9rem;">%s</span>
                        </div>
                    </td>
                    <td class="align-middle">%s</td>
                    <td class="align-middle text-secondary fw-semibold" style="font-size: 0.85rem;">%s</td>
                    <td class="align-middle text-dark" style="font-size: 0.85rem;" title="%s">%s</td>
                </tr>',
                $fecha, $color, $initials, $nombre, $accion_badge, $friendly_mod, $detalle, $detalle
            );
        }
    } else {
        $rows_recientes_html = '<tr><td colspan="5" class="text-center text-muted py-4"><i class="bi bi-info-circle me-2"></i>No hay registros en la bitácora.</td></tr>';
    }

    # Banners de advertencia si tiene registros en estado "NUEVA"
    my $advertencia_banner_html = '';
    if ($mis_nuevas > 0) {
        my $plural_reg = $mis_nuevas == 1 ? 'registro puede' : 'registros pueden';
        $advertencia_banner_html = <<"HTML";
        <!-- Warning Banner -->
        <a href="listado_afiliados.pl?filtro=NUEVA" class="card border-0 shadow-sm rounded-4 mb-4 text-decoration-none transition" style="background-color: #fffbeb; border: 1px solid #fde68a; padding: 1.2rem 1.5rem; transition: transform 0.2s ease;">
            <div class="d-flex justify-content-between align-items-center">
                <div class="d-flex align-items-center gap-3">
                    <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 40px; height: 40px; background-color: #fef3c7; color: #d97706; flex-shrink: 0; border: 1.5px solid #d97706;">
                        <i class="bi bi-exclamation-circle-fill fs-5"></i>
                    </div>
                    <div>
                        <h6 class="fw-bold mb-1" style="color: #92400e; font-size: 0.95rem;">$mis_nuevas de tus $plural_reg ser editados</h6>
                        <p class="mb-0 small" style="color: #b45309; font-weight: 500; opacity: 0.9;">Tienes capturas con estatus «Nueva afiliación» que aún puedes modificar antes de que el Administrador las envíe a revisión.</p>
                    </div>
                </div>
                <i class="bi bi-chevron-right fs-5" style="color: #d97706;"></i>
            </div>
        </a>
        <style>
            a.card:hover {
                transform: translateY(-2px);
                box-shadow: 0 6px 15px rgba(217, 119, 6, 0.08) !important;
            }
        </style>
HTML
    }

    my $first_name = 'Usuario';
    if ($nombre_completo) {
        my @parts = split /\s+/, $nombre_completo;
        $first_name = $parts[0] if @parts > 0;
    }

    $dashboard_content = <<"HTML";
        <!-- Welcome Card -->
        <div class="card border-0 shadow-sm rounded-4 mb-4">
            <div class="card-body p-4 p-md-5">
                <div class="row align-items-center">
                    <div class="col-lg-7 mb-4 mb-lg-0">
                        <div class="d-flex align-items-center mb-2 flex-wrap gap-2">
                            <h2 class="fw-bold text-dark mb-0">¡Hola, $first_name! 👋</h2>
                            <span class="badge rounded-pill bg-success-subtle text-success border border-success-subtle px-3 py-1.5" style="font-size: 0.75rem; font-weight: 500;">
                                <span class="d-inline-block rounded-circle bg-success me-1.5" style="width: 8px; height: 8px; animation: pulse 1.5s infinite;"></span>Sesión Activa
                            </span>
                        </div>
                        <p class="text-secondary mb-3 fs-6">
                            Bienvenido al Sistema de Registro de Afiliaciones del IEEQ. Tu rol es <strong>Persona Auxiliar</strong>.
                        </p>
                        <span class="badge rounded-pill px-3 py-1.5" style="background-color: #eff6ff; color: #1d4ed8; font-weight: 600; font-size: 0.75rem; border: 1px solid #bfdbfe;">Auxiliar</span>
                    </div>
                    <div class="col-lg-5 text-lg-end d-flex gap-2 justify-content-lg-end flex-wrap">
                        <a href="registro_afiliados.pl" class="btn btn-ieeq px-4 py-2.5 rounded-pill d-inline-flex align-items-center gap-2">
                            <i class="bi bi-person-plus-fill"></i> Nueva Afiliación
                        </a>
                        <a href="listado_afiliados.pl" class="btn px-4 py-2.5 rounded-pill d-inline-flex align-items-center gap-2" style="background-color: #3b174a; color: white; border: 1px solid #3b174a;">
                            <i class="bi bi-file-earmark-check-fill"></i> Mis Registros
                        </a>
                    </div>
                </div>
            </div>
        </div>

        $advertencia_banner_html

        <!-- KPI Cards Grid -->
        <div class="row mb-4 g-3">
            <div class="col-lg-3 col-sm-6">
                <div class="card border-0 shadow-sm rounded-4 text-white h-100 position-relative overflow-hidden" style="background-color: #4C1D95; padding: 1.5rem;">
                    <div class="d-flex justify-content-between align-items-start mb-3">
                        <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 44px; height: 44px; background-color: rgba(255, 255, 255, 0.2) !important;">
                            <i class="bi bi-people fs-4 text-white"></i>
                        </div>
                        <div class="text-white-50"><i class="bi bi-arrow-up-right fs-5 opacity-75"></i></div>
                    </div>
                    <h3 class="display-5 fw-bold mb-1 font-monospace">$mis_afiliaciones</h3>
                    <div class="fw-bold mb-1" style="font-size: 0.95rem;">Mis Afiliaciones</div>
                    <span class="text-white-50" style="font-size: 0.75rem;">capturas realizadas</span>
                </div>
            </div>
            <div class="col-lg-3 col-sm-6">
                <div class="card border-0 shadow-sm rounded-4 text-white h-100 position-relative overflow-hidden" style="background-color: #F59E0B; padding: 1.5rem;">
                    <div class="d-flex justify-content-between align-items-start mb-3">
                        <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 44px; height: 44px; background-color: rgba(255, 255, 255, 0.2) !important;">
                            <i class="bi bi-clock fs-4 text-white"></i>
                        </div>
                        <div class="text-white-50"><i class="bi bi-arrow-up-right fs-5 opacity-75"></i></div>
                    </div>
                    <h3 class="display-5 fw-bold mb-1 font-monospace">$mis_nuevas</h3>
                    <div class="fw-bold mb-1" style="font-size: 0.95rem;">En edición (nuevas)</div>
                    <span class="text-white-50" style="font-size: 0.75rem;">puedes editar/eliminar</span>
                </div>
            </div>
            <div class="col-lg-3 col-sm-6">
                <div class="card border-0 shadow-sm rounded-4 text-white h-100 position-relative overflow-hidden" style="background-color: #10B981; padding: 1.5rem;">
                    <div class="d-flex justify-content-between align-items-start mb-3">
                        <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 44px; height: 44px; background-color: rgba(255, 255, 255, 0.2) !important;">
                            <i class="bi bi-check-circle fs-4 text-white"></i>
                        </div>
                        <div class="text-white-50"><i class="bi bi-arrow-up-right fs-5 opacity-75"></i></div>
                    </div>
                    <h3 class="display-5 fw-bold mb-1 font-monospace">$total_verificadas_sistema</h3>
                    <div class="fw-bold mb-1" style="font-size: 0.95rem;">Total verificadas</div>
                    <span class="text-white-50" style="font-size: 0.75rem;">del sistema</span>
                </div>
            </div>
            <div class="col-lg-3 col-sm-6">
                <div class="card border-0 shadow-sm rounded-4 text-white h-100 position-relative overflow-hidden" style="background-color: #3B82F6; padding: 1.5rem;">
                    <div class="d-flex justify-content-between align-items-start mb-3">
                        <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 44px; height: 44px; background-color: rgba(255, 255, 255, 0.2) !important;">
                            <i class="bi bi-graph-up fs-4 text-white"></i>
                        </div>
                        <div class="text-white-50"><i class="bi bi-arrow-up-right fs-5 opacity-75"></i></div>
                    </div>
                    <h3 class="display-5 fw-bold mb-1 font-monospace">$total_afiliaciones_sistema</h3>
                    <div class="fw-bold mb-1" style="font-size: 0.95rem;">Total afiliaciones</div>
                    <span class="text-white-50" style="font-size: 0.75rem;">en el sistema</span>
                </div>
            </div>
        </div>

        <!-- Acciones Rápidas and Capacidades Grid -->
        <div class="row mb-4 g-3">
            <div class="col-lg-5">
                <div class="card border-0 shadow-sm rounded-4 p-4 h-100">
                    <h5 class="fw-bold text-dark mb-4">Acciones rápidas</h5>
                    <div class="d-flex flex-column gap-3">
                        <a href="registro_afiliados.pl" class="quick-action-card d-flex align-items-center justify-content-between p-3 rounded-4 text-decoration-none transition" style="background-color: #FAF5FF; border: 1px solid #F3E8FF;">
                            <div class="d-flex align-items-center">
                                <div class="rounded-circle d-flex align-items-center justify-content-center text-white" style="width: 44px; height: 44px; background-color: #6B2D8B;">
                                    <i class="bi bi-person-plus fs-5"></i>
                                </div>
                                <div class="ms-3">
                                    <div class="fw-bold text-dark" style="font-size: 0.95rem;">Nueva Afiliación</div>
                                    <div class="text-secondary" style="font-size: 0.75rem;">Capturar un nuevo ciudadano</div>
                                </div>
                            </div>
                            <i class="bi bi-arrow-right text-secondary fs-5 me-1"></i>
                        </a>
                        <a href="listado_afiliados.pl" class="quick-action-card d-flex align-items-center justify-content-between p-3 rounded-4 text-decoration-none transition" style="background-color: #FAF5FF; border: 1px solid #F3E8FF;">
                            <div class="d-flex align-items-center">
                                <div class="rounded-circle d-flex align-items-center justify-content-center text-white" style="width: 44px; height: 44px; background-color: #6B2D8B;">
                                    <i class="bi bi-file-earmark-check fs-5"></i>
                                </div>
                                <div class="ms-3">
                                    <div class="fw-bold text-dark" style="font-size: 0.95rem;">Mis Registros</div>
                                    <div class="text-secondary" style="font-size: 0.75rem;">Ver y editar mis capturas</div>
                                </div>
                            </div>
                            <i class="bi bi-arrow-right text-secondary fs-5 me-1"></i>
                        </a>
                    </div>
                </div>
            </div>
            <div class="col-lg-7">
                <div class="card border-0 shadow-sm rounded-4 p-4 h-100">
                    <h5 class="fw-bold text-dark mb-4">Capacidades de tu rol</h5>
                    <div class="row g-3">
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA;">
                                <div class="text-success me-3 fs-4 d-flex align-items-center justify-content-center bg-success bg-opacity-10 rounded-circle" style="width: 36px; height: 36px; color: #6B2D8B !important; background-color: rgba(107,45,139,0.1) !important;">
                                    <i class="bi bi-check-circle-fill"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Capturar afiliaciones</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Registrar nuevos afiliados</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA;">
                                <div class="text-success me-3 fs-4 d-flex align-items-center justify-content-center bg-success bg-opacity-10 rounded-circle" style="width: 36px; height: 36px; color: #6B2D8B !important; background-color: rgba(107,45,139,0.1) !important;">
                                    <i class="bi bi-check-circle-fill"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Editar mis capturas</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Solo registros propios con estatus «Nueva»</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA;">
                                <div class="text-success me-3 fs-4 d-flex align-items-center justify-content-center bg-success bg-opacity-10 rounded-circle" style="width: 36px; height: 36px; color: #6B2D8B !important; background-color: rgba(107,45,139,0.1) !important;">
                                    <i class="bi bi-check-circle-fill"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Eliminar mis capturas</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Solo registros propios con estatus «Nueva»</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA; opacity: 0.6;">
                                <div class="text-secondary me-3 fs-4 d-flex align-items-center justify-content-center bg-secondary bg-opacity-10 rounded-circle" style="width: 36px; height: 36px;">
                                    <i class="bi bi-dash-circle"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Enviar a revisión</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Solo disponible para el Administrador</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA; opacity: 0.6;">
                                <div class="text-secondary me-3 fs-4 d-flex align-items-center justify-content-center bg-secondary bg-opacity-10 rounded-circle" style="width: 36px; height: 36px;">
                                    <i class="bi bi-dash-circle"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Gestionar usuarios</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Solo disponible para el Administrador</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA; opacity: 0.6;">
                                <div class="text-secondary me-3 fs-4 d-flex align-items-center justify-content-center bg-secondary bg-opacity-10 rounded-circle" style="width: 36px; height: 36px;">
                                    <i class="bi bi-dash-circle"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Generar cédulas</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Solo disponible para Administrador e IEEQ</div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Avance Mínimo Requerido Card -->
        <div class="card border-0 shadow-sm rounded-4 p-4 mb-4 bg-white">
            <div class="d-flex justify-content-between align-items-center mb-2 flex-wrap">
                <div>
                    <h5 class="fw-bold text-dark mb-1">Avance hacia el mínimo requerido</h5>
                    <small class="text-secondary">Padrón de referencia: <strong class="text-dark">$padron_formatted</strong> electores · Mínimo reglamentario: <strong class="text-dark">$minimo_formatted ($porcentaje_minimo_fmt%)</strong></small>
                </div>
                <div class="text-end">
                    <span id="contadorPorcentaje" class="display-6 fw-bold" style="color: #6B2D8B;">0.0%</span>
                </div>
            </div>
            
            <div class="progress mb-3" style="height: 12px; background-color: #e9ecef; border-radius: 6px;">
                <div id="barraProgreso" class="progress-bar progress-bar-striped progress-bar-animated" role="progressbar" style="width: 0%; background-color: #6B2D8B; border-radius: 6px; transition: none;"></div>
            </div>
            
            <div class="d-flex justify-content-between text-secondary" style="font-size: 0.85rem;">
                <div><strong>$total_sistema_formatted</strong> afiliaciones registradas</div>
                <div><strong>$restantes_formatted</strong> restantes para el mínimo</div>
            </div>
        </div>

        <!-- Recent Activity Table Card -->
        <div class="card border-0 shadow-sm rounded-4 p-4 bg-white mb-4">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h5 class="fw-bold text-dark mb-0">Actividad Reciente</h5>
            </div>
            <div class="table-responsive">
                <table class="table table-hover align-middle mb-0">
                    <thead>
                        <tr class="table-light">
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Fecha / Hora</th>
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Usuario</th>
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Acción</th>
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Módulo</th>
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Detalle</th>
                        </tr>
                    </thead>
                    <tbody>
                        $rows_recientes_html
                    </tbody>
                </table>
            </div>
        </div>
HTML
} elsif ($rol eq 'funcionario') {
    # 1. Obtener conteo de afiliaciones (Total, Nuevas, Verificadas, Rechazadas)
    my ($total_afiliaciones, $pendientes, $verificadas, $rechazadas) = (0, 0, 0, 0);
    my @counts_data = execute_query_list("
        SELECT 
            COUNT(*) as total,
            SUM(CASE WHEN estatus = 'NUEVA' THEN 1 ELSE 0 END) as pendientes,
            SUM(CASE WHEN estatus = 'VERIFICADO' THEN 1 ELSE 0 END) as verificadas,
            SUM(CASE WHEN estatus = 'RECHAZADO' THEN 1 ELSE 0 END) as rechazadas
        FROM afiliaciones
        WHERE fecha_eliminacion IS NULL
    ");
    if (@counts_data) {
        $total_afiliaciones = $counts_data[0]->{total} || 0;
        $pendientes         = $counts_data[0]->{pendientes} || 0;
        $verificadas        = $counts_data[0]->{verificadas} || 0;
        $rechazadas         = $counts_data[0]->{rechazadas} || 0;
    }

    # 2. Obtener actividad reciente para la tabla
    my $rows_recientes_html = '';
    my @recent_logs = execute_query_list("
        SELECT 
            b.fecha,
            b.accion,
            b.modulo,
            b.detalles as detalle,
            COALESCE(CONCAT(u.nombre, ' ', u.apellido_paterno), 'Sistema') as nombre_completo,
            COALESCE(u.correo_electronico, 'sistema') as username
        FROM bitacora b
        LEFT JOIN usuarios u ON b.id_usuario = u.id_usuario
        ORDER BY b.fecha DESC
        LIMIT 5
    ");
    if (@recent_logs) {
        for my $log (@recent_logs) {
            my $fecha = $log->{fecha} || '';
            my $nombre = $log->{nombre_completo} || 'Sistema';
            my $usr = $log->{username} || 'sistema';
            my $accion_badge = get_dashboard_badge($log->{accion});
            my $friendly_mod = get_friendly_modulo($log->{modulo});
            my $detalle = $log->{detalle} || '';
            
            my $initials = get_user_initials($nombre);
            my $color = get_avatar_color($nombre);
            
            $rows_recientes_html .= sprintf(
                '<tr>
                    <td class="align-middle text-secondary font-monospace" style="font-size: 0.85rem;">%s</td>
                    <td class="align-middle">
                        <div class="d-flex align-items-center">
                            <div class="rounded-circle text-white d-flex align-items-center justify-content-center fw-bold me-2" style="width: 32px; height: 32px; background-color: %s; font-size: 0.85rem;">
                                %s
                            </div>
                            <span class="fw-semibold text-dark" style="font-size: 0.9rem;">%s</span>
                        </div>
                    </td>
                    <td class="align-middle">%s</td>
                    <td class="align-middle text-secondary fw-semibold" style="font-size: 0.85rem;">%s</td>
                    <td class="align-middle text-dark" style="font-size: 0.85rem;" title="%s">%s</td>
                </tr>',
                $fecha, $color, $initials, $nombre, $accion_badge, $friendly_mod, $detalle, $detalle
            );
        }
    } else {
        $rows_recientes_html = '<tr><td colspan="5" class="text-center text-muted py-4"><i class="bi bi-info-circle me-2"></i>No hay registros en la bitácora.</td></tr>';
    }

    my $first_name = 'Usuario';
    if ($nombre_completo) {
        my @parts = split /\s+/, $nombre_completo;
        $first_name = $parts[0] if @parts > 0;
    }

    my $alert_banner_html = '';
    if ($pendientes > 0) {
        $alert_banner_html = <<"HTML";
        <!-- Alert Banner -->
        <a href="listado_afiliados.pl?filtro=NUEVA" class="card border-0 shadow-sm rounded-4 mb-4 text-decoration-none transition" style="background-color: #eff6ff; border: 1px solid #bfdbfe; padding: 1.2rem 1.5rem; transition: transform 0.2s ease;">
            <div class="d-flex justify-content-between align-items-center">
                <div class="d-flex align-items-center gap-3">
                    <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 40px; height: 40px; background-color: #dbeafe; color: #1d4ed8; flex-shrink: 0;">
                        <i class="bi bi-shield-exclamation fs-5"></i>
                    </div>
                    <div>
                        <h6 class="fw-bold mb-1" style="color: #1e3a8a; font-size: 0.95rem;">Tienes $pendientes afiliaciones pendientes de verificación</h6>
                        <p class="mb-0 small" style="color: #1d4ed8; font-weight: 500; opacity: 0.9;">Estas afiliaciones están «En revisión» y esperan tu validación contra el padrón electoral.</p>
                    </div>
                </div>
                <i class="bi bi-chevron-right fs-5" style="color: #1d4ed8;"></i>
            </div>
        </a>
        <style>
            a.card:hover {
                transform: translateY(-2px);
                box-shadow: 0 6px 15px rgba(29, 78, 216, 0.08) !important;
            }
        </style>
HTML
    }

    my $total_afiliaciones_fmt = format_number($total_afiliaciones);
    my $pendientes_fmt = format_number($pendientes);
    my $verificadas_fmt = format_number($verificadas);
    my $rechazadas_fmt = format_number($rechazadas);

    $dashboard_content = <<"HTML";
        <!-- Welcome Card -->
        <div class="card border-0 shadow-sm rounded-4 mb-4">
            <div class="card-body p-4 p-md-5">
                <div class="row align-items-center">
                    <div class="col-lg-7 mb-4 mb-lg-0">
                        <div class="d-flex align-items-center mb-2 flex-wrap gap-2">
                            <h2 class="fw-bold text-dark mb-0">¡Hola, $first_name! 👋</h2>
                            <span class="badge rounded-pill bg-success-subtle text-success border border-success-subtle px-3 py-1.5" style="font-size: 0.75rem; font-weight: 500;">
                                <span class="d-inline-block rounded-circle bg-success me-1.5" style="width: 8px; height: 8px; animation: pulse 1.5s infinite;"></span>Sesión Activa
                            </span>
                        </div>
                        <p class="text-secondary mb-3 fs-6">
                            Bienvenido al Sistema de Registro de Afiliaciones del IEEQ. Tu rol es <strong>Funcionariado IEEQ</strong>.
                        </p>
                        <span class="badge rounded-pill px-3 py-1.5" style="background-color: #f3e8ff; color: #6B2D8B; font-weight: 600; font-size: 0.75rem; border: 1px solid #e9d5ff;">Funcionario IEEQ</span>
                    </div>
                    <div class="col-lg-5 text-lg-end d-flex gap-2 justify-content-lg-end flex-wrap">
                        <a href="listado_afiliados.pl?filtro=NUEVA" class="btn btn-ieeq px-4 py-2.5 rounded-pill d-inline-flex align-items-center gap-2">
                            <i class="bi bi-shield-check"></i> Verificar Registros
                            <span class="badge bg-white text-primary rounded-circle px-2 py-1" style="font-size: 0.75rem; background-color: #ffffff !important; color: #6B2D8B !important;">$pendientes</span>
                        </a>
                        <a href="listado_afiliados.pl" class="btn px-4 py-2.5 rounded-pill d-inline-flex align-items-center gap-2" style="background-color: #3b174a; color: white; border: 1px solid #3b174a;">
                            <i class="bi bi-search"></i> Consultar Registros
                        </a>
                    </div>
                </div>
            </div>
        </div>

        $alert_banner_html

        <!-- KPI Cards Grid -->
        <div class="row mb-4 g-3">
            <div class="col-lg-3 col-sm-6">
                <div class="card border-0 shadow-sm rounded-4 text-white h-100 position-relative overflow-hidden" style="background-color: #4C1D95; padding: 1.5rem;">
                    <div class="d-flex justify-content-between align-items-start mb-3">
                        <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 44px; height: 44px; background-color: rgba(255, 255, 255, 0.2) !important;">
                            <i class="bi bi-people fs-4 text-white"></i>
                        </div>
                        <div class="text-white-50"><i class="bi bi-arrow-up-right fs-5 opacity-75"></i></div>
                    </div>
                    <h3 class="display-5 fw-bold mb-1 font-monospace">$total_afiliaciones_fmt</h3>
                    <div class="fw-bold mb-1" style="font-size: 0.95rem;">Total Afiliaciones</div>
                    <span class="text-white-50" style="font-size: 0.75rem;">en el sistema</span>
                </div>
            </div>
            <div class="col-lg-3 col-sm-6">
                <div class="card border-0 shadow-sm rounded-4 text-white h-100 position-relative overflow-hidden" style="background-color: #2563eb; padding: 1.5rem;">
                    <div class="d-flex justify-content-between align-items-start mb-3">
                        <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 44px; height: 44px; background-color: rgba(255, 255, 255, 0.2) !important;">
                            <i class="bi bi-shield fs-4 text-white"></i>
                        </div>
                        <div class="text-white-50"><i class="bi bi-arrow-up-right fs-5 opacity-75"></i></div>
                    </div>
                    <h3 class="display-5 fw-bold mb-1 font-monospace">$pendientes_fmt</h3>
                    <div class="fw-bold mb-1" style="font-size: 0.95rem;">Pendientes de verificar</div>
                    <span class="text-white-50" style="font-size: 0.75rem;">esperan tu revisión</span>
                </div>
            </div>
            <div class="col-lg-3 col-sm-6">
                <div class="card border-0 shadow-sm rounded-4 text-white h-100 position-relative overflow-hidden" style="background-color: #10B981; padding: 1.5rem;">
                    <div class="d-flex justify-content-between align-items-start mb-3">
                        <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 44px; height: 44px; background-color: rgba(255, 255, 255, 0.2) !important;">
                            <i class="bi bi-check-circle fs-4 text-white"></i>
                        </div>
                        <div class="text-white-50"><i class="bi bi-arrow-up-right fs-5 opacity-75"></i></div>
                    </div>
                    <h3 class="display-5 fw-bold mb-1 font-monospace">$verificadas_fmt</h3>
                    <div class="fw-bold mb-1" style="font-size: 0.95rem;">Verificadas por IEEQ</div>
                    <span class="text-white-50" style="font-size: 0.75rem;">localizadas en padrón</span>
                </div>
            </div>
            <div class="col-lg-3 col-sm-6">
                <div class="card border-0 shadow-sm rounded-4 text-white h-100 position-relative overflow-hidden" style="background-color: #EF4444; padding: 1.5rem;">
                    <div class="d-flex justify-content-between align-items-start mb-3">
                        <div class="rounded-circle d-flex align-items-center justify-content-center" style="width: 44px; height: 44px; background-color: rgba(255, 255, 255, 0.2) !important;">
                            <i class="bi bi-x-circle fs-4 text-white"></i>
                        </div>
                        <div class="text-white-50"><i class="bi bi-arrow-up-right fs-5 opacity-75"></i></div>
                    </div>
                    <h3 class="display-5 fw-bold mb-1 font-monospace">$rechazadas_fmt</h3>
                    <div class="fw-bold mb-1" style="font-size: 0.95rem;">Rechazadas</div>
                    <span class="text-white-50" style="font-size: 0.75rem;">no localizadas</span>
                </div>
            </div>
        </div>

        <!-- Acciones Rápidas and Capacidades Grid -->
        <div class="row mb-4 g-3">
            <div class="col-lg-5">
                <div class="card border-0 shadow-sm rounded-4 p-4 h-100">
                    <h5 class="fw-bold text-dark mb-4">Acciones rápidas</h5>
                    <div class="d-flex flex-column gap-3">
                        <a href="listado_afiliados.pl?filtro=NUEVA" class="quick-action-card d-flex align-items-center justify-content-between p-3 rounded-4 text-decoration-none transition" style="background-color: #FAF5FF; border: 1px solid #F3E8FF;">
                            <div class="d-flex align-items-center flex-grow-1">
                                <div class="rounded-circle d-flex align-items-center justify-content-center text-white" style="width: 44px; height: 44px; background-color: #6B2D8B; flex-shrink: 0;">
                                    <i class="bi bi-shield-check fs-5"></i>
                                </div>
                                <div class="ms-3 flex-grow-1">
                                    <div class="d-flex align-items-center justify-content-between">
                                        <div class="fw-bold text-dark" style="font-size: 0.95rem;">Verificar Registros</div>
                                        <span class="badge rounded-circle bg-primary px-2 py-1" style="font-size: 0.75rem; background-color: #2563eb !important; color: white !important;">$pendientes</span>
                                    </div>
                                    <div class="text-secondary" style="font-size: 0.75rem;">Verificar en el padrón electoral</div>
                                </div>
                            </div>
                            <i class="bi bi-arrow-right text-secondary fs-5 ms-3"></i>
                        </a>
                        <a href="listado_afiliados.pl" class="quick-action-card d-flex align-items-center justify-content-between p-3 rounded-4 text-decoration-none transition" style="background-color: #FAF5FF; border: 1px solid #F3E8FF;">
                            <div class="d-flex align-items-center">
                                <div class="rounded-circle d-flex align-items-center justify-content-center text-white" style="width: 44px; height: 44px; background-color: #6B2D8B; flex-shrink: 0;">
                                    <i class="bi bi-search fs-5"></i>
                                </div>
                                <div class="ms-3">
                                    <div class="fw-bold text-dark" style="font-size: 0.95rem;">Consultar Registros</div>
                                    <div class="text-secondary" style="font-size: 0.75rem;">Vista completa de afiliaciones</div>
                                </div>
                            </div>
                            <i class="bi bi-arrow-right text-secondary fs-5 me-1"></i>
                        </a>
                        <a href="cedulas.pl" class="quick-action-card d-flex align-items-center justify-content-between p-3 rounded-4 text-decoration-none transition" style="background-color: #FAF5FF; border: 1px solid #F3E8FF;">
                            <div class="d-flex align-items-center">
                                <div class="rounded-circle d-flex align-items-center justify-content-center text-white" style="width: 44px; height: 44px; background-color: #6B2D8B; flex-shrink: 0;">
                                    <i class="bi bi-award-fill fs-5"></i>
                                </div>
                                <div class="ms-3">
                                    <div class="fw-bold text-dark" style="font-size: 0.95rem;">Generar Cédulas</div>
                                    <div class="text-secondary" style="font-size: 0.75rem;">Emitir cédulas de afiliados</div>
                                </div>
                            </div>
                            <i class="bi bi-arrow-right text-secondary fs-5 me-1"></i>
                        </a>
                        <a href="auditoria.pl" class="quick-action-card d-flex align-items-center justify-content-between p-3 rounded-4 text-decoration-none transition" style="background-color: #FAF5FF; border: 1px solid #F3E8FF;">
                            <div class="d-flex align-items-center">
                                <div class="rounded-circle d-flex align-items-center justify-content-center text-white" style="width: 44px; height: 44px; background-color: #6B2D8B; flex-shrink: 0;">
                                    <i class="bi bi-journal-text fs-5"></i>
                                </div>
                                <div class="ms-3">
                                    <div class="fw-bold text-dark" style="font-size: 0.95rem;">Bitácora</div>
                                    <div class="text-secondary" style="font-size: 0.75rem;">Revisión de operaciones</div>
                                </div>
                            </div>
                            <i class="bi bi-arrow-right text-secondary fs-5 me-1"></i>
                        </a>
                    </div>
                </div>
            </div>
            <div class="col-lg-7">
                <div class="card border-0 shadow-sm rounded-4 p-4 h-100">
                    <h5 class="fw-bold text-dark mb-4">Capacidades de tu rol</h5>
                    <div class="row g-3">
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA;">
                                <div class="text-success me-3 fs-4 d-flex align-items-center justify-content-center bg-success bg-opacity-10 rounded-circle" style="width: 36px; height: 36px; color: #6B2D8B !important; background-color: rgba(107,45,139,0.1) !important;">
                                    <i class="bi bi-check-circle-fill"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Consultar todos los registros</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Vista completa del sistema en modo lectura</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA;">
                                <div class="text-success me-3 fs-4 d-flex align-items-center justify-content-center bg-success bg-opacity-10 rounded-circle" style="width: 36px; height: 36px; color: #6B2D8B !important; background-color: rgba(107,45,139,0.1) !important;">
                                    <i class="bi bi-check-circle-fill"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Verificar afiliaciones</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Localizar en el padrón electoral del estado</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA;">
                                <div class="text-success me-3 fs-4 d-flex align-items-center justify-content-center bg-success bg-opacity-10 rounded-circle" style="width: 36px; height: 36px; color: #6B2D8B !important; background-color: rgba(107,45,139,0.1) !important;">
                                    <i class="bi bi-check-circle-fill"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Rechazar afiliaciones</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Marcar como no localizadas en el padrón</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA;">
                                <div class="text-success me-3 fs-4 d-flex align-items-center justify-content-center bg-success bg-opacity-10 rounded-circle" style="width: 36px; height: 36px; color: #6B2D8B !important; background-color: rgba(107,45,139,0.1) !important;">
                                    <i class="bi bi-check-circle-fill"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Generar cédulas</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Emitir cédulas de afiliados verificados</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA; opacity: 0.6;">
                                <div class="text-secondary me-3 fs-4 d-flex align-items-center justify-content-center bg-secondary bg-opacity-10 rounded-circle" style="width: 36px; height: 36px;">
                                    <i class="bi bi-dash-circle"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Capturar afiliaciones</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Solo disponible para la Asociación</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="d-flex align-items-center p-3 rounded-4" style="background-color: #F8F9FA; opacity: 0.6;">
                                <div class="text-secondary me-3 fs-4 d-flex align-items-center justify-content-center bg-secondary bg-opacity-10 rounded-circle" style="width: 36px; height: 36px;">
                                    <i class="bi bi-dash-circle"></i>
                                </div>
                                <div>
                                    <div class="fw-bold text-dark style-role-capability" style="font-size: 0.85rem;">Gestionar usuarios</div>
                                    <div class="text-secondary" style="font-size: 0.7rem;">Solo disponible para el Administrador</div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Recent Activity Table Card -->
        <div class="card border-0 shadow-sm rounded-4 p-4 bg-white mb-4">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h5 class="fw-bold text-dark mb-0">Actividad Reciente</h5>
                <a href="auditoria.pl" class="text-decoration-none fw-semibold" style="color: #6B2D8B; font-size: 0.9rem;">Ver bitácora completa &rarr;</a>
            </div>
            <div class="table-responsive">
                <table class="table table-hover align-middle mb-0">
                    <thead>
                        <tr class="table-light">
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Fecha / Hora</th>
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Usuario</th>
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Acción</th>
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Módulo</th>
                            <th class="py-3 text-muted text-uppercase fw-semibold" style="font-size: 0.75rem;">Detalle</th>
                        </tr>
                    </thead>
                    <tbody>
                        $rows_recientes_html
                    </tbody>
                </table>
            </div>
        </div>
HTML
}

# Cabeceras anti-caché de alta seguridad
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
    <title>Dashboard - IEEQ</title>
    <!-- Bootstrap 5 -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <!-- Bootstrap Icons -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons\@1.11.3/font/bootstrap-icons.min.css">
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
            display: flex;
            flex-direction: column;
        }
        .sidebar-header {
            padding: 1.5rem;
            text-align: center;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .sidebar-header h3 {
            font-weight: 700;
            letter-spacing: 2px;
            margin-bottom: 5px;
            font-size: 1.5rem;
        }
        .sidebar-header p {
            font-size: 0.8rem;
            opacity: 0.8;
            margin: 0;
        }
        .nav-pills .nav-link {
            border-radius: 0;
            padding: 12px 20px;
            font-weight: 400;
            opacity: 0.85;
            transition: all 0.2s;
            color: white;
            font-size: 0.9rem;
            border-left: 4px solid transparent;
        }
        .nav-pills .nav-link:hover {
            opacity: 1;
            background-color: rgba(255,255,255,0.08);
            border-left: 4px solid rgba(255,255,255,0.5);
            color: white;
        }
        .nav-pills .nav-link.active {
            background-color: rgba(255,255,255,0.15);
            opacity: 1;
            border-left: 4px solid #ffffff;
            font-weight: 600;
            color: white;
        }
        
        /* User Profile Section in Sidebar */
        .user-section {
            padding: 1.25rem;
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
            font-size: 0.72rem;
            text-transform: uppercase;
            letter-spacing: 0.5px;
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

        /* Card styles & hover effects */
        .quick-action-card {
            transition: all 0.3s ease;
        }
        .quick-action-card:hover {
            transform: translateY(-3px);
            box-shadow: 0 8px 20px rgba(107,45,139,0.08);
            border-color: #d8b4fe !important;
            background-color: #FDFEFE !important;
        }
        .btn-ieeq {
            background-color: #6B2D8B;
            color: white;
            transition: all 0.2s ease;
        }
        .btn-ieeq:hover {
            background-color: #53236c;
            color: white;
            box-shadow: 0 4px 12px rgba(107,45,139,0.25);
        }
        .style-role-capability {
            letter-spacing: 0.3px;
        }
        
        /* Keyframe for Active pulse */
        \@keyframes pulse {
            0% { transform: scale(0.95); opacity: 0.5; }
            50% { transform: scale(1.1); opacity: 1; }
            100% { transform: scale(0.95); opacity: 0.5; }
        }
        
        /* Mobile fixes */
        .mobile-overlay {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100vw;
            height: 100vh;
            background: rgba(0,0,0,0.4);
            z-index: 999;
        }
        \@media (max-width: 991px) {
            #sidebar {
                left: -280px;
            }
            #sidebar.active {
                left: 0;
            }
            #content {
                margin-left: 0;
                padding: 1.5rem;
            }
            .mobile-overlay.active {
                display: block;
            }
        }
    </style>
</head>
<body>

HTML

# --- Sidebar compartido ---
if ($rol eq 'administrador' || $rol eq 'funcionario' || $rol eq 'integrante_organizacion') {
    require "$FindBin::Bin/_sidebar_admin.pl";
}

print <<"HTML";

    <!-- Main Content -->
    <div id="content">
        <div class="top-header">
            <div class="d-flex align-items-center">
                <button id="sidebarToggle" class="btn btn-outline-secondary d-lg-none me-3" type="button" style="border-radius: 8px;">
                    <i class="bi bi-list"></i>
                </button>
                <h4 class="mb-0 text-dark fw-bold">Dashboard Principal</h4>
            </div>
            <div class="text-muted d-none d-md-block">
                Instituto Electoral del Estado de Querétaro
            </div>
        </div>

        <!-- Contenido dinámico del Dashboard -->
        $dashboard_content
        
    </div>

    <!-- Bootstrap 5 Bundle -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    <!-- SweetAlert2 -->
    <script src="https://cdn.jsdelivr.net/npm/sweetalert2\@11"></script>
    
    <script>
        // (sidebar toggle y logout son manejados por _sidebar_admin.pl)
HTML

if ($rol eq 'administrador') {
    # Solo agregar el script de animación de barra si es administrador
    print <<"ANIMATION_JS";
        // Animación de la barra de progreso
        function animarBarra(porcentajeReal) {
            const barra = document.getElementById('barraProgreso');
            const contador = document.getElementById('contadorPorcentaje');
            if (!barra || !contador) return;
            
            let inicio = 0;
            const duracion = 1500;
            const startTime = performance.now();
            
            function step(currentTime) {
                const elapsed = currentTime - startTime;
                const progreso = Math.min(elapsed / duracion, 1);
                const easeOut = 1 - Math.pow(1 - progreso, 3);
                const actual = inicio + (porcentajeReal - inicio) * easeOut;
                
                barra.style.width = actual + '%';
                contador.textContent = actual.toFixed(1) + '%';
                
                if (progreso < 1) {
                    requestAnimationFrame(step);
                }
            }
            requestAnimationFrame(step);
        }
        
        // Ejecutar animación cuando cargue la página
        window.addEventListener('DOMContentLoaded', () => {
            animarBarra($pct_avance_fmt);
        });
ANIMATION_JS
}

print <<"HTML";
    </script>
</body>
</html>
HTML
