#!/usr/bin/env python3
"""Experimental exact-leaf operation on a newly created disposable probe tree only.
Not an application executor: external reopen/leaf-swap races are unqualified.
No recursive deletion, no links, no unmanifested targets, no nonregular leaves.
"""
import json, os, pathlib, stat, sys

def run():
    root, cache = map(pathlib.Path, sys.argv[1:])
    if not root.is_absolute() or root.name[:17] != 'StillChromeProbe-' or root != root.resolve():
        raise ValueError('disposable canonical root required')
    if not cache.is_absolute() or cache.name != 'Cache_Data':
        raise ValueError('explicit Cache_Data boundary required')
    relative_cache = cache.relative_to(root)
    manifest = json.load(sys.stdin)
    if not manifest or len(manifest) > 10000:
        raise ValueError('nonempty bounded exact-leaf manifest required')
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    root_fd = os.open(root, flags)
    cache_fd = os.dup(root_fd)
    try:
        for component in relative_cache.parts:
            if component in ('', '.', '..'): raise ValueError('invalid cache component')
            next_fd = os.open(component, flags, dir_fd=cache_fd)
            os.close(cache_fd); cache_fd = next_fd
        targets = []
        for item in manifest:
            path = pathlib.Path(item['path']).relative_to(cache)
            if path.is_absolute() or any(p in ('', '.', '..') for p in path.parts):
                raise ValueError('invalid exact leaf')
            parent_fd = os.dup(cache_fd)
            try:
                for component in path.parts[:-1]:
                    next_fd = os.open(component, flags, dir_fd=parent_fd)
                    os.close(parent_fd); parent_fd = next_fd
                info = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)
                if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                    raise ValueError('nonregular or multiply linked leaf')
                if (info.st_dev, info.st_ino, info.st_size) != (item['dev'], item['ino'], item['size']):
                    raise ValueError('leaf identity changed')
                if abs(info.st_mtime_ns / 1e6 - item['mtimeMs']) > 0.01:
                    raise ValueError('leaf modified')
                targets.append((parent_fd, path.name, info))
                parent_fd = None
            finally:
                if parent_fd is not None: os.close(parent_fd)
        try:
            for parent_fd, name, expected in targets:
                current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
                if (current.st_dev, current.st_ino, current.st_size, current.st_mtime_ns) != (expected.st_dev, expected.st_ino, expected.st_size, expected.st_mtime_ns):
                    raise ValueError('leaf changed before removal')
                os.unlink(name, dir_fd=parent_fd)
        finally:
            for parent_fd, _, _ in targets: os.close(parent_fd)
    finally:
        os.close(cache_fd); os.close(root_fd)

if __name__ == '__main__':
    try: run()
    except Exception as error:
        print('Refused owned-cache operation: ' + str(error), file=sys.stderr)
        sys.exit(1)
