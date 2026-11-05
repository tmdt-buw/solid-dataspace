"""Check local deployment isolation without starting services or reading .env."""
from pathlib import Path
import json
import subprocess

root = Path(__file__).resolve().parents[1]
base = ['docker', 'compose', '--env-file', '.env.local.example', '-f', 'docker-compose.yml', '-f', 'docker-compose.local.yml']
for development in [False, True]:
    command = base + (['-f', 'docker-compose.dev.yml'] if development else [])
    result = subprocess.run(command + ['--profile', 'plasma', '--profile', 'search', '--profile', 'node-red', 'config', '--format', 'json'], cwd=root, capture_output=True, text=True, check=True)
    config = json.loads(result.stdout)
    services = config['services']
    worker = services['solid-data-connection-sync-worker']
    assert config['name'] == 'solid-dataspace-local'
    assert config['networks']['solid-dataspace']['name'] == 'solid-dataspace-local_solid-dataspace'
    assert services['caddy']['ports'][0]['host_ip'] == '127.0.0.1'
    assert not services['caddy'].get('container_name')
    assert set(services['caddy']['depends_on']) == {'access-gateway'}
    assert worker['environment']['WORKER_CONNECTION_NAMESPACE'] == 'test'
    assert worker['environment']['STATISTICS_ENABLED'] == 'false'
    assert worker['environment']['ENVIRONMENTAL_SCENARIO_ENABLED'] == 'false'
    assert worker['environment']['PUBLIC_CACHE_REGISTRIES_JSON'] == '[]'
    assert worker['environment']['WORKER_WEBID'] == ''
    assert worker['environment']['WORKER_CLIENT_SECRET'] == ''
    assert services['semantic-data-catalog-backend']['profiles'] == ['search']
    assert services['plasma-sms']['profiles'] == ['plasma']
    assert services['node-red']['profiles'] == ['node-red']
    assert all(not service.get('build') for service in services.values())
    assert all(not service.get('ports') for name, service in services.items() if name != 'caddy')
    for name in ['semantic-data-catalog-frontend', 'solid-data-manager', 'solid-health-questionnaire'] + ([] if development else ['city-tours']):
        assert services[name]['image'].startswith('son1i/')
        assert not services[name].get('command')
        assert not services[name].get('volumes')
    for volume in config['volumes'].values():
        assert volume['name'].startswith('solid-dataspace-local_')
        assert not volume.get('external')
    if development:
        manager = services['solid-dataspace-manager']
        assert manager['environment']['LOCAL_PACKAGE_WATCH_DIRS'] == '/solid-health-app/dist;/city-tours/dist'
        assert manager['depends_on']['solid-health-app']['condition'] == 'service_healthy'
        assert manager['depends_on']['city-tours']['condition'] == 'service_healthy'
        tours = services['city-tours']
        assert tours['image'] == 'node:22-alpine'
        assert tours['depends_on']['local-catalog-package']['condition'] == 'service_completed_successfully'
        assert tours['environment']['LOCAL_NPM_PACKAGE_DIR'] == '/packages'
        assert services['local-catalog-package']['network_mode'] == 'none'
        assert 'NPM_TOKEN' not in tours['environment']
        assert any(v['target'] == '/city-tours/dist' and v['read_only'] for v in manager['volumes'])
        assert any(v['target'] == '/app' and v['source'].endswith('/solid-tours') for v in tours['volumes'])
        assert 'semantic-data-catalog-frontend' not in manager['depends_on']
        assert 'NPM_TOKEN' not in manager['environment']
        assert all(volume['type'] == 'volume' for volume in manager['volumes'])
        assert not any(volume['target'] == '/app/access.mjs' for volume in services['access-gateway']['volumes'])
    print(('Development' if development else 'Images') + ': local isolation and dependency checks passed')
