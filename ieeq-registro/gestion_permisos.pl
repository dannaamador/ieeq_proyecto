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

# Configurar salida UTF-8
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

if ($rol ne 'administrador') {
    print $cgi->redirect(-uri => 'dashboard.pl');
    exit;
}

my $accion = $cgi->param('accion') || '';

# ==========================================
# ENDPOINT: get_usuarios
# ==========================================
if ($accion eq 'get_usuarios') {
    my @usuarios = execute_query_list(
        "SELECT id_usuario, CONCAT(nombre,' ',apellido_paterno,COALESCE(CONCAT(' ',apellido_materno),'')) AS nombre_completo,
                correo_electronico, tipo_usuario
         FROM usuarios WHERE activo = 1 ORDER BY nombre_completo ASC"
    );
    print $cgi->header(-type => 'application/json', -charset => 'utf-8');
    print encode_json({ success => 1, usuarios => \@usuarios });
    exit;
}

# ==========================================
# ENDPOINT: get_permisos
# ==========================================
if ($accion eq 'get_permisos') {
    my $id_usuario = $cgi->param('id_usuario');
    if ($id_usuario) {
        # Intentar cargar módulos desde la tabla (si existe)
        my @modulos = execute_query_list(
            "SELECT id_modulo, nombre_modulo FROM modulos_sistema ORDER BY id_modulo ASC"
        );
        # Si no existe la tabla modulos_sistema, usar listado hardcodeado
        if (!@modulos) {
            @modulos = (
                { id_modulo => 1,  nombre_modulo => 'Gestión de Usuarios'      },
                { id_modulo => 2,  nombre_modulo => 'Gestión de Permisos'      },
                { id_modulo => 3,  nombre_modulo => 'Asociación'               },
                { id_modulo => 4,  nombre_modulo => 'Padrón de Referencia'     },
                { id_modulo => 5,  nombre_modulo => 'Registro de Afiliaciones' },
                { id_modulo => 6,  nombre_modulo => 'Listado de Afiliados'     },
                { id_modulo => 7,  nombre_modulo => 'Cédulas'                  },
                { id_modulo => 8,  nombre_modulo => 'Bitácora'                 },
                { id_modulo => 9,  nombre_modulo => 'Verificación'             },
            );
        }
        # Intentar permisos con columna id_modulo (v3)
        my @permisos = execute_query_list(
            "SELECT id_modulo, puede_ver, puede_editar FROM permisos_usuario WHERE id_usuario = ?",
            $id_usuario
        );
        # Fallback: intentar con id_opcion (v2 legacy)
        if (!@permisos) {
            @permisos = execute_query_list(
                "SELECT id_opcion AS id_modulo, puede_ver, puede_editar FROM permisos_usuario WHERE id_usuario = ?",
                $id_usuario
            );
        }
        my %perm_hash;
        for my $p (@permisos) {
            my $key = $p->{id_modulo} // $p->{id_opcion};
            $perm_hash{$key} = {
                puede_ver    => $p->{puede_ver}    ? 1 : 0,
                puede_editar => $p->{puede_editar} ? 1 : 0
            };
        }
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 1, modulos => \@modulos, permisos => \%perm_hash });
        exit;
    }
    print $cgi->header(-type => 'application/json', -charset => 'utf-8');
    print encode_json({ success => 0, message => 'ID de usuario no proporcionado' });
    exit;
}

# ==========================================
# ENDPOINT: save_permisos
# ==========================================
if ($accion eq 'save_permisos') {
    my $id_usuario    = $cgi->param('id_usuario');
    my $permisos_json = $cgi->param('permisos_json');

    if ($id_usuario && $permisos_json) {
        my $permisos;
        eval { $permisos = decode_json($permisos_json); };
        if ($@) {
            print $cgi->header(-type => 'application/json', -charset => 'utf-8');
            print encode_json({ success => 0, message => 'JSON inválido' });
            exit;
        }

        my $errors = 0;

        # Detectar columna disponible (id_modulo v3 o id_opcion legacy)
        my @existentes_mod = execute_query_list(
            "SELECT id_modulo FROM permisos_usuario WHERE id_usuario = ?", $id_usuario
        );
        my @existentes_op = ();
        if (!@existentes_mod) {
            @existentes_op = execute_query_list(
                "SELECT id_opcion FROM permisos_usuario WHERE id_usuario = ?", $id_usuario
            );
        }

        my %tiene_reg;
        if (@existentes_mod) {
            $tiene_reg{$_->{id_modulo}} = 1 for @existentes_mod;
        } else {
            $tiene_reg{$_->{id_opcion}} = 1 for @existentes_op;
        }

        my $use_modulo_col = @existentes_mod ? 1 : 0;

        for my $p (@$permisos) {
            my $id_mod = $p->{id_modulo};
            my $ver    = $p->{puede_ver}    ? 1 : 0;
            my $editar = $p->{puede_editar} ? 1 : 0;

            if ($use_modulo_col) {
                if ($tiene_reg{$id_mod}) {
                    my $sql = "UPDATE permisos_usuario SET puede_ver=?, puede_editar=? WHERE id_usuario=? AND id_modulo=?";
                    $errors++ unless execute_query_write($sql, $ver, $editar, $id_usuario, $id_mod);
                } else {
                    my $sql = "INSERT INTO permisos_usuario (id_usuario, id_modulo, puede_ver, puede_editar) VALUES (?, ?, ?, ?)";
                    $errors++ unless execute_query_write($sql, $id_usuario, $id_mod, $ver, $editar);
                }
            } else {
                # Legacy: id_opcion
                if ($tiene_reg{$id_mod}) {
                    my $sql = "UPDATE permisos_usuario SET puede_ver=?, puede_editar=? WHERE id_usuario=? AND id_opcion=?";
                    $errors++ unless execute_query_write($sql, $ver, $editar, $id_usuario, $id_mod);
                } else {
                    my $sql = "INSERT INTO permisos_usuario (id_usuario, id_opcion, puede_ver, puede_editar) VALUES (?, ?, ?, ?)";
                    $errors++ unless execute_query_write($sql, $id_usuario, $id_mod, $ver, $editar);
                }
            }
        }


        # Registrar en bitácora
        my $id_sess_user = $session->param('id_usuario') || 0;
        execute_query_write(
            "INSERT INTO bitacora (id_usuario, accion, modulo, detalles, fecha) VALUES (?, 'EDICION', 'permisos_usuario', ?, NOW())",
            $id_sess_user,
            "Permisos actualizados para usuario ID $id_usuario"
        );

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
# Cargar lista inicial de usuarios para el selector
my @todos_usuarios = execute_query_list(
    "SELECT id_usuario,
            CONCAT(nombre,' ',apellido_paterno,COALESCE(CONCAT(' ',apellido_materno),'')) AS nombre_completo,
            correo_electronico, tipo_usuario
     FROM usuarios WHERE activo = 1 ORDER BY nombre_completo ASC"
);
my $usuarios_json = encode_json(\@todos_usuarios);

# Para el sidebar
my $pagina_activa = 'PERMISOS';

print $cgi->header(
    -type         => 'text/html',
    -charset      => 'utf-8',
    -expires      => 'now',
    -Cache_Control => 'no-store, no-cache, must-revalidate, max-age=0',
    -Pragma       => 'no-cache'
);

print <<"HTML";
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Gestión de Permisos - IEEQ</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons\@1.11.3/font/bootstrap-icons.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght\@300;400;500;600;700&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/sweetalert2\@11"></script>
    <style>
        * { box-sizing: border-box; }
        body { font-family: 'Outfit', sans-serif; background-color: #f5f5f8; overflow-x: hidden; margin: 0; }
        #content { margin-left: 260px; min-height: 100vh; padding: 2rem; transition: margin-left 0.3s ease; }

        /* ── Top header ── */
        .page-header {
            display: flex; justify-content: space-between; align-items: center;
            background: #fff; padding: 1rem 1.5rem; border-radius: 14px;
            box-shadow: 0 2px 12px rgba(0,0,0,0.05); margin-bottom: 1.5rem;
        }
        .page-header h4 { margin: 0; font-weight: 700; color: #1a1a2e; font-size: 1.3rem; }
        .page-header p  { margin: 0; color: #6c757d; font-size: 0.85rem; }

        /* ── Cards ── */
        .card-ieeq {
            background: #fff; border: none; border-radius: 14px;
            box-shadow: 0 2px 16px rgba(0,0,0,0.06);
        }

        /* ══════════════════════════════════════
           SELECTOR DE USUARIO COMBINADO
           ══════════════════════════════════════ */
        .selector-wrap { position: relative; }

        /* El "trigger" que aparece como dropdown de Bootstrap */
        .selector-trigger {
            display: flex; align-items: center; gap: 10px;
            padding: 0.7rem 1rem; border: 1.5px solid #e0e0e0; border-radius: 12px;
            cursor: pointer; transition: border-color .2s, box-shadow .2s;
            background: #fff; user-select: none;
        }
        .selector-trigger:hover { border-color: #6B2D8B; }
        .selector-trigger.open  { border-color: #6B2D8B; box-shadow: 0 0 0 3px rgba(107,45,139,.12); }
        .trig-avatar {
            width: 36px; height: 36px; border-radius: 50%; flex-shrink: 0;
            display: flex; align-items: center; justify-content: center;
            font-weight: 700; font-size: 0.85rem; color: #fff;
        }
        .trig-placeholder { color: #9e9e9e; font-size: 0.9rem; flex: 1; }
        .trig-name  { font-weight: 700; font-size: 0.9rem; color: #1a1a2e; flex: 1; line-height:1.2; }
        .trig-sub   { font-size: 0.72rem; color: #9e9e9e; }
        .trig-chevron { color: #9e9e9e; font-size: 0.85rem; transition: transform .2s; flex-shrink:0; }
        .selector-trigger.open .trig-chevron { transform: rotate(180deg); }

        /* Dropdown panel */
        .selector-panel {
            position: absolute; top: calc(100% + 8px); left: 0; right: 0;
            background: #fff; border-radius: 14px; border: 1px solid #e8e8e8;
            box-shadow: 0 10px 36px rgba(0,0,0,.12); z-index: 1060;
            display: none; flex-direction: column; overflow: hidden;
        }
        .selector-panel.show { display: flex; }

        /* Buscador dentro del dropdown */
        .sel-search-wrap { padding: .75rem .85rem; border-bottom: 1px solid #f0f0f0; }
        .sel-search {
            width: 100%; padding: .5rem .85rem .5rem 2.4rem;
            border: 1.5px solid #e0e0e0; border-radius: 9px;
            font-family: 'Outfit', sans-serif; font-size: .85rem; outline: none;
            transition: border-color .2s;
        }
        .sel-search:focus { border-color: #6B2D8B; }
        .sel-search-icon {
            position: absolute; left: 1.5rem; top: 50%; transform: translateY(-50%);
            color: #bdbdbd; font-size: .9rem; pointer-events: none;
        }

        /* Lista de usuarios */
        .sel-list { max-height: 260px; overflow-y: auto; }
        .sel-option {
            display: flex; align-items: center; gap: 10px;
            padding: .7rem 1rem; cursor: pointer; transition: background .15s;
        }
        .sel-option:hover { background: #f8f0fc; }
        .sel-option:not(:last-child) { border-bottom: 1px solid #f5f5f5; }
        .sel-option.sel-active { background: #f3e8f8; }
        .u-avatar {
            width: 36px; height: 36px; border-radius: 50%; flex-shrink: 0;
            display: flex; align-items: center; justify-content: center;
            font-weight: 700; font-size: 0.8rem; color: #fff;
        }
        .u-name  { font-weight: 600; font-size: 0.87rem; color: #1a1a2e; line-height:1.2; }
        .u-email { font-size: 0.72rem; color: #9e9e9e; }
        .sel-empty { padding: .9rem 1rem; color: #9e9e9e; font-size: .85rem; text-align:center; }

        /* ── Tabla de permisos ── */
        .perm-table { width: 100%; border-collapse: collapse; }
        .perm-table thead tr {
            background: #6B2D8B; color: #fff;
        }
        .perm-table thead th {
            padding: 0.9rem 1.2rem; font-size: 0.78rem;
            font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase;
        }
        .perm-table thead th:first-child { border-radius: 12px 0 0 0; }
        .perm-table thead th:last-child  { border-radius: 0 12px 0 0; }
        .perm-table tbody tr { border-bottom: 1px solid #f3f3f3; transition: background 0.15s; }
        .perm-table tbody tr:hover { background: #faf5ff; }
        .perm-table td { padding: 0.85rem 1.2rem; vertical-align: middle; }
        .mod-icon {
            width: 30px; height: 30px; border-radius: 50%;
            background: #f3e8f8; color: #6B2D8B;
            display: inline-flex; align-items: center; justify-content: center;
            font-size: 0.85rem; flex-shrink: 0;
        }
        .mod-name { font-size: 0.88rem; color: #1a1a2e; font-weight: 500; }

        /* ── Pills de nivel ── */
        .perm-pills { display: flex; gap: 6px; flex-wrap: wrap; }
        .perm-pill {
            padding: 5px 14px; border-radius: 20px; font-size: 0.76rem;
            font-weight: 600; cursor: pointer; border: none; transition: all 0.2s;
            background: #f0f0f0; color: #6c757d;
        }
        .perm-pill:hover { filter: brightness(0.95); }
        .perm-pill.active-write  { background: #1a1a2e; color: #fff; }
        .perm-pill.active-read   { background: #6B2D8B; color: #fff; }
        .perm-pill.active-none   { background: #e8e8e8; color: #555; font-weight: 700; }

        /* ── Bulk bar ── */
        .bulk-bar {
            display: none; align-items: center; gap: 10px; flex-wrap: wrap;
            padding: 0.9rem 1.2rem; background: #faf5ff;
            border-bottom: 1px solid #f0e8fa;
        }
        .bulk-bar.show { display: flex; }
        .bulk-user-info { display: flex; align-items: center; gap: 10px; margin-right: auto; }
        .bulk-av {
            width: 38px; height: 38px; border-radius: 50%;
            display: flex; align-items: center; justify-content: center;
            font-weight: 700; font-size: 0.85rem; color: #fff; flex-shrink: 0;
        }
        .bulk-name  { font-weight: 700; font-size: 0.9rem; color: #1a1a2e; }
        .bulk-email { font-size: 0.75rem; color: #6c757d; }
        .btn-bulk {
            padding: 6px 16px; border-radius: 20px; font-size: 0.78rem;
            font-weight: 600; cursor: pointer; border: 1.5px solid transparent;
            transition: all 0.2s; font-family: 'Outfit', sans-serif;
        }
        .btn-bulk-write { background: #1a1a2e; color: #fff; border-color: #1a1a2e; }
        .btn-bulk-write:hover { background: #2d2d4e; }
        .btn-bulk-read  { background: #6B2D8B; color: #fff; border-color: #6B2D8B; }
        .btn-bulk-read:hover { background: #4a1f61; }
        .btn-bulk-none  { background: #e8e8e8; color: #333; border-color: #ccc; }
        .btn-bulk-none:hover { background: #ddd; }

        /* ── Leyenda de niveles ── */
        .nivel-card { background:#fff; border-radius:14px; box-shadow:0 2px 16px rgba(0,0,0,.06); padding:1.2rem 1.4rem; margin-top:.9rem; }

        /* ── Empty state ── */
        .empty-pane {
            display: flex; flex-direction: column; align-items: center;
            justify-content: center; min-height: 360px; color: #9e9e9e; text-align: center;
        }
        .empty-pane i { font-size: 3.5rem; margin-bottom: 1rem; color: #e0d0ee; }
        .empty-pane h5 { color: #4a4a6a; margin-bottom: 0.4rem; font-weight: 600; }

        /* ── Botón guardar ── */
        .save-bar {
            padding: 1rem 1.2rem; border-top: 1px solid #f0f0f0;
            display: flex; justify-content: flex-end; background: #fff;
            border-radius: 0 0 14px 14px;
        }
        .btn-save {
            background: #6B2D8B; color: #fff; border: none;
            padding: 0.65rem 1.8rem; border-radius: 25px;
            font-family: 'Outfit', sans-serif; font-size: 0.9rem; font-weight: 600;
            cursor: pointer; transition: background 0.2s; display: inline-flex; align-items: center; gap: 8px;
        }
        .btn-save:hover { background: #4a1f61; }
        .btn-save:disabled { background: #c0a0d0; cursor: not-allowed; }

        /* ── Loader ── */
        .perm-loader {
            display: none; align-items: center; justify-content: center;
            flex-direction: column; min-height: 300px; gap: 16px;
        }
        .perm-loader.show { display: flex; }
        .spinner-ieeq {
            width: 40px; height: 40px; border-radius: 50%;
            border: 4px solid #f3e8f8; border-top-color: #6B2D8B;
            animation: spin 0.8s linear infinite;
        }
        \@keyframes spin { to { transform: rotate(360deg); } }

        \@media (max-width: 991px) {
            #content { margin-left: 0 !important; }
        }
    </style>
</head>
<body>
HTML

# --- Sidebar compartido ---
require "$FindBin::Bin/_sidebar_admin.pl";

print <<"HTML";
    <!-- Main Content -->
    <div id="content">

        <!-- Page Header -->
        <div class="page-header d-flex align-items-center justify-content-between">
            <div class="d-flex align-items-center gap-2">
                <button id="sidebarToggle" class="btn btn-outline-secondary d-lg-none me-3" type="button" style="border-radius: 8px;">
                    <i class="bi bi-list"></i>
                </button>
                <div>
                    <h4><i class="bi bi-shield-lock me-2" style="color:#6B2D8B;"></i>Gestión de Permisos</h4>
                    <p>Configura los niveles de acceso de cada usuario a los módulos del sistema.</p>
                </div>
            </div>
            <div class="text-muted d-none d-md-block small">
                Instituto Electoral del Estado de Querétaro
            </div>
        </div>

        <div class="row g-3">

            <!-- ── Columna izquierda: selector ── -->
            <div class="col-lg-4">
                <div class="card-ieeq p-4">
                    <h6 class="fw-bold mb-3" style="color:#1a1a2e;">Seleccionar usuario a configurar</h6>

                    <!-- Trigger / selector combinado -->
                    <div class="selector-wrap" id="selectorWrap">

                        <!-- Trigger visible -->
                        <div class="selector-trigger" id="selectorTrigger" onclick="toggleSelector()">
                            <div class="trig-avatar" id="trigAvatar" style="background:#d0c0e0;">
                                <i class="bi bi-person" style="font-size:1rem;color:#6B2D8B;"></i>
                            </div>
                            <div style="flex:1; min-width:0;">
                                <div id="trigName" class="trig-placeholder">Seleccionar usuario...</div>
                                <div id="trigSub"  class="trig-sub" style="display:none;"></div>
                            </div>
                            <i class="bi bi-chevron-down trig-chevron" id="trigChevron"></i>
                        </div>

                        <!-- Panel dropdown -->
                        <div class="selector-panel" id="selectorPanel">
                            <!-- Buscador -->
                            <div class="sel-search-wrap" style="position:relative;">
                                <i class="bi bi-search sel-search-icon"></i>
                                <input
                                    type="text"
                                    id="selSearchInput"
                                    class="sel-search"
                                    placeholder="Buscar por nombre o correo..."
                                    autocomplete="off"
                                >
                            </div>
                            <!-- Lista -->
                            <div class="sel-list" id="selList"></div>
                        </div>
                    </div>
                </div>

                <!-- Leyenda de niveles -->
                <div class="nivel-card">
                    <h6 class="fw-bold mb-3" style="color:#1a1a2e; font-size:.85rem;">Niveles de Acceso</h6>
                    <div class="d-flex flex-column gap-2">
                        <div class="d-flex align-items-center gap-2">
                            <span class="perm-pill active-write" style="cursor:default; pointer-events:none;">Escritura</span>
                            <small class="text-muted">Lectura y modificación completa</small>
                        </div>
                        <div class="d-flex align-items-center gap-2">
                            <span class="perm-pill active-read" style="cursor:default; pointer-events:none;">Lectura</span>
                            <small class="text-muted">Solo consulta, sin editar</small>
                        </div>
                        <div class="d-flex align-items-center gap-2">
                            <span class="perm-pill active-none" style="cursor:default; pointer-events:none;">Sin acceso</span>
                            <small class="text-muted">Módulo oculto para el usuario</small>
                        </div>
                    </div>
                </div>
            </div>

            <!-- ── Columna derecha: tabla de permisos ── -->
            <div class="col-lg-8">
                <div class="card-ieeq" style="overflow:hidden;">

                    <!-- Empty state -->
                    <div id="emptyPane" class="empty-pane">
                        <i class="bi bi-shield-lock"></i>
                        <h5>Seleccione un usuario</h5>
                        <p class="small text-muted mb-0">Para configurar sus permisos de acceso al sistema</p>
                    </div>

                    <!-- Loader -->
                    <div id="permLoader" class="perm-loader">
                        <div class="spinner-ieeq"></div>
                        <span class="small text-muted fw-semibold">Cargando permisos...</span>
                    </div>

                    <!-- Panel de permisos -->
                    <div id="permPanel" style="display:none;">

                        <!-- Bulk actions bar -->
                        <div id="bulkBar" class="bulk-bar show">
                            <div class="bulk-user-info">
                                <div id="bulkAvatar" class="bulk-av"></div>
                                <div>
                                    <div id="bulkName"  class="bulk-name"></div>
                                    <div id="bulkEmail" class="bulk-email"></div>
                                </div>
                            </div>
                            <span class="small fw-semibold text-muted me-1">Aplicar a todos:</span>
                            <button class="btn-bulk btn-bulk-write" onclick="applyBulk('write')">
                                <i class="bi bi-pencil-fill me-1"></i>Escritura
                            </button>
                            <button class="btn-bulk btn-bulk-read" onclick="applyBulk('read')">
                                <i class="bi bi-eye-fill me-1"></i>Lectura
                            </button>
                            <button class="btn-bulk btn-bulk-none" onclick="applyBulk('none')">
                                <i class="bi bi-slash-circle me-1"></i>Sin acceso
                            </button>
                        </div>

                        <!-- Tabla -->
                        <div class="table-responsive">
                            <table class="perm-table">
                                <thead>
                                    <tr>
                                        <th style="width:55%">MÓDULO</th>
                                        <th>NIVEL DE ACCESO</th>
                                    </tr>
                                </thead>
                                <tbody id="permTableBody">
                                </tbody>
                            </table>
                        </div>

                        <!-- Botón guardar -->
                        <div class="save-bar">
                            <button id="btnGuardarPermisos" class="btn-save" disabled>
                                <i class="bi bi-floppy-fill"></i>Guardar Permisos
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
HTML

# Inyectar JSON fuera del heredoc para evitar interpolación de @ en correos
print '    <!-- Datos de usuarios -->' . "\n";
print '    <script>' . "\n";
print '    var ALL_USERS = ' . $usuarios_json . ";\n";
print '    </script>' . "\n\n";

print <<'ENDHTML';
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    <script>
    (function () {
        'use strict';


        /* ── Helpers ───────────────────────────────────────────────── */
        var COLORS = ['#7c3aed','#2563eb','#059669','#db2777','#0dcaf0','#6f42c1','#d97706'];
        function avatarColor(name) {
            var s = 0;
            for (var i = 0; i < (name||'').length; i++) s += name.charCodeAt(i);
            return COLORS[s % COLORS.length];
        }
        function initials(name) {
            var parts = (name||'').trim().split(/\s+/).filter(Boolean);
            var ini = parts.length > 0 ? parts[0].charAt(0).toUpperCase() : '?';
            if (parts.length > 1) ini += parts[1].charAt(0).toUpperCase();
            return ini;
        }
        function tipoBadge(tipo) {
            var map = {
                'ADMINISTRADOR':    { label: 'Administrador',    bg: '#ede7f6', color: '#6B2D8B' },
                'FUNCIONARIO_IEEQ': { label: 'Funcionario IEEQ', bg: '#e3f2fd', color: '#1565c0' },
                'AUXILIAR':         { label: 'Auxiliar',          bg: '#e8f5e9', color: '#2e7d32' }
            };
            return map[tipo] || { label: tipo||'', bg: '#eee', color: '#555' };
        }

        /* ── Referencias DOM ──────────────────────────────────────── */
        var selectorTrigger = document.getElementById('selectorTrigger');
        var selectorPanel   = document.getElementById('selectorPanel');
        var selSearchInput  = document.getElementById('selSearchInput');
        var selList         = document.getElementById('selList');
        var trigAvatar      = document.getElementById('trigAvatar');
        var trigName        = document.getElementById('trigName');
        var trigSub         = document.getElementById('trigSub');
        var emptyPane       = document.getElementById('emptyPane');
        var permLoader      = document.getElementById('permLoader');
        var permPanel       = document.getElementById('permPanel');
        var permTableBody   = document.getElementById('permTableBody');
        var btnGuardar      = document.getElementById('btnGuardarPermisos');
        var selectedUserId  = '';

        /* ── Render lista en el panel ─────────────────────────────── */
        function renderList(filtered) {
            selList.innerHTML = '';
            if (!filtered || filtered.length === 0) {
                selList.innerHTML = '<div class="sel-empty">Sin resultados</div>';
                return;
            }
            filtered.forEach(function(u) {
                var ini   = initials(u.nombre_completo);
                var clr   = avatarColor(u.nombre_completo);
                var badge = tipoBadge(u.tipo_usuario);
                var isActive = selectedUserId && String(u.id_usuario) === String(selectedUserId);

                var el = document.createElement('div');
                el.className = 'sel-option' + (isActive ? ' sel-active' : '');
                el.innerHTML =
                    '<div class="u-avatar" style="background:' + clr + ';">' + ini + '</div>' +
                    '<div style="flex:1; min-width:0;">' +
                        '<div class="u-name text-truncate">' + (u.nombre_completo||'') + '</div>' +
                        '<div class="u-email text-truncate">@' + (u.correo_electronico||'').split('@')[0] + '</div>' +
                    '</div>' +
                    '<span class="badge rounded-pill" style="background:' + badge.bg + ';color:' + badge.color + ';font-size:.68rem;white-space:nowrap;">' + badge.label + '</span>';

                el.addEventListener('click', function() {
                    selectUser(u);
                    closeSelector();
                });
                selList.appendChild(el);
            });
        }

        /* ── Abrir / cerrar selector ──────────────────────────────── */
        window.toggleSelector = function() {
            var isOpen = selectorPanel.classList.contains('show');
            if (isOpen) { closeSelector(); } else { openSelector(); }
        };
        function openSelector() {
            selectorPanel.classList.add('show');
            selectorTrigger.classList.add('open');
            selSearchInput.value = '';
            renderList(ALL_USERS);
            setTimeout(function(){ selSearchInput.focus(); }, 60);
        }
        function closeSelector() {
            selectorPanel.classList.remove('show');
            selectorTrigger.classList.remove('open');
        }

        /* Cerrar al click fuera */
        document.addEventListener('click', function(e) {
            var wrap = document.getElementById('selectorWrap');
            if (wrap && !wrap.contains(e.target)) closeSelector();
        });

        /* Buscador en tiempo real */
        selSearchInput.addEventListener('input', function() {
            var q = this.value.toLowerCase().trim();
            var filtered = q === ''
                ? ALL_USERS
                : ALL_USERS.filter(function(u) {
                    return (u.nombre_completo||'').toLowerCase().includes(q)
                        || (u.correo_electronico||'').toLowerCase().includes(q);
                });
            renderList(filtered);
        });

        /* ── Seleccionar un usuario ───────────────────────────────── */
        function selectUser(u) {
            selectedUserId = u.id_usuario;

            var ini   = initials(u.nombre_completo);
            var clr   = avatarColor(u.nombre_completo);
            var badge = tipoBadge(u.tipo_usuario);

            // Actualizar trigger
            trigAvatar.style.background = clr;
            trigAvatar.innerHTML = '<span style="color:#fff;font-weight:700;font-size:.85rem;">' + ini + '</span>';
            trigName.className   = 'trig-name';
            trigName.textContent = u.nombre_completo;
            trigSub.style.display = 'block';
            trigSub.innerHTML = '@' + (u.correo_electronico||'').split('@')[0] +
                ' &nbsp;<span class="badge rounded-pill" style="background:' + badge.bg + ';color:' + badge.color + ';font-size:.62rem;">' + badge.label + '</span>';

            // Bulk bar
            document.getElementById('bulkAvatar').textContent      = ini;
            document.getElementById('bulkAvatar').style.background = clr;
            document.getElementById('bulkName').textContent        = u.nombre_completo;
            document.getElementById('bulkEmail').textContent       = u.correo_electronico || '';

            loadPermisos(u.id_usuario);
        }

        /* ── Cargar permisos ──────────────────────────────────────── */
        function loadPermisos(userId) {
            emptyPane.style.display  = 'none';
            permPanel.style.display  = 'none';
            permLoader.classList.add('show');

            var fd = new FormData();
            fd.append('accion', 'get_permisos');
            fd.append('id_usuario', userId);

            fetch('gestion_permisos.pl', { method: 'POST', body: fd })
                .then(function(r) { return r.json(); })
                .then(function(data) {
                    permLoader.classList.remove('show');
                    if (!data.success) throw new Error(data.message || 'Error');
                    renderPermisos(data.modulos, data.permisos);
                    permPanel.style.display = 'block';
                    btnGuardar.disabled = false;
                })
                .catch(function(err) {
                    permLoader.classList.remove('show');
                    emptyPane.style.display = 'flex';
                    Swal.fire({ icon: 'error', title: 'Error', text: err.message });
                });
        }

        /* ── Render tabla de módulos ──────────────────────────────── */
        var MOD_ICONS = [
            'bi-people','bi-shield-lock','bi-building','bi-collection',
            'bi-person-plus','bi-list-ul','bi-award','bi-journal-text','bi-patch-check'
        ];
        function renderPermisos(modulos, permisos) {
            permTableBody.innerHTML = '';
            (modulos || []).forEach(function(mod, idx) {
                var perm  = permisos[mod.id_modulo] || { puede_ver: 0, puede_editar: 0 };
                var nivel = 'none';
                if (perm.puede_editar) nivel = 'write';
                else if (perm.puede_ver) nivel = 'read';

                var icon = MOD_ICONS[idx % MOD_ICONS.length];
                var tr   = document.createElement('tr');
                tr.setAttribute('data-id', mod.id_modulo);
                tr.setAttribute('data-nivel', nivel);
                tr.innerHTML =
                    '<td>' +
                        '<div class="d-flex align-items-center gap-2">' +
                            '<span class="mod-icon"><i class="bi ' + icon + '"></i></span>' +
                            '<span class="mod-name">' + mod.nombre_modulo + '</span>' +
                        '</div>' +
                    '</td>' +
                    '<td>' +
                        '<div class="perm-pills">' +
                            '<button class="perm-pill pill-write ' + (nivel === 'write' ? 'active-write' : '') + '" onclick="setNivel(this,\'write\')">Escritura</button>' +
                            '<button class="perm-pill pill-read  ' + (nivel === 'read'  ? 'active-read'  : '') + '" onclick="setNivel(this,\'read\')">Lectura</button>'  +
                            '<button class="perm-pill pill-none  ' + (nivel === 'none'  ? 'active-none'  : '') + '" onclick="setNivel(this,\'none\')">Sin acceso</button>' +
                        '</div>' +
                    '</td>';
                permTableBody.appendChild(tr);
            });
        }

        /* ── Cambiar nivel ────────────────────────────────────────── */
        window.setNivel = function(btn, nivel) {
            var tr = btn.closest('tr');
            tr.setAttribute('data-nivel', nivel);
            tr.querySelectorAll('.perm-pill').forEach(function(p) {
                p.classList.remove('active-write','active-read','active-none');
            });
            btn.classList.add('active-' + nivel);
        };

        /* ── Nivel masivo ─────────────────────────────────────────── */
        window.applyBulk = function(nivel) {
            document.querySelectorAll('#permTableBody tr[data-id]').forEach(function(tr) {
                tr.setAttribute('data-nivel', nivel);
                tr.querySelectorAll('.perm-pill').forEach(function(p) {
                    p.classList.remove('active-write','active-read','active-none');
                });
                var pill = tr.querySelector('.pill-' + nivel);
                if (pill) pill.classList.add('active-' + nivel);
            });
        };

        /* ── Guardar permisos ─────────────────────────────────────── */
        btnGuardar.addEventListener('click', function() {
            if (!selectedUserId) return;

            var perms = [];
            document.querySelectorAll('#permTableBody tr[data-id]').forEach(function(tr) {
                var id_mod = tr.getAttribute('data-id');
                var nivel  = tr.getAttribute('data-nivel') || 'none';
                perms.push({
                    id_modulo:    id_mod,
                    puede_ver:    (nivel === 'read' || nivel === 'write') ? 1 : 0,
                    puede_editar: (nivel === 'write') ? 1 : 0
                });
            });

            var origHTML = btnGuardar.innerHTML;
            btnGuardar.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Guardando...';
            btnGuardar.disabled  = true;

            var fd = new FormData();
            fd.append('accion', 'save_permisos');
            fd.append('id_usuario', selectedUserId);
            fd.append('permisos_json', JSON.stringify(perms));

            fetch('gestion_permisos.pl', { method: 'POST', body: fd })
                .then(function(r) { return r.json(); })
                .then(function(data) {
                    btnGuardar.innerHTML = origHTML;
                    btnGuardar.disabled  = false;
                    if (data.success) {
                        Swal.fire({
                            toast: true, position: 'top-end', icon: 'success',
                            title: '¡Permisos actualizados!',
                            showConfirmButton: false, timer: 3000, timerProgressBar: true
                        });
                    } else {
                        throw new Error(data.message || 'Error al guardar');
                    }
                })
                .catch(function (err) {
                    btnGuardar.innerHTML = origHTML;
                    btnGuardar.disabled  = false;
                    Swal.fire({ icon: 'error', title: 'Error', text: err.message });
                });
        });

    })();
    </script>
</body>
</html>
ENDHTML
