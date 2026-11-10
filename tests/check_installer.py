#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import socket
import subprocess
import tempfile
import time
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlsplit


ROOT = Path(__file__).resolve().parents[1]
UI_HOST = "community.test"
AUTH_HOST = "auth.community.test"
CAMUNDA_HOST = "camunda.community.test"
RUNTIME_CLIENT = "unibpm-integration-runtime"
MODES = {
    "local": ("local", "http"),
    "path-http": ("path", "http"),
    "path-https": ("path", "https"),
    "subdomain-http": ("subdomain", "http"),
    "subdomain-https": ("subdomain", "https"),
}


def command(args, directory, env=None):
    result = subprocess.run(args, cwd=directory, env=env, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"{args[0]} exited with {result.returncode}")
    return result.stdout


def copy_installer(directory):
    for name in ("install.sh", "prepare.sh", ".env.example", "docker-compose.yml"):
        shutil.copy2(ROOT / name, directory)
    for name in ("config-templates", "keycloak", "nginx", "postgres"):
        shutil.copytree(ROOT / name, directory / name)


def settings(mode, expose_camunda):
    routing, scheme = MODES[mode]
    return {
        "DEPLOY_MODE": "local" if routing == "local" else "edge",
        "EDGE_ROUTING_MODE": "subdomain" if routing == "local" else routing,
        "ENABLE_TLS": str(scheme == "https").lower(),
        "EXPOSE_CAMUNDA": str(expose_camunda).lower(),
        "UNIBPM_DOMAIN": UI_HOST,
        "KEYCLOAK_DOMAIN": AUTH_HOST,
        "CAMUNDA_DOMAIN": CAMUNDA_HOST,
    }


def write_env(directory, variables):
    example = (directory / ".env.example").read_text()
    overrides = "\n".join(f"{name}={value}" for name, value in variables.items())
    (directory / ".env").write_text(f"{example}\n{overrides}\n")


def check_config(modes):
    for name in ("install.sh", "prepare.sh"):
        command(["bash", "-n", name], ROOT)
    model = json.loads(command([
        "docker", "compose", "-f", "docker-compose.yml", "--env-file", ".env.example",
        "config", "--format", "json",
    ], ROOT))["services"]
    assert not model[RUNTIME_CLIENT].get("ports"), "runtime publishes a host port"
    assert model[RUNTIME_CLIENT]["depends_on"]["kafka"]["condition"] == "service_healthy"
    assert model["unibpm-engine"]["ports"][0]["host_ip"] == "127.0.0.1"
    for name in ("unibpm", "unibpm-engine", "unibpm-frontend", RUNTIME_CLIENT, "unibpm-keycloak"):
        assert model[name]["platform"] == "linux/amd64", f"unexpected platform for {name}"
        assert model[name]["healthcheck"]["test"], f"missing readiness check for {name}"
    assert model["nginx"]["healthcheck"]["test"]
    assert "keycloak" in model["unibpm-keycloak"]["networks"]["unibpm"]["aliases"]

    for mode in modes:
        routing, scheme = MODES[mode]
        for expose in (False, True) if routing != "local" else (False,):
            with tempfile.TemporaryDirectory(prefix="unibpm-config-") as temp:
                directory = Path(temp)
                copy_installer(directory)
                write_env(directory, settings(mode, expose))
                (directory / "prepare.sh").write_text(
                    '#!/usr/bin/env bash\nprintf "%s\\n" "$KEYCLOAK_EXTERNAL_URL" > issuer.txt\n'
                )
                fake_docker = directory / "docker"
                fake_docker.write_text('''#!/usr/bin/env bash
case "$*" in
  'compose version --short') echo 2.24.4 ;;
  'compose run --rm certbot '*) printf '%s\\n' "$@" > certbot.args ;;
  'compose up '*) touch services-started ;;
  'compose exec -T nginx nginx -t') [[ "${FAIL_NGINX_CONFIG:-}" != 1 ]] ;;
esac
''')
                fake_docker.chmod(0o755)
                fake_env = {**os.environ, "PATH": f"{directory}:{os.environ['PATH']}"}
                command(["bash", "install.sh"], directory, fake_env)
                auth_host = AUTH_HOST if routing == "subdomain" else UI_HOST
                expected = ("http://localhost:8082/keycloak" if routing == "local"
                            else f"{scheme}://{auth_host}/keycloak")
                assert (directory / "issuer.txt").read_text().strip() == expected
                nginx_config = directory / "generated/nginx/default.conf"
                if routing == "local":
                    assert not nginx_config.exists()
                    (directory / "services-started").unlink()
                    for invalid, expected_error in (
                        ({"DEPLOY_MODE": "locla"}, "DEPLOY_MODE"),
                        ({"DEPLOY_MODE": "edge", "EDGE_ROUTING_MODE": "paths"}, "EDGE_ROUTING_MODE"),
                        ({"DEPLOY_MODE": "edge", "ENABLE_TLS": "true", "LETSENCRYPT_EMAIL": ""}, "LETSENCRYPT_EMAIL"),
                    ):
                        write_env(directory, {**settings("local", False), **invalid})
                        rejected = subprocess.run(["bash", "install.sh"], cwd=directory, env=fake_env,
                                                  capture_output=True, text=True)
                        assert rejected.returncode and expected_error in rejected.stderr
                        assert not (directory / "services-started").exists()
                    continue
                nginx = nginx_config.read_text()
                assert ("listen 443 ssl;" in nginx) == (scheme == "https")
                assert ("unibpm-engine:8080" in nginx) == expose
                if routing == "path" and expose:
                    assert "oauth2/authorization|login/oauth2/code" in nginx
                args_file = directory / "certbot.args"
                if scheme == "https":
                    args = args_file.read_text().splitlines()
                    domains = [args[index + 1] for index, arg in enumerate(args) if arg == "-d"]
                    expected_domains = [UI_HOST] if routing == "path" else [UI_HOST, AUTH_HOST]
                    if routing == "subdomain" and expose:
                        expected_domains.append(CAMUNDA_HOST)
                    assert domains == expected_domains
                    if not expose:
                        rejected = subprocess.run(["bash", "install.sh"], cwd=directory,
                                                  env={**fake_env, "FAIL_NGINX_CONFIG": "1"},
                                                  capture_output=True, text=True)
                        assert rejected.returncode and "Installed." not in rejected.stdout
                        assert "listen 443 ssl;" not in nginx_config.read_text()
                else:
                    assert not args_file.exists()
        print(f"PASS config {mode}", flush=True)


def free_ports(count):
    sockets = [socket.socket() for _ in range(count)]
    try:
        for listener in sockets:
            listener.bind(("127.0.0.1", 0))
        return [listener.getsockname()[1] for listener in sockets]
    finally:
        for listener in sockets:
            listener.close()


def wait_for(check, description):
    deadline = time.monotonic() + 120
    while True:
        try:
            return check()
        except RuntimeError as error:
            if time.monotonic() >= deadline:
                raise RuntimeError(f"{description}: {error}") from error
            time.sleep(2)


class LoginForm(HTMLParser):
    action = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "form" and attrs.get("id") == "kc-form-login":
            self.action = attrs.get("action")


def smoke(directory, mode, ports):
    front, camunda, keycloak, _, http, https = ports
    routing, scheme = MODES[mode]
    public_ui = f"http://localhost:{front}" if routing == "local" else f"{scheme}://{UI_HOST}"
    auth_host = AUTH_HOST if routing == "subdomain" else UI_HOST
    public_auth = f"http://localhost:{keycloak}" if routing == "local" else f"{scheme}://{auth_host}"
    public_camunda = (f"http://localhost:{camunda}" if routing == "local"
                      else f"{scheme}://{CAMUNDA_HOST if routing == 'subdomain' else UI_HOST}")
    issuer = f"{public_auth}/keycloak/realms/unibpm"
    local_auth = f"http://localhost:{keycloak}/keycloak"
    engine = f"http://localhost:{camunda}/engine-rest"
    curl_args = ["curl", "--noproxy", "*", "-fsS", "--max-time", "12", "--cacert", "test-ca.pem"]
    for host in (UI_HOST, AUTH_HOST, CAMUNDA_HOST):
        curl_args += ["--connect-to", f"{host}:80:127.0.0.1:{http}",
                      "--connect-to", f"{host}:443:127.0.0.1:{https}"]

    def request(url, *args):
        return command([*curl_args, *args, url], directory)

    def token(realm, **fields):
        body = request(f"{local_auth}/realms/{realm}/protocol/openid-connect/token",
                       "--data", urlencode(fields))
        return json.loads(body)["access_token"]

    metadata = wait_for(lambda: json.loads(request(f"{issuer}/.well-known/openid-configuration")),
                        "public Keycloak discovery")
    assert metadata["issuer"] == issuer
    admin = token("master", grant_type="password", client_id="admin-cli", username="admin", password="admin")
    admin_header = ("-H", f"Authorization: Bearer {admin}")
    admin_api = f"{local_auth}/admin/realms/unibpm"

    def service_token(client_id):
        clients = json.loads(request(f"{admin_api}/clients?clientId={client_id}", *admin_header))
        assert len(clients) == 1, f"expected one client {client_id}"
        secret = json.loads(request(f"{admin_api}/clients/{clients[0]['id']}/client-secret", *admin_header))
        return token("unibpm", grant_type="client_credentials", client_id=client_id, client_secret=secret["value"])

    runtime_token = service_token(RUNTIME_CLIENT)
    wait_for(lambda: request(f"{public_ui}/api/ticket/list?size=1", "-H", f"Authorization: Bearer {runtime_token}",
                             "-o", os.devnull), "UniBPM API through the frontend")
    engine_token = service_token("unibpm-camunda-client")

    def engine_request(path, *args):
        return request(engine + path, "-H", f"Authorization: Bearer {engine_token}", *args)

    wait_for(lambda: engine_request("/version"), "Camunda REST API")
    engine_request("/deployment/create", "-F", "deployment-name=installer-smoke", "-F",
                   f"data=@{ROOT / 'tests/runtime-smoke.bpmn'}")
    process = json.loads(engine_request("/process-definition/key/community_runtime_smoke/start",
                                       "-H", "Content-Type: application/json", "--data", '{}'))["id"]

    def completed():
        history = json.loads(engine_request(f"/history/process-instance/{process}"))
        if history["state"] != "COMPLETED":
            raise RuntimeError(f"process state is {history['state']}")

    wait_for(completed, "External Task process completion")
    variables = json.loads(engine_request(f"/history/variable-instance?processInstanceId={process}&deserializeValues=false"))
    assert {"demoHandled", "communityTickets"} <= {item["name"] for item in variables}

    demo = json.loads(request(f"{admin_api}/users?username=admin&exact=true", *admin_header))[0]
    request(f"{admin_api}/users/{demo['id']}", *admin_header, "-X", "PUT", "-H", "Content-Type: application/json",
            "--data", '{"firstName":"Installer","lastName":"Smoke","email":"smoke@example.test","emailVerified":true}')
    callback = public_camunda + "/login/oauth2/code/keycloak"
    redirect = request(public_camunda + "/oauth2/authorization/keycloak", "-o", os.devnull, "-w", "%{redirect_url}")
    assert parse_qs(urlsplit(redirect).query)["redirect_uri"] == [callback]
    with tempfile.NamedTemporaryFile(dir=directory) as cookies:
        browser = ("-L", "--proto-redir", f"={scheme}", "--max-redirs", "12", "-b", cookies.name, "-c", cookies.name)
        cockpit = public_camunda + "/camunda/app/cockpit/default/"
        form = LoginForm()
        form.feed(request(cockpit, *browser))
        assert form.action and form.action.startswith(issuer + "/login-actions/"), "missing Keycloak login form"
        landed = request(form.action, *browser, "--data", urlencode({"username": "admin", "password": "admin"}),
                         "-o", os.devnull, "-w", "%{url_effective}")
        assert landed.startswith(cockpit), "Camunda login did not return to Cockpit"
    print(f"PASS Docker {mode} (issuer, API, BPMN, Camunda login)", flush=True)


def check_docker(modes):
    with tempfile.TemporaryDirectory(prefix="unibpm-smoke-") as temp:
        directory = Path(temp)
        copy_installer(directory)
        ports = free_ports(6)
        front, camunda, keycloak, backend, http, https = ports
        (directory / "compose.smoke.yml").write_text(f'''services:
  unibpm:
    ports: !override ["127.0.0.1:{backend}:8099"]
  unibpm-frontend:
    ports: !override ["127.0.0.1:{front}:80"]
  nginx:
    ports: !override ["127.0.0.1:{http}:80", "127.0.0.1:{https}:443"]
''')
        cert_dir = directory / "letsencrypt/conf/live" / UI_HOST
        cert_dir.mkdir(parents=True)
        command(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", f"/CN={UI_HOST}",
                 "-addext", f"subjectAltName=DNS:{UI_HOST},DNS:{AUTH_HOST},DNS:{CAMUNDA_HOST}",
                 "-keyout", str(cert_dir / "privkey.pem"), "-out", str(cert_dir / "fullchain.pem")], directory)
        shutil.copyfile(cert_dir / "fullchain.pem", directory / "test-ca.pem")
        project = "installer-smoke-" + directory.name.rsplit("-", 1)[1]
        env = {**os.environ, "COMPOSE_PROJECT_NAME": project, "COMPOSE_FILE": "docker-compose.yml:compose.smoke.yml"}
        try:
            for mode in modes:
                write_env(directory, {**settings(mode, True), "FRONT_PUBLIC_PORT": front, "CAMUNDA_PUBLIC_PORT": camunda,
                                      "KEYCLOAK_PUBLIC_PORT": keycloak, "BACKEND_PUBLIC_PORT": backend,
                                      "KEYCLOAK_INTERNAL_URL": f"http://localhost:{keycloak}/keycloak"})
                print(f"Running isolated Docker smoke for {mode}", flush=True)
                subprocess.run(["bash", "install.sh"], cwd=directory, env=env, check=True)
                services = ["unibpm", "unibpm-engine", "unibpm-frontend", RUNTIME_CLIENT]
                if mode != "local":
                    services.append("nginx")
                containers = command(["docker", "compose", "ps", "-q", *services], directory, env).split()
                health = command(["docker", "inspect", "--format", "{{.State.Health.Status}}", *containers],
                                 directory, env).splitlines()
                assert health == ["healthy"] * len(services), f"installer returned before services were ready: {health}"
                for config in ("unibpm", "engine", "integration-runtime"):
                    assert (directory / f"generated/{config}/application.yaml").stat().st_mode & 0o777 == 0o600
                smoke(directory, mode, ports)
        finally:
            subprocess.run(["docker", "compose", "down", "--volumes"], cwd=directory, env=env, check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Check Community Installer modes")
    parser.add_argument("--docker", action="store_true", help="start an isolated Docker stack and run end-to-end checks")
    parser.add_argument("--mode", choices=MODES, help="check a single mode (default: all five)")
    args = parser.parse_args()
    modes = [args.mode] if args.mode else list(MODES)
    check_config(modes)
    if args.docker:
        check_docker(modes)
