"""
Deployer Sidecar - Flask API for managing app deployments.

This is the ONLY container with Docker socket access. It exposes endpoints
that map to the deploy scripts. OpenClaw calls these via HTTP.

Endpoints:
    POST /deploy     Deploy an app (add "basic_auth": true for HTTP Basic Auth)
    POST /stop       Stop a running app
    GET  /status     List all apps or one app's status
    GET  /logs/<name> Get app container logs
"""

import os
import re
import subprocess

import bcrypt
from flask import Flask, jsonify, request

app = Flask(__name__)

SCRIPTS_DIR = os.environ.get("SCRIPTS_DIR", "/deploy-scripts")
WORKSPACE_DIR = os.environ.get("WORKSPACE_DIR", "/workspace")
ENV_FILE = os.path.join(WORKSPACE_DIR, "config", ".env")
VALID_APP_NAME = re.compile(r"^[a-z][a-z0-9-]*$")


def validate_app_name(name):
    """Validate app name to prevent path traversal and bad input."""
    if not name or not isinstance(name, str):
        return False
    if len(name) > 63:  # DNS label limit
        return False
    return bool(VALID_APP_NAME.match(name))


def run_script(script_name, args=None, timeout=300, env_extra=None):
    """Run a deploy script and capture output. env_extra: optional dict merged into env."""
    script_path = os.path.join(SCRIPTS_DIR, script_name)

    if not os.path.isfile(script_path):
        return {
            "success": False,
            "output": f"Script not found: {script_name}",
            "exit_code": -1,
        }

    cmd = ["bash", script_path] + (args or [])
    base_env = {**os.environ, "WORKSPACE_DIR": os.environ.get("WORKSPACE_DIR", "/workspace")}
    run_env = {**base_env, **(env_extra or {})}

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=run_env,
        )
        output = result.stdout
        if result.stderr:
            output += "\n--- stderr ---\n" + result.stderr

        return {
            "success": result.returncode == 0,
            "output": output.strip(),
            "exit_code": result.returncode,
        }
    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "output": f"Script timed out after {timeout}s",
            "exit_code": -1,
        }
    except Exception as e:
        return {
            "success": False,
            "output": f"Error running script: {str(e)}",
            "exit_code": -1,
        }


def _load_env_pairs(path):
    """Load KEY=VALUE pairs from a .env-style file. Returns dict (strips optional quotes)."""
    out = {}
    if not os.path.isfile(path):
        return out
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip().strip("'\"")
    return out


def _generate_basic_auth_hash(username, password):
    """Generate Traefik-compatible basic auth string: user:$2y$... (bcrypt).

    Uses $2y$ prefix (Apache htpasswd format) so all Traefik versions accept it.
    rounds=12 matches the NIST-recommended minimum cost factor.
    """
    raw = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(rounds=12))
    # Python's bcrypt outputs $2b$; replace with $2y$ for Apache/Traefik compatibility.
    hashed = raw.decode("utf-8").replace("$2b$", "$2y$", 1)
    return f"{username}:{hashed}"


def _deploy(app_name, port, basic_auth=False):
    """Shared deploy logic used by /deploy and /deploy-secure."""
    if not validate_app_name(app_name):
        return jsonify({
            "success": False,
            "output": "Invalid app_name. Must be lowercase, start with a letter, use only letters/numbers/hyphens, max 63 chars.",
            "exit_code": -1,
        }), 400

    port = str(port)
    if not port.isdigit():
        return jsonify({
            "success": False,
            "output": f"Invalid port: {port}. Must be a number.",
            "exit_code": -1,
        }), 400

    args = [app_name, port]
    env_extra = None

    if basic_auth:
        env_vars = _load_env_pairs(ENV_FILE)
        auth_user = env_vars.get("BASIC_AUTH_USER", "").strip()
        auth_pass = env_vars.get("BASIC_AUTH_PASS", "").strip()
        if not auth_user or not auth_pass:
            return jsonify({
                "success": False,
                "output": "BASIC_AUTH_USER and BASIC_AUTH_PASS must be set in deployer config/.env for secure deploy.",
                "exit_code": -1,
            }), 400
        args.append("basic_auth")
        env_extra = {"BASIC_AUTH_HASH": _generate_basic_auth_hash(auth_user, auth_pass)}

    result = run_script("deploy-app.sh", args, timeout=600, env_extra=env_extra)
    status_code = 200 if result["success"] else 500
    return jsonify(result), status_code


@app.route("/deploy", methods=["POST"])
def deploy():
    """Deploy an app. Expects JSON: {"app_name": "my-app", "port": 80}.
    Optional: "basic_auth": true to enable Traefik HTTP Basic Auth.
    Basic auth can also be enabled by placing a .secure-deploy file in the app directory."""
    data = request.get_json(silent=True) or {}
    basic_auth = data.get("basic_auth", False) or data.get("secure", False)
    return _deploy(data.get("app_name", ""), data.get("port", ""), basic_auth=bool(basic_auth))


@app.route("/stop", methods=["POST"])
def stop():
    """Stop an app. Expects JSON: {"app_name": "my-app"}"""
    data = request.get_json(silent=True) or {}

    app_name = data.get("app_name", "")

    if not validate_app_name(app_name):
        return jsonify({
            "success": False,
            "output": "Invalid app_name.",
            "exit_code": -1,
        }), 400

    result = run_script("stop-app.sh", [app_name])
    status_code = 200 if result["success"] else 500
    return jsonify(result), status_code


@app.route("/status", methods=["GET"])
def status():
    """Get app status. Optional query param: ?app_name=my-app"""
    app_name = request.args.get("app_name", "")

    if app_name:
        if not validate_app_name(app_name):
            return jsonify({
                "success": False,
                "output": "Invalid app_name.",
                "exit_code": -1,
            }), 400
        result = run_script("status-app.sh", [app_name])
    else:
        result = run_script("status-app.sh")

    status_code = 200 if result["success"] else 500
    return jsonify(result), status_code


@app.route("/logs/<app_name>", methods=["GET"])
def logs(app_name):
    """Get app logs. Optional query param: ?lines=50"""
    if not validate_app_name(app_name):
        return jsonify({
            "success": False,
            "output": "Invalid app_name.",
            "exit_code": -1,
        }), 400

    lines = request.args.get("lines", "50")
    if not lines.isdigit():
        lines = "50"

    result = run_script("logs-app.sh", [app_name, lines])
    status_code = 200 if result["success"] else 500
    return jsonify(result), status_code


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
