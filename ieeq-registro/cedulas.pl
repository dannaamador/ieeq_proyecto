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
binmode(STDOUT, ":utf8");

# Evitar doble codificación UTF-8 en encode_json al usar binmode :utf8
no warnings 'redefine';
sub encode_json ($) {
    return JSON->new->utf8(0)->encode($_[0]);
}
use warnings 'redefine';

my $session = CGI::Session->new(undef, $cgi, {Directory => "$FindBin::Bin/.sesiones"});
my $rol             = $session->param('rol')             || '';
my $nombre_completo = $session->param('nombre_completo') || '';
my $id_usuario_sesion = $session->param('id_usuario')   || 0;

if (!$rol)                  { print $cgi->redirect(-uri => 'login.pl');     exit; }
if ($rol ne 'administrador' && $rol ne 'funcionario'){ print $cgi->redirect(-uri => 'dashboard.pl'); exit; }

my $accion = $cgi->param('accion') || '';

# ──────────────────────────────────────────────────────────────
# HELPER: Obtener datos completos del afiliado + asociación
# ──────────────────────────────────────────────────────────────
sub get_cedula_data {
    my ($id_afil) = @_;

    my @afil = execute_query_list("
        SELECT
            a.id_afiliacion,
            CONCAT(a.nombre,' ',a.apellido_paterno,
                   COALESCE(CONCAT(' ',a.apellido_materno),'')) AS nombre_completo,
            COALESCE(a.clave_elector,'')            AS clave_elector,
            COALESCE(a.ocr,'')                      AS numero_ocr,
            COALESCE(a.curp,'')                     AS curp,
            COALESCE(m.nombre,'')                   AS municipio,
            a.estatus,
            COALESCE(a.cedula_folio,'')             AS folio,
            DATE_FORMAT(a.cedula_fecha,'%d/%m/%Y %H:%i')    AS fecha_cedula,
            DATE_FORMAT(a.fecha_hora_afiliacion,'%Y-%m-%d %H:%i') AS fecha_afiliacion,
            COALESCE(a.foto_anverso_ine,'')         AS foto_anverso_ine,
            COALESCE(a.foto_reverso_ine,'')         AS foto_reverso_ine,
            COALESCE(a.foto_persona,'')             AS foto_persona,
            COALESCE(a.firma,'')                    AS firma,
            CONCAT(
                COALESCE(a.domicilio_calle,''),
                CASE WHEN COALESCE(a.domicilio_numero,'') != '' THEN CONCAT(' #', a.domicilio_numero) ELSE '' END,
                CASE WHEN COALESCE(a.domicilio_colonia,'') != '' THEN CONCAT(', Col. ', a.domicilio_colonia) ELSE '' END,
                CASE WHEN COALESCE(m.nombre,'') != '' THEN CONCAT(', ', m.nombre) ELSE '' END
            ) AS domicilio
        FROM afiliaciones a
        LEFT JOIN municipios m ON a.id_municipio_afiliacion = m.id_municipio
        WHERE a.id_afiliacion = ? AND a.fecha_eliminacion IS NULL
        LIMIT 1
    ", $id_afil);

    my @asoc = execute_query_list("
        SELECT
            COALESCE(nombre,'Asociación') AS nombre_asoc,
            COALESCE(emblema,'')          AS emblema,
            COALESCE(estatus_registro,'') AS estatus_registro
        FROM asociaciones_politicas LIMIT 1
    ");

    return (\@afil, \@asoc);
}

# ══════════════════════════════════════════════════════════════
# ENDPOINT POST: generar cédula
# ══════════════════════════════════════════════════════════════
if ($accion eq 'generar') {
    my $id_afil = $cgi->param('id_afiliacion') || 0;
    if ($id_afil) {
        my ($afil_ref, $asoc_ref) = get_cedula_data($id_afil);
        my @afil = @$afil_ref;
        my @asoc = @$asoc_ref;

        if (@afil) {
            my $folio = sprintf("CED-%04d-%05d", (localtime)[5]+1900, $id_afil);
            execute_query_write(
                "UPDATE afiliaciones SET cedula_folio = ?, cedula_fecha = NOW() WHERE id_afiliacion = ?",
                $folio, $id_afil
            );
            execute_query_write(
                "INSERT INTO bitacora (id_usuario, accion, modulo, detalles, fecha)
                 VALUES (?, 'GENERACION_CEDULA', 'cedulas', ?, NOW())",
                $id_usuario_sesion,
                "Cédula generada: $folio para $afil[0]->{nombre_completo}"
            );

            $afil[0]->{folio}       = $folio;
            $afil[0]->{fecha_cedula} = '';   # se calcula en JS

            print $cgi->header(-type => 'application/json', -charset => 'utf-8');
            print encode_json({
                success    => 1,
                folio      => $folio,
                afiliado   => $afil[0],
                asociacion => (@asoc ? $asoc[0] : {}),
            });
        } else {
            print $cgi->header(-type => 'application/json', -charset => 'utf-8');
            print encode_json({ success => 0, message => 'Afiliación no encontrada' });
        }
    } else {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'ID inválido' });
    }
    exit;
}

# ══════════════════════════════════════════════════════════════
# ENDPOINT POST: ver cédula (para reimprimir)
# ══════════════════════════════════════════════════════════════
if ($accion eq 'ver') {
    my $id_afil = $cgi->param('id_afiliacion') || 0;
    if ($id_afil) {
        my ($afil_ref, $asoc_ref) = get_cedula_data($id_afil);
        my @afil = @$afil_ref;
        my @asoc = @$asoc_ref;
        if (@afil) {
            print $cgi->header(-type => 'application/json', -charset => 'utf-8');
            print encode_json({
                success    => 1,
                afiliado   => $afil[0],
                asociacion => (@asoc ? $asoc[0] : {}),
            });
        } else {
            print $cgi->header(-type => 'application/json', -charset => 'utf-8');
            print encode_json({ success => 0, message => 'Afiliación no encontrada' });
        }
    } else {
        print $cgi->header(-type => 'application/json', -charset => 'utf-8');
        print encode_json({ success => 0, message => 'ID inválido' });
    }
    exit;
}

# ══════════════════════════════════════════════════════════════
# GET: Cargar listado de afiliados para mostrar las cards
# ══════════════════════════════════════════════════════════════
my @afiliados = execute_query_list("
    SELECT
        a.id_afiliacion,
        CONCAT(a.nombre,' ',a.apellido_paterno,
               COALESCE(CONCAT(' ',a.apellido_materno),'')) AS nombre_completo,
        a.clave_elector,
        a.estatus,
        COALESCE(a.cedula_folio,'')                    AS folio,
        DATE_FORMAT(a.cedula_fecha,'%d/%m/%Y')         AS fecha_cedula
    FROM afiliaciones a
    WHERE a.fecha_eliminacion IS NULL
      AND a.estatus IN ('VERIFICADO','EN_REVISION')
    ORDER BY a.estatus DESC, a.nombre ASC
");

my $total_disponibles = scalar @afiliados;
my $total_verif = 0;
for my $a (@afiliados) { $total_verif++ if ($a->{estatus}||'') eq 'VERIFICADO'; }

# Colores de avatar
my @AV_COLORS = ('#7c3aed','#2563eb','#059669','#db2777','#d97706','#0891b2','#6f42c1');
sub av_color { my $s=0; $s+=ord($_) for split//,($_[0]||''); return $AV_COLORS[$s%7]; }
sub initials {
    my @p = split /\s+/, ($_[0]||''); my $i='';
    $i .= uc(substr($p[0],0,1)) if @p>0;
    $i .= uc(substr($p[1],0,1)) if @p>1;
    return $i || '?';
}

# Construir cards HTML
my $cards_html = '';
if (@afiliados) {
    for my $a (@afiliados) {
        my $ini   = initials($a->{nombre_completo});
        my $clr   = av_color($a->{nombre_completo});
        my $est   = $a->{estatus} || 'EN_REVISION';
        my $id    = $a->{id_afiliacion};
        my $clave = $a->{clave_elector} || '—';
        my $folio = $a->{folio} || '';

        my ($badge_cls, $badge_lbl) = $est eq 'VERIFICADO'
            ? ('badge-verif',    'Verificado')
            : ('badge-revision', 'En revisión');

        my $btn_text = $folio ? 'Reimprimir' : 'Generar';
        my $btn_icon = $folio ? 'bi-printer'  : 'bi-award';

        my $folio_info = $folio
            ? "<div class='folio-tag'><i class='bi bi-tag-fill me-1'></i>$folio</div>"
            : '';

        # acción JS según si ya tiene folio
        my $js_call = $folio
            ? "verCedula($id)"
            : "generarCedula($id)";

        $cards_html .= <<"CARD";
<div class="cedula-card" data-id="$id" data-estatus="$est">
    <div class="card-inner">
        <div class="card-avatar" style="background:$clr;">$ini</div>
        <div class="card-info">
            <div class="card-nombre">$a->{nombre_completo}</div>
            <div class="card-clave">$clave</div>
            $folio_info
        </div>
        <div class="card-status-wrap">
            <span class="estatus-badge $badge_cls">$badge_lbl</span>
        </div>
        <div class="card-btn-wrap">
            <button class="btn-generar" onclick="$js_call">
                <i class="bi $btn_icon me-1"></i>$btn_text
            </button>
        </div>
    </div>
</div>
CARD
    }
} else {
    $cards_html = '<div class="empty-state"><i class="bi bi-award"></i><h5>Sin cédulas disponibles</h5><p class="text-muted">No hay afiliados verificados o en revisión.</p></div>';
}

my $pagina_activa = 'CEDULAS';

print $cgi->header(-type=>'text/html',-charset=>'utf-8',-expires=>'now',
    -Cache_Control=>'no-store,no-cache,must-revalidate,max-age=0',-Pragma=>'no-cache');

print <<"HTML";
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cédulas de Afiliación - IEEQ</title>
    <meta name="description" content="Genera e imprime las cédulas de los afiliados verificados en el sistema IEEQ.">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons\@1.11.3/font/bootstrap-icons.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght\@300;400;500;600;700&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/sweetalert2\@11"></script>
    <style>
        *{box-sizing:border-box;}
        body{font-family:'Outfit',sans-serif;background:#f5f5f8;overflow-x:hidden;margin:0;}
        #content{margin-left:260px;min-height:100vh;padding:2rem;transition:margin-left .3s;}

        /* ── Page header ── */
        .page-header{display:flex;justify-content:space-between;align-items:center;
            background:#fff;padding:1rem 1.5rem;border-radius:14px;
            box-shadow:0 2px 12px rgba(0,0,0,.05);margin-bottom:1.5rem;}
        .page-header h4{margin:0;font-weight:700;color:#1a1a2e;font-size:1.3rem;}
        .page-header p{margin:0;color:#6c757d;font-size:.85rem;}

        /* ── Filtros ── */
        .filter-row{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:1.5rem;align-items:center;}
        .ftab{padding:6px 18px;border-radius:20px;border:none;font-family:'Outfit',sans-serif;
            font-size:.82rem;font-weight:600;cursor:pointer;transition:all .2s;
            background:#f0f0f0;color:#6c757d;}
        .ftab.active{background:#6B2D8B;color:#fff;}
        .ftab:hover:not(.active){background:#e8e0f0;color:#6B2D8B;}

        /* ── Cards ── */
        .cards-grid{display:flex;flex-direction:column;gap:10px;}
        .cedula-card{background:#fff;border-radius:14px;border:1px solid #f0f0f0;
            box-shadow:0 2px 10px rgba(0,0,0,.04);transition:box-shadow .2s;}
        .cedula-card:hover{box-shadow:0 4px 20px rgba(107,45,139,.1);}
        .card-inner{display:flex;align-items:center;gap:16px;padding:1rem 1.3rem;flex-wrap:wrap;}
        .card-avatar{width:44px;height:44px;border-radius:50%;display:flex;align-items:center;
            justify-content:center;font-weight:700;font-size:.95rem;color:#fff;flex-shrink:0;}
        .card-info{flex:1;min-width:180px;}
        .card-nombre{font-weight:700;font-size:.95rem;color:#1a1a2e;}
        .card-clave{font-size:.78rem;color:#9e9e9e;font-family:monospace;margin-top:2px;}
        .folio-tag{display:inline-flex;align-items:center;margin-top:4px;background:#f3e8f8;
            color:#6B2D8B;border-radius:8px;padding:2px 10px;font-size:.72rem;font-weight:600;}
        .card-status-wrap{flex-shrink:0;}
        .card-btn-wrap{flex-shrink:0;}

        /* ── Badges ── */
        .estatus-badge{display:inline-block;padding:5px 14px;border-radius:20px;font-size:.75rem;font-weight:600;}
        .badge-verif   {background:#dcfce7;color:#15803d;}
        .badge-revision{background:#dbeafe;color:#1d4ed8;}

        /* ── Botón generar ── */
        .btn-generar{background:#6B2D8B;color:#fff;border:none;padding:8px 20px;
            border-radius:20px;font-family:'Outfit',sans-serif;font-size:.82rem;font-weight:600;
            cursor:pointer;transition:background .2s;display:inline-flex;align-items:center;}
        .btn-generar:hover{background:#4a1f61;}

        /* ── Empty state ── */
        .empty-state{display:flex;flex-direction:column;align-items:center;justify-content:center;
            min-height:300px;text-align:center;color:#9e9e9e;}
        .empty-state i{font-size:3rem;color:#e0d0ee;margin-bottom:1rem;}
        .empty-state h5{color:#4a4a6a;}

        /* ══════════════ MODAL CÉDULA ══════════════ */
        .modal-cedula-dialog{max-width:640px;}

        /* Header de la cédula dentro del modal */
        .ced-header{display:flex;align-items:center;padding:1rem 1.5rem;
            border-bottom:3px solid #6B2D8B;gap:8px;}
        .ced-logo-box{flex:0 0 90px;display:flex;flex-direction:column;align-items:center;}
        .ced-logo-img{max-width:72px;max-height:60px;object-fit:contain;border-radius:6px;}
        .ced-logo-placeholder{width:56px;height:56px;border-radius:8px;
            background:#f3e8f8;border:1.5px dashed #c4a0d8;
            display:flex;align-items:center;justify-content:center;
            font-size:1.1rem;font-weight:800;color:#6B2D8B;}
        .ced-logo-name{font-size:.62rem;color:#6c757d;text-align:center;margin-top:3px;
            max-width:88px;line-height:1.2;}
        .ced-title-center{flex:1;text-align:center;}
        .ced-title-center .main-title{font-weight:800;font-size:1rem;color:#6B2D8B;letter-spacing:.5px;}
        .ced-title-center .sub-title{font-size:.7rem;color:#9e9e9e;margin-top:2px;}
        .ced-ieeq-right{flex:0 0 110px;text-align:right;}
        .ced-ieeq-right .ieeq-badge{font-weight:800;font-size:1rem;color:#6B2D8B;}
        .ced-ieeq-right .ieeq-sub{font-size:.62rem;color:#9e9e9e;line-height:1.4;}

        /* Sección bar morada */
        .ced-section-bar{background:#6B2D8B;color:#fff;font-weight:700;
            font-size:.72rem;letter-spacing:.8px;text-transform:uppercase;
            padding:.45rem 1.5rem;}

        /* Grid de campos */
        .ced-fields-row{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;
            padding:.75rem 1.5rem .25rem;}
        .ced-field-full{padding:.25rem 1.5rem .75rem;}
        .ced-field{background:#fff;border:1px solid #ececec;border-radius:8px;padding:.5rem .8rem;}
        .ced-field .lbl{font-size:.65rem;color:#9e9e9e;margin-bottom:2px;}
        .ced-field .val{font-size:.82rem;font-weight:700;color:#1a1a2e;word-break:break-word;}

        /* Evidencia fotográfica */
        .ced-fotos-row{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;padding:.75rem 1.5rem;}
        .ced-foto-box{border:1px solid #ececec;border-radius:8px;min-height:80px;
            display:flex;flex-direction:column;align-items:center;justify-content:center;
            color:#bdbdbd;font-size:.65rem;text-align:center;padding:.4rem;gap:4px;}
        .ced-foto-box i{font-size:1.5rem;}

        /* Declaraciones */
        .ced-decl-list{padding:.6rem 1.5rem .9rem;display:flex;flex-direction:column;gap:.4rem;}
        .ced-decl-item{display:flex;align-items:flex-start;gap:8px;
            background:#f0fdf4;border-radius:8px;padding:.45rem .75rem;
            font-size:.78rem;color:#1a1a2e;line-height:1.4;}
        .ced-decl-item i{color:#16a34a;font-size:.95rem;flex-shrink:0;margin-top:1px;}

        /* Footer de la cédula */
        .ced-footer{display:flex;align-items:flex-end;justify-content:space-between;
            padding:.75rem 1.5rem;border-top:1px solid #f0f0f0;gap:8px;}
        .ced-footer-folio{font-size:.75rem;}
        .ced-footer-folio .fol-num{color:#6B2D8B;font-weight:700;}
        .ced-footer-firma{text-align:center;font-size:.68rem;color:#9e9e9e;flex:1;}
        .ced-footer-firma .firma-line{width:120px;border-top:1px solid #9e9e9e;margin:0 auto 3px;}
        .ced-footer-ieeq{text-align:right;font-size:.65rem;color:#9e9e9e;line-height:1.5;}
        .ced-footer-ieeq .ieeq-main{color:#6B2D8B;font-weight:700;font-size:.72rem;}

        /* Botón imprimir */
        .btn-imprimir{background:#6B2D8B;color:#fff;border:none;border-radius:20px;
            padding:8px 20px;font-family:'Outfit',sans-serif;font-size:.85rem;font-weight:600;
            display:inline-flex;align-items:center;gap:6px;cursor:pointer;transition:background .2s;}
        .btn-imprimir:hover{background:#4a1f61;}

        \@media(max-width:991px){#content{margin-left:0!important;}}

        /* ── Print ── */
        \@media print{
            #sidebar,.modal-footer,.modal-header,.filter-row,.page-header,
            .cards-grid,button{display:none!important;}
            #content{margin-left:0!important;padding:0!important;}
            .modal{position:static!important;display:block!important;}
            .modal-dialog{max-width:100%!important;margin:0!important;}
            .modal-content{border:none!important;box-shadow:none!important;}
            .modal-body{padding:0!important;}
            body{background:#fff!important;}
        }
    </style>
</head>
<body>
HTML

require "$FindBin::Bin/_sidebar_admin.pl";

print <<"HTML";
    <div id="content">

        <div class="page-header d-flex align-items-center justify-content-between">
            <div class="d-flex align-items-center gap-2">
                <button id="sidebarToggle" class="btn btn-outline-secondary d-lg-none me-3" type="button" style="border-radius: 8px;">
                    <i class="bi bi-list"></i>
                </button>
                <div>
                    <h4><i class="bi bi-award me-2" style="color:#6B2D8B;"></i>Cédulas de Afiliación</h4>
                    <p>Genera e imprime las cédulas de los afiliados verificados. <strong>$total_disponibles cédulas disponibles.</strong></p>
                </div>
            </div>
            <div class="text-muted small d-none d-md-block">Instituto Electoral del Estado de Querétaro</div>
        </div>

        <!-- Filtros -->
        <div class="filter-row">
            <button class="ftab active" onclick="filtrarCards(this,'TODOS')">Todos ($total_disponibles)</button>
            <button class="ftab" onclick="filtrarCards(this,'VERIFICADO')">Solo Verificados ($total_verif)</button>
            <button class="ftab" onclick="filtrarCards(this,'EN_REVISION')">En revisión</button>
        </div>

        <!-- Grid de cédulas -->
        <div class="cards-grid" id="cardsGrid">
            $cards_html
        </div>

    </div>

    <!-- ════════════════════════════════════════════════
         MODAL CÉDULA DE AFILIACIÓN
         ════════════════════════════════════════════════ -->
    <div class="modal fade" id="modalCedula" tabindex="-1" aria-labelledby="modalCedulaLabel" aria-hidden="true">
        <div class="modal-dialog modal-dialog-scrollable modal-cedula-dialog">
            <div class="modal-content border-0" style="border-radius:16px;overflow:hidden;">

                <!-- Título del modal -->
                <div class="modal-header" style="padding:.75rem 1.5rem;border-bottom:1px solid #eee;">
                    <h5 class="modal-title fw-bold" id="modalCedulaLabel">Cédula de Afiliación</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Cerrar"></button>
                </div>

                <!-- Cuerpo = la cédula -->
                <div class="modal-body p-0" id="cedulaBody">

                    <!-- ── Header ── -->
                    <div class="ced-header">
                        <!-- Logo de la asociación -->
                        <div class="ced-logo-box">
                            <div id="logoWrap"></div>
                            <div class="ced-logo-name" id="logoNombre"></div>
                        </div>
                        <!-- Título centrado -->
                        <div class="ced-title-center">
                            <div class="main-title">CÉDULA DE AFILIACIÓN</div>
                            <div class="sub-title">Sistema de Registro — IEEQ</div>
                        </div>
                        <!-- Bloque IEEQ -->
                        <div class="ced-ieeq-right">
                            <div class="ieeq-badge"><i class="bi bi-shield-fill me-1"></i>IEEQ</div>
                            <div class="ieeq-sub">Instituto Electoral<br>del Estado de Querétaro</div>
                        </div>
                    </div>

                    <!-- ── Datos Personales ── -->
                    <div class="ced-section-bar">Datos Personales</div>
                    <div class="ced-fields-row">
                        <div class="ced-field">
                            <div class="lbl">Nombre completo</div>
                            <div class="val" id="cdNombre">—</div>
                        </div>
                        <div class="ced-field">
                            <div class="lbl">Clave de Elector</div>
                            <div class="val" id="cdClave" style="font-family:monospace;font-size:.75rem;">—</div>
                        </div>
                        <div class="ced-field">
                            <div class="lbl">Número OCR</div>
                            <div class="val" id="cdOcr" style="font-family:monospace;">—</div>
                        </div>
                    </div>
                    <div class="ced-fields-row" style="padding-top:.25rem;">
                        <div class="ced-field">
                            <div class="lbl">CURP</div>
                            <div class="val" id="cdCurp" style="font-family:monospace;font-size:.72rem;">—</div>
                        </div>
                        <div class="ced-field">
                            <div class="lbl">Municipio</div>
                            <div class="val" id="cdMunicipio">—</div>
                        </div>
                        <div class="ced-field">
                            <div class="lbl">Fecha de afiliación</div>
                            <div class="val" id="cdFechaAfil" style="font-size:.76rem;">—</div>
                        </div>
                    </div>
                    <div class="ced-field-full">
                        <div class="ced-field">
                            <div class="lbl">Domicilio</div>
                            <div class="val" id="cdDomicilio">—</div>
                        </div>
                    </div>

                    <!-- ── Evidencia Fotográfica ── -->
                    <div class="ced-section-bar">Evidencia Fotográfica</div>
                    <div class="ced-fotos-row" id="cdFotosRow">
                        <div class="ced-foto-box" id="cdImgAnverso"><i class="bi bi-camera"></i>Anverso INE</div>
                        <div class="ced-foto-box" id="cdImgReverso"><i class="bi bi-camera"></i>Reverso INE</div>
                        <div class="ced-foto-box" id="cdImgPersona"><i class="bi bi-camera"></i>Fotografía Viva</div>
                        <div class="ced-foto-box" id="cdImgFirma"><i class="bi bi-pencil-square"></i>Firma Digital</div>
                    </div>

                    <!-- ── Declaraciones ── -->
                    <div class="ced-section-bar">Declaraciones del Afiliado</div>
                    <div class="ced-decl-list">
                        <div class="ced-decl-item">
                            <i class="bi bi-check-circle-fill"></i>
                            Manifiesto que mi afiliación es libre, voluntaria, individual y pacífica.
                        </div>
                        <div class="ced-decl-item">
                            <i class="bi bi-check-circle-fill"></i>
                            Conozco y acepto los documentos básicos de la organización política.
                        </div>
                        <div class="ced-decl-item">
                            <i class="bi bi-check-circle-fill"></i>
                            Declaro no estar afiliado/a a otra organización política estatal.
                        </div>
                        <div class="ced-decl-item">
                            <i class="bi bi-check-circle-fill"></i>
                            He leído y acepto el Aviso de Privacidad Simplificado e Integral.
                        </div>
                    </div>

                    <!-- ── Footer de la cédula ── -->
                    <div class="ced-footer">
                        <div class="ced-footer-folio">
                            <div>Folio: <span class="fol-num" id="cdFolio">—</span></div>
                            <div style="color:#9e9e9e;font-size:.65rem;">Generado: <span id="cdFechaGen">—</span></div>
                        </div>
                        <div class="ced-footer-firma">
                            <div class="firma-line"></div>
                            Firma del Registrador
                        </div>
                        <div class="ced-footer-ieeq">
                            <div class="ieeq-main">IEEQ</div>
                            Sistema de Registro de Afiliaciones<br>Versión 1.0 · 2025
                        </div>
                    </div>

                </div><!-- /modal-body -->

                <!-- Botones -->
                <div class="modal-footer" style="border-top:1px solid #eee;padding:.75rem 1.5rem;">
                    <button type="button" class="btn btn-outline-secondary rounded-pill px-4"
                            data-bs-dismiss="modal">Cerrar</button>
                    <button type="button" class="btn-imprimir" onclick="imprimirCedula()">
                        <i class="bi bi-printer-fill"></i>Imprimir / Exportar PDF
                    </button>
                </div>

            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap\@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js"></script>
    <script>
    (function(){
        'use strict';

        var modalCedula = new bootstrap.Modal(document.getElementById('modalCedula'));

        /* ── Filtrar cards ── */
        window.filtrarCards = function(btn, filtro) {
            document.querySelectorAll('.ftab').forEach(function(b){ b.classList.remove('active'); });
            btn.classList.add('active');
            document.querySelectorAll('.cedula-card[data-id]').forEach(function(c){
                c.style.display = (filtro === 'TODOS' || c.getAttribute('data-estatus') === filtro) ? '' : 'none';
            });
        };

        /* ── Poblar y mostrar el modal ── */
        function mostrarModal(data) {
            var af = data.afiliado  || {};
            var as = data.asociacion || {};

            // Logo de la asociación
            var logoWrap = document.getElementById('logoWrap');
            if (as.emblema) {
                logoWrap.innerHTML = '<img class="ced-logo-img" src="uploads/emblemas/' + as.emblema + '" alt="Logo">';
            } else {
                var iniciales = (as.nombre_asoc || 'ACQ').substring(0,3).toUpperCase();
                logoWrap.innerHTML = '<div class="ced-logo-placeholder">' + iniciales + '</div>';
            }
            document.getElementById('logoNombre').textContent = as.nombre_asoc || '';

            // Datos del afiliado
            document.getElementById('cdNombre').textContent     = af.nombre_completo || '—';
            document.getElementById('cdClave').textContent      = af.clave_elector   || '—';
            document.getElementById('cdOcr').textContent        = af.numero_ocr      || '—';
            document.getElementById('cdCurp').textContent       = af.curp            || '—';
            document.getElementById('cdMunicipio').textContent  = af.municipio       || '—';
            document.getElementById('cdFechaAfil').textContent  = af.fecha_afiliacion|| '—';
            document.getElementById('cdDomicilio').textContent  = af.domicilio       || '—';

            // Evidencias fotográficas
            var cda = document.getElementById('cdImgAnverso');
            if (af.foto_anverso_ine) {
                cda.innerHTML = '<img src="' + af.foto_anverso_ine + '" style="width:100%; height:100%; object-fit:contain; border-radius:4px;">';
            } else {
                cda.innerHTML = '<i class="bi bi-camera"></i>Anverso INE';
            }

            var cdr = document.getElementById('cdImgReverso');
            if (af.foto_reverso_ine) {
                cdr.innerHTML = '<img src="' + af.foto_reverso_ine + '" style="width:100%; height:100%; object-fit:contain; border-radius:4px;">';
            } else {
                cdr.innerHTML = '<i class="bi bi-camera"></i>Reverso INE';
            }

            var cdp = document.getElementById('cdImgPersona');
            if (af.foto_persona) {
                cdp.innerHTML = '<img src="' + af.foto_persona + '" style="width:100%; height:100%; object-fit:contain; border-radius:4px;">';
            } else {
                cdp.innerHTML = '<i class="bi bi-camera"></i>Fotografía Viva';
            }

            var cdf = document.getElementById('cdImgFirma');
            if (af.firma) {
                cdf.innerHTML = '<img src="' + af.firma + '" style="width:100%; height:100%; object-fit:contain; background:#fff; border-radius:4px;">';
            } else {
                cdf.innerHTML = '<i class="bi bi-pencil-square"></i>Firma Digital';
            }

            // Folio y fecha
            var folio = data.folio || af.folio || '—';
            document.getElementById('cdFolio').textContent   = folio;
            var fechaGen = af.fecha_cedula || new Date().toLocaleString('es-MX');
            document.getElementById('cdFechaGen').textContent = fechaGen || new Date().toLocaleString('es-MX');

            modalCedula.show();
        }

        /* ── Generar cédula (primera vez) ── */
        window.generarCedula = function(id) {
            Swal.fire({
                title: 'Generar Cédula',
                html: '<p style="margin:0">¿Generar cédula para el afiliado ID <strong>' + id + '</strong>?</p>',
                icon: 'question',
                showCancelButton: true,
                confirmButtonColor: '#6B2D8B',
                cancelButtonColor: '#6c757d',
                confirmButtonText: '<i class="bi bi-award-fill me-1"></i>Sí, generar',
                cancelButtonText: 'Cancelar'
            }).then(function(r){
                if (!r.isConfirmed) return;

                Swal.fire({ title:'Generando...', allowOutsideClick:false,
                    didOpen:function(){ Swal.showLoading(); }});

                var fd = new FormData();
                fd.append('accion','generar');
                fd.append('id_afiliacion', id);

                fetch('cedulas.pl', { method:'POST', body:fd })
                    .then(function(r){ return r.json(); })
                    .then(function(d){
                        Swal.close();
                        if (d.success) {
                            mostrarModal(d);
                            // Actualizar el botón en la card
                            var card = document.querySelector('.cedula-card[data-id="' + id + '"]');
                            if (card) {
                                var btn = card.querySelector('.btn-generar');
                                if (btn) {
                                    btn.innerHTML = '<i class="bi bi-printer me-1"></i>Reimprimir';
                                    btn.setAttribute('onclick', 'verCedula(' + id + ')');
                                }
                                var infoDiv = card.querySelector('.card-info');
                                if (infoDiv && !infoDiv.querySelector('.folio-tag')) {
                                    var ft = document.createElement('div');
                                    ft.className = 'folio-tag';
                                    ft.innerHTML = '<i class="bi bi-tag-fill me-1"></i>' + d.folio;
                                    infoDiv.appendChild(ft);
                                }
                            }
                        } else {
                            Swal.fire({ icon:'error', title:'Error', text: d.message || 'No se pudo generar.' });
                        }
                    })
                    .catch(function(){
                        Swal.fire({ icon:'error', title:'Error de conexión', text:'No se pudo contactar al servidor.' });
                    });
            });
        };

        /* ── Ver cédula (reimprimir) ── */
        window.verCedula = function(id) {
            Swal.fire({ title:'Cargando...', allowOutsideClick:false,
                didOpen:function(){ Swal.showLoading(); }});

            var fd = new FormData();
            fd.append('accion','ver');
            fd.append('id_afiliacion', id);

            fetch('cedulas.pl', { method:'POST', body:fd })
                .then(function(r){ return r.json(); })
                .then(function(d){
                    Swal.close();
                    if (d.success) {
                        mostrarModal(d);
                    } else {
                        Swal.fire({ icon:'error', title:'Error', text: d.message || 'No se pudo cargar.' });
                    }
                })
                .catch(function(){
                    Swal.fire({ icon:'error', title:'Error de conexión', text:'No se pudo contactar al servidor.' });
                });
        };

        /* ── Imprimir / Exportar PDF ── */
        window.imprimirCedula = function() {
            var element = document.getElementById('cedulaBody');
            var folio = document.getElementById('cdFolio').textContent || 'cedula';
            var nombre = document.getElementById('cdNombre').textContent || 'afiliado';
            var filename = 'Cedula_' + folio + '_' + nombre.replace(/\\s+/g, '_') + '.pdf';

            var opt = {
                margin:       10,
                filename:     filename,
                image:        { type: 'jpeg', quality: 0.98 },
                html2canvas:  { scale: 2, useCORS: true },
                jsPDF:        { unit: 'mm', format: 'a4', orientation: 'portrait' }
            };

            Swal.fire({
                title: 'Generando PDF...',
                text: 'Por favor espera un momento.',
                allowOutsideClick: false,
                didOpen: function() {
                    Swal.showLoading();
                }
            });

            html2pdf().set(opt).from(element).save().then(function() {
                Swal.close();
            }).catch(function(err) {
                Swal.fire({ icon: 'error', title: 'Error', text: 'No se pudo generar el archivo PDF.' });
            });
        };

        window.addEventListener('DOMContentLoaded', function() {
            var urlParams = new URLSearchParams(window.location.search);
            var id = urlParams.get('id');
            if (id) {
                window.verCedula(id);
            } else {
                var genId = urlParams.get('generar_id');
                if (genId) {
                    window.generarCedula(genId);
                }
            }
        });

    })();
    </script>
</body>
</html>
HTML
