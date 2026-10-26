#!/usr/bin/env python3
"""Disposable public-CLI faults. Pacing widens detection interval, never a lease."""
import argparse, json, os, pathlib, select, signal, subprocess, tempfile, time
HELPER = pathlib.Path(__file__).with_name('cache-group.py')

def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--bundle', required=True); parser.add_argument('--output', required=True)
    args = parser.parse_args(); bundle = pathlib.Path(args.bundle).resolve()
    assert os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted', 'native faults hosted only'
    assert bundle.name == 'Google Chrome.app' and (bundle/'Contents/MacOS/Google Chrome').is_file()
    report = {'scope':'owned disposable synthetic cache only', 'pacing':'1000ms widens observation interval; not arbitrary race exclusion', 'checks':{}}
    def save():
        pathlib.Path(args.output).write_text(json.dumps(report, indent=2)+'\n')
    save()
    with tempfile.TemporaryDirectory(prefix='StillChromeProbe-', dir=os.environ['RUNNER_TEMP']) as temporary:
        root = pathlib.Path(temporary).resolve(); cache = root/'Default/Cache/Cache_Data'; cache.mkdir(parents=True)
        protected = root/'Default/Cookies'; protected.write_bytes(b'protected synthetic sentinel')
        cli = ['python3', str(HELPER), str(root), str(cache), str(bundle)]
        def populate():
            (cache/'0123456789abcdef_0').write_bytes(b'cache')
            index = cache/'index-dir'; index.mkdir(exist_ok=True); (index/'the-real-index').write_bytes(b'index')
        def observe():
            result = subprocess.run(cli+['observe'], text=True, capture_output=True, timeout=10)
            assert result.returncode == 0, result.stderr
            return result.stdout
        def partial(approval, change):
            process = subprocess.Popen(cli+['clean','--progress','--pace-ms','1000'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            process.stdin.write(approval); process.stdin.close(); process.stdin = None
            ready, _, _ = select.select([process.stderr], [], [], 10); assert ready, 'no bounded progress'
            event = json.loads(process.stderr.readline()); assert event == {'event':'removed','count':1}, event
            change()
            stdout, stderr = process.communicate(timeout=15); outcome = json.loads(stdout)
            assert process.returncode != 0 and outcome['status'] == 'stopped' and outcome['removed'] == 1, (outcome,stderr)
            assert protected.read_bytes() == b'protected synthetic sentinel'
            return outcome
        populate(); approval = observe()
        def swap():
            (cache/'index-dir').rename(cache/'retained-index')
            (cache/'index-dir').mkdir(); (cache/'index-dir/the-real-index').write_bytes(b'replacement protected')
        outcome = partial(approval, swap); assert 'index directory changed' in outcome['reason'], outcome
        assert (cache/'retained-index/the-real-index').read_bytes() == b'index'
        assert (cache/'index-dir/the-real-index').read_bytes() == b'replacement protected'
        report['checks']['indexSwap'] = outcome
        save()
        (cache/'retained-index/the-real-index').unlink(); (cache/'retained-index').rmdir()
        populate(); approval = observe(); cache.chmod(0o500)
        try:
            result = subprocess.run(cli+['clean'], input=approval, text=True, capture_output=True, timeout=10)
            assert result.returncode != 0 and json.loads(result.stdout)['removed'] == 0 and 'Permission denied' in result.stdout, (result.stdout,result.stderr)
            assert (cache/'0123456789abcdef_0').read_bytes() == b'cache'
            report['checks']['actualModeDenial'] = json.loads(result.stdout)
            save()
        finally: cache.chmod(0o700)
        approval = observe(); browser = None
        def launch():
            nonlocal browser
            browser = subprocess.Popen([str(bundle/'Contents/MacOS/Google Chrome'), '--user-data-dir='+str(root/'BrowserProfile'), '--no-first-run', '--no-default-browser-check', '--disable-background-networking', '--disable-component-update', 'about:blank'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            outcome = partial(approval, launch); assert 'activity observed' in outcome['reason'], outcome
            report['checks']['nativeBetweenWorkReopen'] = outcome
            save()
            deadline = time.monotonic() + 5
            while True:
                processes = subprocess.check_output(['/bin/ps','-axo','pid=,command='], text=True)
                report['checks']['actualHelperAssociation'] = any(str(bundle)+'/' in line and 'Helper' in line for line in processes.splitlines())
                if report['checks']['actualHelperAssociation'] or time.monotonic() >= deadline: break
                time.sleep(0.1)
            assert report['checks']['actualHelperAssociation'], 'no actual owned bundle helper observed'
            result = subprocess.run(cli+['observe'], text=True, capture_output=True, timeout=10)
            assert result.returncode != 0 and 'activity observed' in result.stderr
            report['checks']['activeBrowserRefused'] = True
            save()
        finally:
            if browser:
                browser.terminate()
                try: browser.wait(timeout=10)
                except subprocess.TimeoutExpired: raise AssertionError('owned browser did not exit gracefully')
                deadline = time.monotonic() + 10
                while str(bundle)+'/' in subprocess.check_output(['/bin/ps','-axo','command='], text=True):
                    if time.monotonic() >= deadline: raise AssertionError('owned helpers remained active')
                    time.sleep(0.1)
        assert protected.read_bytes() == b'protected synthetic sentinel'
    report['completed'] = True
    save()
    print(json.dumps(report))
if __name__ == '__main__': main()
