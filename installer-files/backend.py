import os
import socket
import subprocess
import systemd.daemon
import threading
import time

import flask
from flask import Flask, make_response, request
from flask_cors import CORS
from flask_sock import Sock
from simple_websocket import ConnectionClosed

app = Flask(__name__)
sock = Sock(app)
CORS(app)


class Context(object):
    def __init__(self):
        self.running_subprocess = None
        self.running_parameters = {}
        self.subprocess_output = ""
        self.output_readers = []


context = Context()
# inherit environment variables from systemd (and installer.ini)
context.running_parameters.update(os.environ)
context.running_parameters["NON_INTERACTIVE"] = "yes"
INSTALLER_SCRIPT = os.environ["INSTALLER_SCRIPT"]


@app.route("/login", methods=["GET"])
def login():
    hostname = socket.gethostname()
    has_efi = os.path.exists("/sys/firmware/efi")
    return {"hostname": hostname,
            "has_efi": has_efi,
            "running": context.running_subprocess is not None,
            "environ": context.running_parameters}


@app.route("/block_devices", methods=["GET"])
def get_block_devices():
    p = subprocess.run(["lsblk", "-OJ"], capture_output=True, text=True)
    return p.stdout


@app.route("/install", methods=["POST"])
def install():
    if context.running_subprocess is not None:
        app.logger.error("Process already running")
        flask.abort(409, "Already running")

    for k, v in request.form.items():
        context.running_parameters[k] = v
        app.logger.info(f"  env: {k} = {v}")

    do_start_installation()
    return {}


def do_start_installation():
    context.running_subprocess = subprocess.Popen(INSTALLER_SCRIPT,
                                                  env=context.running_parameters,
                                                  text=True,
                                                  stdout=subprocess.PIPE,
                                                  stderr=subprocess.PIPE)

    def output_reader(fd, main):
        app.logger.info("Starting output reader thread")
        for line in fd:
            print(line, end="")
            to_remove = []
            for websocket in context.output_readers:
                try:
                    websocket.send(line)
                except ConnectionClosed:
                    to_remove.append(websocket)
            for websocket in to_remove:
                app.logger.info(f"Removing websocket output reader {websocket}")
                context.output_readers.remove(websocket)
            context.subprocess_output += line
        app.logger.info("Output reader thread finished")
        if main:
            for websocket in context.output_readers:
                websocket.close()

    threading.Thread(target=output_reader,
                     args=(context.running_subprocess.stdout, True),
                     name="Stdout reader") \
        .start()
    threading.Thread(target=output_reader,
                     args=(context.running_subprocess.stderr, False),
                     name="Stderr reader") \
        .start()


@app.route("/clear", methods=["GET"])
def clear():
    if context.running_subprocess is None:
        return {}
    if context.running_subprocess.poll() is None:
        # still running
        context.running_subprocess.terminate()
        return {}
    context.running_subprocess = None
    context.subprocess_output = ""
    return {}


@app.route("/process_status", methods=["GET"])
def get_process_status():
    status = {"status": "RUNNING",
              "output": context.subprocess_output,
              "return_code": -1}
    if context.running_subprocess is None:
        app.logger.error(f"No subprocess")
        flask.abort(404, "No such process")
    return_code = context.running_subprocess.poll()
    if return_code is None:
        return status
    status["command"] = context.running_subprocess.args
    status["status"] = "FINISHED"
    status["return_code"] = context.running_subprocess.returncode
    return status


@app.route("/download_log", methods=["GET"])
def download_log():
    resp = make_response(str(context.subprocess_output))
    resp.headers["Content-Type"] = 'text/plain;charset=UTF-8'
    resp.headers['Content-Disposition'] = 'attachment;filename=installer.log'
    return resp


@sock.route("/process_output")
def get_process_output(ws):
    app.logger.info("Websocket connected")
    ws.send(context.subprocess_output)
    context.output_readers.append(ws)
    while ws in context.output_readers:
        time.sleep(60)
    app.logger.info("Websocket closing")
    
    
systemd.daemon.notify("READY=1")

if os.environ.get("AUTO_INSTALL", None) == "true":
    app.logger.info("Automatically starting the installation")
    do_start_installation()
