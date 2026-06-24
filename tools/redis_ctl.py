#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# requires python3.4+

from __future__ import print_function

import argparse
import os
import signal
import subprocess
import sys
import time

if sys.version_info[0] < 3:
    print("requires python3", file=sys.stderr)
    sys.exit(1)

DEFAULT_PORT = 8001
DEFAULT_PASSWORD = "r12345"
DEFAULT_BIND = "0.0.0.0"
DEFAULT_USER = "root"
DEFAULT_CONFIG = "/etc/redis/{port}.conf"
DEFAULT_PIDFILE = "/var/run/redis/{port}.pid"
DEFAULT_DATADIR = "/var/lib/redis_{port}"
DEFAULT_LOGFILE = "/var/log/redis/{port}.log"
DEFAULT_INIT_SCRIPT = "/etc/init.d/redis_{port}"


def paths(port):
    return {
        "port": port,
        "config": DEFAULT_CONFIG.format(port=port),
        "pidfile": DEFAULT_PIDFILE.format(port=port),
        "datadir": DEFAULT_DATADIR.format(port=port),
        "logfile": DEFAULT_LOGFILE.format(port=port),
        "init_script": DEFAULT_INIT_SCRIPT.format(port=port),
    }


def run(cmd, check=True, capture=False):
    stdout = subprocess.PIPE if capture else None
    stderr = subprocess.PIPE if capture else None
    p = subprocess.Popen(cmd, stdout=stdout, stderr=stderr)
    out, err = p.communicate()
    if capture:
        class Result(object):
            pass
        r = Result()
        r.returncode = p.returncode
        r.stdout = out.decode("utf-8", "replace") if out else ""
        r.stderr = err.decode("utf-8", "replace") if err else ""
        if check and r.returncode != 0:
            sys.exit(r.returncode)
        return r
    if check and p.returncode != 0:
        sys.exit(p.returncode)
    return p.returncode


def require_root():
    if os.geteuid() != 0:
        print("需要 root 权限，请使用 sudo", file=sys.stderr)
        sys.exit(1)


def read_pid(pidfile):
    if not os.path.isfile(pidfile):
        return None
    try:
        with open(pidfile, "r") as f:
            return int(f.read().strip())
    except (IOError, ValueError):
        return None


def is_pid_alive(pid):
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def redis_ping(port, password):
    cmd = ["redis-cli", "-p", str(port), "-a", password, "ping"]
    try:
        r = run(cmd, check=False, capture=True)
        return r.returncode == 0 and "PONG" in (r.stdout or "")
    except OSError:
        return False


def is_running(p, password):
    pid = read_pid(p["pidfile"])
    return is_pid_alive(pid) or redis_ping(p["port"], password)


def config_content(p, password, bind):
    return """port {port}
bind {bind}
requirepass {password}
daemonize yes
pidfile {pidfile}
dir {datadir}
logfile {logfile}
databases 16
save 900 1
save 300 10
save 60 10000
""".format(
        port=p["port"],
        bind=bind,
        password=password,
        pidfile=p["pidfile"],
        datadir=p["datadir"],
        logfile=p["logfile"],
    )


def init_script_content(p):
    return """#!/bin/sh
### BEGIN INIT INFO
# Provides:          redis_{port}
# Required-Start:    $network $remote_fs $local_fs
# Required-Stop:     $network $remote_fs $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Redis instance on port {port}
### END INIT INFO

CONF="{config}"
PIDFILE="{pidfile}"

case "$1" in
  start)
    if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
      echo "redis:{port} already running"
      exit 0
    fi
    redis-server "$CONF"
    ;;
  stop)
    if [ -f "$PIDFILE" ]; then
      kill -TERM $(cat "$PIDFILE") 2>/dev/null
      for i in 1 2 3 4 5; do
        kill -0 $(cat "$PIDFILE") 2>/dev/null || exit 0
        sleep 1
      done
      kill -9 $(cat "$PIDFILE") 2>/dev/null
    fi
    ;;
  restart)
    $0 stop
    sleep 1
    $0 start
    ;;
  status)
    if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
      echo "redis:{port} running (pid $(cat $PIDFILE))"
      exit 0
    fi
    echo "redis:{port} stopped"
    exit 1
    ;;
  *)
    echo "Usage: $0 {{start|stop|restart|status}}"
    exit 1
    ;;
esac
""".format(port=p["port"], config=p["config"], pidfile=p["pidfile"])


def write_file(path, content, mode=0o644):
    parent = os.path.dirname(path)
    if parent and not os.path.isdir(parent):
        os.makedirs(parent)
    with open(path, "w") as f:
        f.write(content)
    os.chmod(path, mode)


def chown_redis(path, user):
    import pwd
    try:
        uid = pwd.getpwnam(user).pw_uid
        gid = pwd.getpwnam(user).pw_gid
        if os.path.isdir(path):
            for root, dirs, files in os.walk(path):
                for name in dirs + files:
                    os.chown(os.path.join(root, name), uid, gid)
        os.chown(path, uid, gid)
    except KeyError:
        print("用户 {0} 不存在，跳过 chown".format(user), file=sys.stderr)


def cmd_install(args):
    require_root()
    p = paths(args.port)
    ##run(["apt-get", "update"], check=False)
    ##run(["apt-get", "install", "-y", "redis-server"])
    for d in (p["datadir"], os.path.dirname(p["pidfile"]), os.path.dirname(p["logfile"])):
        if not os.path.isdir(d):
            os.makedirs(d)
    write_file(p["config"], config_content(p, args.password, args.bind))
    write_file(p["init_script"], init_script_content(p), mode=0o755)
    chown_redis(p["datadir"], args.user)
    chown_redis(os.path.dirname(p["pidfile"]), args.user)
    chown_redis(os.path.dirname(p["logfile"]), args.user)
    run(["update-rc.d", os.path.basename(p["init_script"]), "defaults"], check=False)
    print("install 完成: {0}".format(p["config"]))


def cmd_start(args):
    p = paths(args.port)
    if is_running(p, args.password):
        print("redis:{0} 已在运行".format(args.port))
        return
    if not os.path.isfile(p["config"]):
        print("配置文件不存在: {0}，请先 install".format(p["config"]), file=sys.stderr)
        sys.exit(1)
    if os.geteuid() == 0 and os.path.isfile(p["init_script"]):
        run([p["init_script"], "start"])
    else:
        run(["redis-server", p["config"]])
    time.sleep(0.5)
    if redis_ping(args.port, args.password):
        print("redis:{0} 已启动".format(args.port))
    else:
        print("redis:{0} 启动失败".format(args.port), file=sys.stderr)
        sys.exit(1)


def cmd_stop(args):
    p = paths(args.port)
    if not is_running(p, args.password):
        print("redis:{0} 未运行".format(args.port))
        return
    pid = read_pid(p["pidfile"])
    if pid and is_pid_alive(pid):
        os.kill(pid, signal.SIGTERM)
        for _ in range(10):
            if not is_pid_alive(pid):
                break
            time.sleep(0.5)
        if is_pid_alive(pid):
            os.kill(pid, signal.SIGKILL)
    if redis_ping(args.port, args.password):
        run(["redis-cli", "-p", str(args.port), "-a", args.password, "shutdown"], check=False)
        time.sleep(0.5)
    if is_running(p, args.password):
        print("redis:{0} 停止失败".format(args.port), file=sys.stderr)
        sys.exit(1)
    print("redis:{0} 已停止".format(args.port))


def cmd_restart(args):
    cmd_stop(args)
    time.sleep(1)
    cmd_start(args)


def cmd_status(args):
    p = paths(args.port)
    pid = read_pid(p["pidfile"])
    alive = is_pid_alive(pid)
    pong = redis_ping(args.port, args.password)
    if alive or pong:
        info = "pid={0}".format(pid) if alive else "pid=unknown"
        print("redis:{0} running ({1}, ping={2})".format(args.port, info, "PONG" if pong else "FAIL"))
        sys.exit(0)
    print("redis:{0} stopped".format(args.port))
    sys.exit(1)


def cmd_uninstall(args):
    require_root()
    p = paths(args.port)
    if is_running(p, args.password):
        cmd_stop(args)
    run(["update-rc.d", "-f", os.path.basename(p["init_script"]), "remove"], check=False)
    for f in (p["config"], p["init_script"], p["pidfile"]):
        if os.path.isfile(f):
            os.remove(f)
    if args.purge_data and os.path.isdir(p["datadir"]):
        import shutil
        shutil.rmtree(p["datadir"])
    print("uninstall 完成")


def build_parser():
    parser = argparse.ArgumentParser(description="Redis 实例管理 (Debian 8)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--password", default=DEFAULT_PASSWORD)
    parser.add_argument("--bind", default=DEFAULT_BIND)
    parser.add_argument("--user", default=DEFAULT_USER)
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("install")
    sub.add_parser("start")
    sub.add_parser("stop")
    sub.add_parser("restart")
    sub.add_parser("status")
    p_un = sub.add_parser("uninstall")
    p_un.add_argument("--purge-data", action="store_true")
    return parser


def main():
    parser = build_parser()
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(1)
    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)
    handlers = {
        "install": cmd_install,
        "start": cmd_start,
        "stop": cmd_stop,
        "restart": cmd_restart,
        "status": cmd_status,
        "uninstall": cmd_uninstall,
    }
    handlers[args.command](args)


if __name__ == "__main__":
    main()
