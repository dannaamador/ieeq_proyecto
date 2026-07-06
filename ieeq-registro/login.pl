#!C:\xampp\perl\bin\perl.exe
use strict;
use warnings;
use utf8;
use CGI;
use CGI::Session;
use Digest::SHA qw(sha256_hex);

# Incluir el módulo de base de datos
use FindBin;
require "$FindBin::Bin/db.pl";

my $cgi = CGI->new;

# Configurar salida UTF-8
binmode(STDOUT, ":utf8");

# Inicializar sesión
my $session = CGI::Session->new(undef, $cgi, {Directory=>"$FindBin::Bin/.sesiones"});

my $cookie = $cgi->cookie(
    -name  => $session->name(),
    -value => $session->id()
);

# Manejo de cierre de sesión manual
if ($cgi->param('logout')) {
    $session->delete();
    $session->flush();
    print $cgi->redirect(-uri => 'login.pl', -cookie => $cookie);
    exit;
}

# Recuperar errores de la sesión (Patrón PRG)
my $error_msg = $session->param('flash_error') || '';
$session->clear('flash_error') if $error_msg;

if ($session->param('id_usuario')) {
    print $cgi->redirect(-uri => 'dashboard.pl', -cookie => $cookie);
    exit;
}

if ($cgi->request_method() eq 'POST') {
    my $usuario = $cgi->param('usuario');
    my $password = $cgi->param('password');
    
    $usuario =~ s/^\s+|\s+$//g if defined $usuario;
    
    if (!$usuario || !$password) {
        $session->param('flash_error', 'Por favor, ingrese usuario y contraseña.');
        print $cgi->redirect(-uri => 'login.pl', -cookie => $cookie);
        exit;
    } else {
        # Usar la nueva función nativa que evita el error de DLLs
        my $user_data = get_user_by_username($usuario);
        
        if ($user_data) {
            if ($user_data->{activo} == 1) {
                my $hashed_password = sha256_hex($password);
                
                if ($hashed_password eq $user_data->{contrasena}) {
                    $session->param('id_usuario', $user_data->{id_usuario});
                    $session->param('username', $user_data->{username});
                    $session->param('nombre_completo', $user_data->{nombre_completo});
                    $session->param('rol', $user_data->{rol});
                    
                    print $cgi->redirect(-uri => 'dashboard.pl', -cookie => $cookie);
                    exit;
                } else {
                    $session->param('flash_error', 'Credenciales incorrectas.');
                    print $cgi->redirect(-uri => 'login.pl', -cookie => $cookie);
                    exit;
                }
            } else {
                $session->param('flash_error', 'El usuario se encuentra inactivo.');
                print $cgi->redirect(-uri => 'login.pl', -cookie => $cookie);
                exit;
            }
        } else {
            $session->param('flash_error', 'Credenciales incorrectas.');
            print $cgi->redirect(-uri => 'login.pl', -cookie => $cookie);
            exit;
        }
    }
}

print $cgi->header(
    -type => 'text/html', 
    -charset => 'utf-8', 
    -cookie => $cookie,
    -expires => 'now',
    -Cache_Control => 'no-store, no-cache, must-revalidate, max-age=0',
    -Pragma => 'no-cache'
);

print <<'HTML';
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - IEEQ Registro</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;700&display=swap" rel="stylesheet">
    <style>
        body {
            font-family: 'Outfit', sans-serif;
            background-color: #f8f9fa;
            height: 100vh;
            margin: 0;
            overflow-x: hidden;
        }
        .split-layout {
            min-height: 100vh;
        }
        /* Left Side: Branding / Image */
        .branding-section {
            background: linear-gradient(135deg, #9b2781 0%, #6e1759 100%);
            color: white;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            padding: 3rem;
            position: relative;
            overflow: hidden;
        }
        .branding-section h1 {
            font-size: 5rem;
            font-weight: 700;
            z-index: 2;
            letter-spacing: 2px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
            margin-bottom: 10px;
        }
        .branding-section p {
            font-size: 1.5rem;
            font-weight: 300;
            z-index: 2;
            opacity: 0.9;
        }
        /* Animated Background Elements in Branding */
        .bg-shape {
            position: absolute;
            border-radius: 50%;
            background: rgba(255, 255, 255, 0.05);
            animation: float 6s infinite ease-in-out;
            z-index: 1;
        }
        .shape1 { width: 400px; height: 400px; top: -10%; left: -10%; animation-duration: 8s; }
        .shape2 { width: 500px; height: 500px; bottom: -15%; right: -15%; animation-duration: 12s; }
        
        @keyframes float {
            0% { transform: translateY(0px) rotate(0deg); }
            50% { transform: translateY(-30px) rotate(15deg); }
            100% { transform: translateY(0px) rotate(0deg); }
        }

        /* Right Side: Form */
        .form-section {
            background-color: #ffffff;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 2rem;
            box-shadow: -10px 0 30px rgba(0,0,0,0.05);
            z-index: 2;
        }
        .login-wrapper {
            width: 100%;
            max-width: 420px;
            padding: 2rem;
        }
        .form-title {
            color: #9b2781;
            font-weight: 700;
            margin-bottom: 2rem;
            font-size: 2.2rem;
        }
        .form-control {
            border-radius: 12px;
            padding: 14px 18px;
            border: 2px solid #eef0f3;
            background-color: #f8f9fa;
            font-size: 1rem;
            transition: all 0.3s ease;
        }
        .form-control:focus {
            border-color: #9b2781;
            box-shadow: 0 0 0 0.25rem rgba(155, 39, 129, 0.15);
            background-color: #ffffff;
        }
        .form-label {
            font-weight: 600;
            color: #4a4a4a;
            margin-bottom: 8px;
            font-size: 0.95rem;
        }
        .btn-primary {
            background: linear-gradient(to right, #9b2781, #b53898);
            border: none;
            border-radius: 12px;
            padding: 14px;
            font-weight: 600;
            font-size: 1.1rem;
            transition: all 0.3s ease;
            box-shadow: 0 4px 15px rgba(155, 39, 129, 0.3);
            width: 100%;
            margin-top: 1rem;
        }
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 25px rgba(155, 39, 129, 0.4);
            background: linear-gradient(to right, #b53898, #9b2781);
        }
        .alert {
            border-radius: 12px;
            border: none;
            box-shadow: 0 4px 6px rgba(0,0,0,0.05);
            font-weight: 500;
        }
        /* Mobile Tweaks */
        @media (max-width: 991px) {
            .branding-section {
                padding: 4rem 2rem;
                min-height: 35vh;
            }
            .branding-section h1 { font-size: 3.5rem; }
            .form-section {
                min-height: 65vh;
                align-items: flex-start;
                padding-top: 3rem;
            }
        }
    </style>
</head>
<body>
    <div class="row g-0 split-layout">
        <!-- Left Side: Branding -->
        <div class="col-lg-6 branding-section">
            <div class="bg-shape shape1"></div>
            <div class="bg-shape shape2"></div>
            <h1 style="font-family: Arial, sans-serif; letter-spacing: -2px;">IEEQ</h1>
            <p>Instituto Electoral del<br>Estado de Querétaro</p>
        </div>
        
        <!-- Right Side: Login Form -->
        <div class="col-lg-6 form-section">
            <div class="login-wrapper">
                <h3 class="form-title">Iniciar Sesión</h3>
HTML

if ($error_msg) {
    print qq|                <div class="alert alert-danger" role="alert">$error_msg</div>\n|;
}

print <<'HTML';
                <form method="POST" action="login.pl">
                    <div class="mb-3">
                        <label for="usuario" class="form-label">Usuario</label>
                        <input type="text" class="form-control" id="usuario" name="usuario" placeholder="Ingresa tu usuario" required autofocus>
                    </div>
                    <div class="mb-4">
                        <label for="password" class="form-label">Contraseña</label>
                        <div class="input-group">
                            <input type="password" class="form-control" id="password" name="password" placeholder="••••••••" required>
                            <button class="btn btn-outline-secondary d-flex align-items-center" type="button" id="togglePassword" style="border-radius: 0 12px 12px 0; border: 2px solid #eef0f3; border-left: none; background: white;">
                                <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="currentColor" class="bi bi-eye" viewBox="0 0 16 16" id="eyeIcon">
                                  <path d="M16 8s-3-5.5-8-5.5S0 8 0 8s3 5.5 8 5.5S16 8 16 8zM1.173 8a13.133 13.133 0 0 1 1.66-2.043C4.12 4.668 5.88 3.5 8 3.5c2.12 0 3.879 1.168 5.168 2.457A13.133 13.133 0 0 1 14.828 8c-.058.087-.122.183-.195.288-.335.48-.83 1.12-1.465 1.755C11.879 11.332 10.119 12.5 8 12.5c-2.12 0-3.879-1.168-5.168-2.457A13.134 13.134 0 0 1 1.172 8z"/>
                                  <path d="M8 5.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM4.5 8a3.5 3.5 0 1 1 7 0 3.5 3.5 0 0 1-7 0z"/>
                                </svg>
                            </button>
                        </div>
                    </div>
                    <div class="d-grid">
                        <button type="submit" class="btn btn-primary">Entrar al Sistema</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        document.getElementById('togglePassword').addEventListener('click', function() {
            const passwordInput = document.getElementById('password');
            const eyeIcon = document.getElementById('eyeIcon');
            
            if (passwordInput.type === 'password') {
                passwordInput.type = 'text';
                eyeIcon.innerHTML = '<path d="M13.359 11.238C15.06 9.72 16 8 16 8s-3-5.5-8-5.5a7.028 7.028 0 0 0-2.79.588l.77.771A5.944 5.944 0 0 1 8 3.5c2.12 0 3.879 1.168 5.168 2.457A13.134 13.134 0 0 1 14.828 8c-.058.087-.122.183-.195.288-.335.48-.83 1.12-1.465 1.755-.165.165-.337.328-.517.486l-.708.709z"/><path d="M11.297 9.176a3.5 3.5 0 0 0-4.474-4.474l.823.823a2.5 2.5 0 0 1 2.829 2.829l.822.822zm-2.943 1.299l.822.822a3.5 3.5 0 0 1-4.474-4.474l.823.823a2.5 2.5 0 0 0 2.829 2.829z"/><path d="M3.35 5.47c-.18.16-.353.322-.518.487A13.134 13.134 0 0 0 1.172 8l.195.288c.335.48.83 1.12 1.465 1.755C4.121 11.332 5.881 12.5 8 12.5c.716 0 1.39-.133 2.02-.36l.77.772A7.029 7.029 0 0 1 8 13.5C3 13.5 0 8 0 8s.939-1.721 2.641-3.238l.708.709z"/><path fill-rule="evenodd" d="M13.646 14.354l-12-12 .708-.708 12 12-.708.708z"/>';
            } else {
                passwordInput.type = 'password';
                eyeIcon.innerHTML = '<path d="M16 8s-3-5.5-8-5.5S0 8 0 8s3 5.5 8 5.5S16 8 16 8zM1.173 8a13.133 13.133 0 0 1 1.66-2.043C4.12 4.668 5.88 3.5 8 3.5c2.12 0 3.879 1.168 5.168 2.457A13.133 13.133 0 0 1 14.828 8c-.058.087-.122.183-.195.288-.335.48-.83 1.12-1.465 1.755C11.879 11.332 10.119 12.5 8 12.5c-2.12 0-3.879-1.168-5.168-2.457A13.134 13.134 0 0 1 1.172 8z"/><path d="M8 5.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM4.5 8a3.5 3.5 0 1 1 7 0 3.5 3.5 0 0 1-7 0z"/>';
            }
        });
    </script>
</body>
</html>
HTML
