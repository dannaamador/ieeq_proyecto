# _sidebar_admin.pl — Sidebar compartido para el rol ADMINISTRADOR
# IMPORTANTE: use utf8 es OBLIGATORIO para que los acentos se rendericen bien
use strict;
use warnings;
use utf8;
use CGI;
use CGI::Session;
use FindBin;
use File::Basename;

# ──────────────────────────────────────────────────
# Inicializar sesión y recuperar datos del usuario
# ──────────────────────────────────────────────────
my $_cgi = CGI->new;
my $_sess = CGI::Session->new(undef, $_cgi, {Directory => "$FindBin::Bin/.sesiones"});
my $_user_name = $_sess->param('nombre_completo') || 'Administrador';

# Calcular iniciales del usuario
my $_clean_name = $_user_name;
$_clean_name =~ s/^\s+|\s+$//g;
my @_name_parts = split /\s+/, $_clean_name;
my $_initials = '';
if (@_name_parts > 0) {
    $_initials .= uc(substr($_name_parts[0], 0, 1));
    if (@_name_parts > 1) {
        $_initials .= uc(substr($_name_parts[1], 0, 1));
    }
}
$_initials ||= 'A';

# Calcular color de avatar basado en el nombre
my @_av_colors = ('#7c3aed', '#2563eb', '#059669', '#db2777', '#0dcaf0', '#6f42c1', '#d97706');
my $_char_sum = 0;
$_char_sum += ord($_) for split //, $_user_name;
my $_avatar_color = $_av_colors[$_char_sum % scalar(@_av_colors)];

# Detectar el nombre del script actual automáticamente
my $_current_script = basename($0);

my $_rol = $_sess->param('rol') || '';

# ──────────────────────────────────────────────────
# Definición del menú y rol dinámico
# ──────────────────────────────────────────────────
my @_menu_items = ();
our $_rol_label = 'Usuario';

if ($_rol eq 'administrador') {
    $_rol_label = 'Administrador de Asociación';
    @_menu_items = (
        { clave => 'INICIO',     href => 'dashboard.pl',        icon => 'bi-house',        label => 'Inicio'               },
        { clave => 'USUARIOS',   href => 'gestion_usuarios.pl', icon => 'bi-people',       label => 'Gestión de Usuarios'  },
        { clave => 'PERMISOS',   href => 'gestion_permisos.pl', icon => 'bi-shield-lock',  label => 'Gestión de Permisos'  },
        { clave => 'ASOCIACION', href => 'asociacion.pl',       icon => 'bi-building',     label => 'Asociación'           },
        { clave => 'LISTADO',    href => 'listado_afiliados.pl',icon => 'bi-list-ul',      label => 'Listado de Afiliados' },
        { clave => 'CEDULAS',    href => 'cedulas.pl',          icon => 'bi-award',        label => 'Cédulas'              },
        { clave => 'BITACORA',   href => 'auditoria.pl',        icon => 'bi-journal-text', label => 'Bitácora'             },
    );
} elsif ($_rol eq 'funcionario') {
    $_rol_label = 'Funcionariado IEEQ';
    @_menu_items = (
        { clave => 'INICIO',      href => 'dashboard.pl',              icon => 'bi-house',        label => 'Inicio'               },
        { clave => 'CONSULTA',    href => 'listado_afiliados.pl',      icon => 'bi-search',       label => 'Consulta de Registros'},
        { clave => 'VERIFICACION',href => 'listado_afiliados.pl?filtro=NUEVA',icon => 'bi-shield-check',  label => 'Verificación'         },
        { clave => 'CEDULAS',     href => 'cedulas.pl',                icon => 'bi-award',        label => 'Cédulas'              },
        { clave => 'BITACORA',    href => 'auditoria.pl',              icon => 'bi-journal-text', label => 'Bitácora'             },
    );
} elsif ($_rol eq 'integrante_organizacion') {
    $_rol_label = 'Persona Auxiliar';
    @_menu_items = (
        { clave => 'INICIO',     href => 'dashboard.pl',         icon => 'bi-house',        label => 'Inicio'               },
        { clave => 'REGISTRO',   href => 'registro_afiliados.pl',icon => 'bi-person-plus',  label => 'Registro de Afiliaciones'},
        { clave => 'CONSULTA',   href => 'listado_afiliados.pl', icon => 'bi-file-earmark-check', label => 'Mis Registros'},
    );
}

# ──────────────────────────────────────────────────
# Construir el HTML de los ítems del menú
# ──────────────────────────────────────────────────
my $_menu_html = '';
for my $_item (@_menu_items) {
    # El ítem está activo si el script actual coincide con su href
    my $_href_base = $_item->{href};
    $_href_base =~ s/\?.*//;
    my $_active = 0;
    if ($_current_script eq $_href_base) {
        my $_filtro_param = $_cgi->param('filtro') || '';
        if ($_item->{clave} eq 'VERIFICACION') {
            $_active = ($_filtro_param eq 'NUEVA');
        } elsif ($_item->{clave} eq 'CONSULTA') {
            $_active = ($_filtro_param ne 'NUEVA');
        } else {
            $_active = 1;
        }
    }

    my $_li_class  = 'nav-item';
    my $_a_extra   = '';
    my $_chevron   = '';

    if ($_active) {
        # Estado activo: borde blanco, fondo semi-transparente, cápsula (border-radius: 50px) y chevron
        $_a_extra = ' style="background: rgba(255,255,255,0.15) !important; border: 2px solid #ffffff !important; color: #ffffff !important; font-weight: 600;"';
        $_chevron = '<i class="bi bi-chevron-right ms-auto" style="font-size: 0.8rem; margin-right: 2px;"></i>';
    } else {
        # Estado inactivo
        $_a_extra = ' style="color: rgba(255,255,255,0.78) !important;"';
    }

    $_menu_html .= sprintf(
        '<li class="%s"><a href="%s" class="nav-link sidebar-nav-link d-flex align-items-center"%s>'
        . '<i class="bi %s me-3"></i>'
        . '<span class="sidebar-label">%s</span>'
        . '%s'
        . '</a></li>' . "\n",
        $_li_class,
        $_item->{href},
        $_a_extra,
        $_item->{icon},
        $_item->{label},
        $_chevron
    );
}

# ──────────────────────────────────────────────────
# Imprimir el HTML de la barra lateral
# ──────────────────────────────────────────────────
print <<"SIDEBAR_HTML";
    <!-- Mobile Overlay -->
    <div class="mobile-overlay"></div>

    <!-- ===== SIDEBAR ADMIN ===== -->
    <nav id="sidebar">

        <!-- Logo -->
        <div class="sidebar-header">
            <div class="d-flex align-items-center gap-2">
                <div class="sidebar-logo-icon">
                    <i class="bi bi-shield fs-4 text-white"></i>
                </div>
                <div>
                    <div class="fw-bold text-white" style="font-size:1.25rem; letter-spacing:1px;">IEEQ</div>
                    <div style="font-size:0.72rem; color:rgba(255,255,255,0.65);">Sistema de Registro</div>
                </div>
            </div>
        </div>

        <!-- Menú -->
        <div class="sidebar-menu-label">MENÚ PRINCIPAL</div>

        <ul class="nav flex-column sidebar-nav px-2">
            $_menu_html
        </ul>

        <!-- Usuario + Logout -->
        <div class="user-section mt-auto">
            <div class="d-flex align-items-center mb-3">
                <div class="sidebar-avatar flex-shrink-0" style="background-color: $_avatar_color;">
                    $_initials
                </div>
                <div class="ms-3" style="min-width:0; overflow:hidden;">
                    <div class="user-name text-white" title="$_user_name">$_user_name</div>
                    <div class="user-role">$_rol_label</div>
                </div>
            </div>
            <a href="#" id="btnLogout" class="logout-link d-flex align-items-center gap-2">
                <i class="bi bi-box-arrow-right"></i>Cerrar Sesión
            </a>
        </div>
    </nav>

    <!-- Estilos del sidebar -->
    <style>
        /* ── Sidebar base ── */
        #sidebar {
            width: 260px;
            height: 100vh;
            position: fixed;
            top: 0; left: 0;
            background: linear-gradient(180deg, #6B2D8B 0%, #4a1f61 100%);
            display: flex;
            flex-direction: column;
            z-index: 1000;
            box-shadow: 4px 0 20px rgba(0,0,0,0.18);
            overflow: hidden;
        }
        #content { margin-left: 260px; min-height: 100vh; transition: margin-left 0.3s ease; }

        /* ── Logo ── */
        .sidebar-header {
            padding: 1.1rem 1.1rem 0.9rem;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .sidebar-logo-icon {
            width: 34px; height: 34px;
            background: rgba(255,255,255,0.15);
            border-radius: 8px;
            display: flex; align-items: center; justify-content: center;
        }

        /* ── Etiqueta de sección ── */
        .sidebar-menu-label {
            padding: 0.8rem 1.1rem 0.2rem;
            font-size: 0.62rem;
            font-weight: 700;
            letter-spacing: 1.2px;
            color: rgba(255,255,255,0.4);
            text-transform: uppercase;
        }

        /* ── Ítems de navegación ── */
        .sidebar-nav {
            flex: 1;
            overflow-y: auto;
            overflow-x: hidden;
        }
        .sidebar-nav .nav-item { margin: 1px 0; }
        .sidebar-nav-link {
            padding: 8px 14px;
            margin: 2px 10px;
            border-radius: 50px;
            transition: all 0.2s ease;
            font-size: 0.85rem;
            font-family: 'Outfit', sans-serif;
            border: 2px solid transparent;
            display: flex;
            align-items: center;
            text-decoration: none !important;
        }
        .sidebar-nav-link:hover {
            background: rgba(255,255,255,0.08) !important;
            color: #fff !important;
            transform: translateX(2px);
        }
        .sidebar-nav-link i {
            font-size: 1rem;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            margin-right: 10px;
        }

        /* ── Sección usuario ── */
        .user-section {
            padding: 1.1rem 1.1rem;
            border-top: 1px solid rgba(255,255,255,0.08);
            background: rgba(0,0,0,0.1);
        }
        .sidebar-avatar {
            width: 38px; height: 38px;
            border-radius: 50%;
            display: flex; align-items: center; justify-content: center;
            font-weight: 700;
            font-size: 0.9rem;
            color: #fff;
            flex-shrink: 0;
        }
        .user-name {
            font-weight: 600;
            font-size: 0.9rem;
            line-height: 1.2;
            margin-bottom: 2px;
            word-break: break-word;
        }
        .user-role {
            font-size: 0.7rem;
            color: rgba(255,255,255,0.55);
            line-height: 1.2;
        }
        .logout-link {
            color: rgba(255,255,255,0.7) !important;
            font-size: 0.82rem;
            font-weight: 500;
            text-decoration: none !important;
            transition: color 0.2s ease;
            margin-top: 8px;
            display: inline-flex;
            align-items: center;
        }
        .logout-link:hover {
            color: #fff !important;
        }

        /* ── Mobile overlay ── */
        .mobile-overlay {
            display: none;
            position: fixed; top:0; left:0;
            width: 100vw; height: 100vh;
            background: rgba(0,0,0,0.45);
            z-index: 999;
        }
        \@media (max-width: 991px) {
            #sidebar { left: -260px; transition: left 0.3s ease; }
            #sidebar.active { left: 0; }
            #content { margin-left: 0 !important; }
            .mobile-overlay.active { display: block; }
        }
    </style>
SIDEBAR_HTML

# ──────────────────────────────────────────────────
# Script: logout con SweetAlert2 + toggle móvil
# ──────────────────────────────────────────────────
print <<'LOGOUT_JS';
<script>
(function () {
    'use strict';

    /* --- Logout con SweetAlert2 --- */
    var btnLogout = document.getElementById('btnLogout');
    if (btnLogout) {
        btnLogout.addEventListener('click', function (e) {
            e.preventDefault();
            Swal.fire({
                title: '¿Cerrar Sesión?',
                text: '¿Está seguro de que desea salir del sistema?',
                icon: 'question',
                showCancelButton: true,
                confirmButtonColor: '#6B2D8B',
                cancelButtonColor: '#6c757d',
                confirmButtonText: 'Sí, salir',
                cancelButtonText: 'Cancelar',
                customClass: { popup: 'rounded-4 border-0 shadow' }
            }).then(function (result) {
                if (result.isConfirmed) {
                    window.location.href = 'dashboard.pl?logout=1';
                }
            });
        });
    }

    /* --- Toggle lateral en móvil --- */
    var toggle  = document.getElementById('sidebarToggle');
    var sidebar = document.getElementById('sidebar');
    var overlay = document.querySelector('.mobile-overlay');
    if (toggle && sidebar && overlay) {
        toggle.addEventListener('click', function () {
            sidebar.classList.toggle('active');
            overlay.classList.toggle('active');
        });
        overlay.addEventListener('click', function () {
            sidebar.classList.remove('active');
            overlay.classList.remove('active');
        });
    }
})();
</script>
LOGOUT_JS
