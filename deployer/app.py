"""
Deployer Sidecar - Flask API for managing app deployments.

This is the ONLY container with Docker socket access. It exposes 4 endpoints
that map 1:1 to the deploy scripts. OpenClaw calls these via HTTP.

Endpoints:
    POST /deploy        Deploy an app (build + DNS + start)
    POST /stop          Stop a running app
    GET  /status        List all apps or one app's status
    GET  /logs/<name>   Get app container logs
"""

import os
import re
import subprocess

from flask import Flask, jsonify, request

app = Flask(__name__)

SCRIPTS_DIR = os.environ.get("SCRIPTS_DIR", "/deploy-scripts")
VALID_APP_NAME = re.compile(r"^[a-z][a-z0-9-]*$")


def validate_app_name(name):
    """Validate app name to prevent path traversal and bad input."""
    if not name or not isinstance(name, str):
        return False
    if len(name) > 63:  # DNS label limit
        return False
    return bool(VALID_APP_NAME.match(name))


def run_script(script_name, args=None, timeout=300):
    """Run a deploy script and capture output."""
    script_path = os.path.join(SCRIPTS_DIR, script_name)

    if not os.path.isfile(script_path):
        return {
            "success": False,
            "output": f"Script not found: {script_name}",
            "exit_code": -1,
        }

    cmd = ["bash", script_path] + (args or [])

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            env={**os.environ, "WORKSPACE_DIR": os.environ.get("WORKSPACE_DIR", "/workspace")},
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


@app.route("/deploy", methods=["POST"])
def deploy():
    """Deploy an app. Expects JSON: {"app_name": "my-app", "port": 80}"""
    data = request.get_json(silent=True) or {}

    app_name = data.get("app_name", "")
    port = data.get("port", "")

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

    result = run_script("deploy-app.sh", [app_name, port], timeout=600)
    status_code = 200 if result["success"] else 500
    return jsonify(result), status_code


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
