#!/usr/bin/env python3
"""Disposable-only close-and-clean prototype. No production capability implied.
Group approval is directory identity, never authority for personal-file cleanup.
Process observations and descriptor traversal do not eliminate final-unlink races.
"""
import argparse, json, os, pathlib, re, stat, subprocess, sys, time
FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW

def identity(info): return [info.st_dev, info.st_ino, info.st_uid]

def activity(bundle, root):
    fixture = os.environ.get('STILL_CHROME_PROBE_PROCESS_FIXTURE')
    if fixture:
        path = pathlib.Path(fixture)
        if path != root/'process-fixture.json' or path.is_symlink(): raise ValueError('owned process fixture required')
        observation = json.loads(path.read_text())
        output = observation['psOutput']
        if isinstance(output, list):
            if not output: raise ValueError('controlled process observations exhausted')
            current = output.pop(0); path.write_text(json.dumps(observation)); output = current
    else:
        if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted': raise ValueError('real process observation is hosted-only')
        output = subprocess.check_output(['/bin/ps', '-axo', 'pid=,command='], text=True, timeout=5)
    if not isinstance(output, str) or not output.strip(): raise ValueError('process observation unavailable')
    # Browser and helpers execute inside the verified bundle. A process whose
    # argument merely mentions it causes conservative refusal, never permission.
    for line in output.splitlines():
        pid, separator, command = line.strip().partition(' ')
        if not pid.isdigit() or not separator or not command.strip(): raise ValueError('process observation malformed')
        if int(pid) not in (os.getpid(), os.getppid()) and bundle + '/' in command:
            raise ValueError('browser or helper activity observed')

def open_chain(root, cache):
    current = os.open(root, FLAGS); opened = [current]
    try:
        for component in cache.relative_to(root).parts:
            current = os.open(component, FLAGS, dir_fd=current); opened.append(current)
        for fd in opened:
            info = os.fstat(fd)
            if info.st_uid != os.getuid() or info.st_mode & 0o022: raise ValueError('ambiguous directory ownership/access')
        return opened
    except Exception:
        for fd in opened: os.close(fd)
        raise

def run():
    root, cache, bundle = map(pathlib.Path, sys.argv[1:4]); command = sys.argv[4]
    options = argparse.ArgumentParser(description='Disposable qualification pacing; not production performance evidence')
    options.add_argument('--progress', action='store_true')
    options.add_argument('--pace-ms', type=int, default=0)
    settings = options.parse_args(sys.argv[5:])
    if not 0 <= settings.pace_ms <= 1000: raise ValueError('qualification pace must be 0–1000 ms')
    if not root.is_absolute() or not root.name.startswith('StillChromeProbe-') or root != root.resolve(): raise ValueError('owned canonical disposable root required')
    if not cache.is_absolute() or cache.name != 'Cache_Data' or cache.parent.name != 'Cache': raise ValueError('explicit asset cache group required')
    if not bundle.is_absolute(): raise ValueError('explicit browser bundle required')
    relative = cache.relative_to(root)
    if any(p in ('', '.', '..') for p in relative.parts): raise ValueError('invalid group path')
    activity(str(bundle), root)
    opened = open_chain(root, cache)
    try:
        observed = {'schema': 1, 'relativeGroup': str(relative), 'directories': [identity(os.fstat(fd)) for fd in opened]}
        if command == 'observe': print(json.dumps(observed)); return
        if command != 'clean' or json.load(sys.stdin) != observed: raise ValueError('approved directory identity changed')
        # Only documented candidate simple-cache shape. No recursive deletion.
        cache_fd = opened[-1]; parents = [cache_fd]; entries = []
        try:
            for name in sorted(os.listdir(cache_fd)):
                info = os.stat(name, dir_fd=cache_fd, follow_symlinks=False)
                if name == 'index-dir' and stat.S_ISDIR(info.st_mode):
                    fd = os.open(name, FLAGS, dir_fd=cache_fd); parents.append(fd)
                    index_identity = identity(os.fstat(fd))
                    if os.fstat(fd).st_uid != os.getuid() or os.fstat(fd).st_mode & 0o022: raise ValueError('ambiguous index ownership/access')
                    children = os.listdir(fd)
                    if any(child != 'the-real-index' for child in children): raise ValueError('unexpected cache index contents')
                    entries.extend((fd, child) for child in children)
                elif name == 'index' or re.fullmatch(r'[0-9a-f]{16}_[0-9]+', name): entries.append((cache_fd, name))
                else: raise ValueError('unexpected cache contents')
            if len(entries) > 10000: raise ValueError('bounded group size exceeded')
            for fd, name in entries:
                info = os.stat(name, dir_fd=fd, follow_symlinks=False)
                if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid(): raise ValueError('unexpected cache leaf')
            removed = 0
            for fd, name in entries:
                activity(str(bundle), root)
                # Reopen the path to detect a replaced group or ancestor between
                # operations, while deletion stays anchored to held descriptors.
                fresh = open_chain(root, cache)
                try:
                    if [identity(os.fstat(x)) for x in fresh] != observed['directories']: raise ValueError('group changed during cleanup')
                finally:
                    for x in fresh: os.close(x)
                if fd != cache_fd:
                    current_index = os.stat('index-dir', dir_fd=cache_fd, follow_symlinks=False)
                    if not stat.S_ISDIR(current_index.st_mode) or identity(current_index) != index_identity: raise ValueError('cache index directory changed')
                info = os.stat(name, dir_fd=fd, follow_symlinks=False)
                if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid(): raise ValueError('cache leaf changed')
                os.unlink(name, dir_fd=fd); removed += 1
                if settings.progress: print(json.dumps({'event':'removed', 'count':removed}), file=sys.stderr, flush=True)
                if settings.pace_ms: time.sleep(settings.pace_ms / 1000)
            print(json.dumps({'removed': removed, 'status': 'completed', 'residualFinalUnlinkRace': True}))
        except Exception as error:
            print(json.dumps({'removed': locals().get('removed', 0), 'status': 'stopped', 'reason': str(error)}))
            raise
        finally:
            for fd in parents[1:]: os.close(fd)
    finally:
        for fd in opened: os.close(fd)
if __name__ == '__main__':
    try: run()
    except Exception as error:
        print('Refused group operation: ' + str(error), file=sys.stderr); sys.exit(1)
