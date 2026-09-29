// Reproducible native config for the RFE Android build (CNG; android/ is never hand-edited).
//  - RFE_DEBUG_KEYSTORE=<path>: sign debug/rehearsal builds with an existing keystore, so an
//    RN build can be installed over the Flutter debug build (same package + signature).
//  - RFE_TEST_BUILD=1: make the release variant debuggable for `adb run-as` verification.
//    Never set for real releases.
//  - Network security config identical to the Flutter app's: cleartext is refused app-wide except
//    to 127.0.0.1, which the media loopback proxy needs (agent traffic stays pinned HTTPS).
const fs = require('fs');
const path = require('path');
const { withAndroidManifest, withAppBuildGradle, withDangerousMod } = require('expo/config-plugins');

const NETWORK_SECURITY_CONFIG = `<?xml version="1.0" encoding="utf-8"?>
<!-- Cleartext only to loopback, for the media proxy (MediaProxy.kt). Every agent request stays on
     the TLS-pinned HTTPS path, which this config does not touch. -->
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
    </domain-config>
    <base-config cleartextTrafficPermitted="false" />
</network-security-config>
`;

function withSigningAndDebuggable(config) {
  return withAppBuildGradle(config, (cfg) => {
    let g = cfg.modResults.contents;
    const ks = process.env.RFE_DEBUG_KEYSTORE;
    if (ks) {
      g = g.replace(/storeFile file\('debug\.keystore'\)/, `storeFile file(${JSON.stringify(ks)})`);
    }
    if (process.env.RFE_TEST_BUILD === '1' && !g.includes('debuggable true')) {
      g = g.replace(/(\n\s*release \{\n)/, '$1            debuggable true\n');
    }
    cfg.modResults.contents = g;
    return cfg;
  });
}

function withNetworkSecurityConfig(config) {
  config = withDangerousMod(config, [
    'android',
    (cfg) => {
      const dir = path.join(cfg.modRequest.platformProjectRoot, 'app/src/main/res/xml');
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, 'network_security_config.xml'), NETWORK_SECURITY_CONFIG);
      return cfg;
    },
  ]);
  return withAndroidManifest(config, (cfg) => {
    const app = cfg.modResults.manifest.application[0];
    app.$['android:networkSecurityConfig'] = '@xml/network_security_config';
    // The config above is the single source of truth for cleartext.
    delete app.$['android:usesCleartextTraffic'];
    return cfg;
  });
}

// FileProvider for handing single files to other apps (open with / share). Only cache/share and cache/open are exposed.
const FILE_PATHS = `<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="share" path="share/" />
    <cache-path name="open" path="open/" />
</paths>
`;

function withFileProvider(config) {
  config = withDangerousMod(config, [
    'android',
    (cfg) => {
      const dir = path.join(cfg.modRequest.platformProjectRoot, 'app/src/main/res/xml');
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, 'rfe_file_paths.xml'), FILE_PATHS);
      return cfg;
    },
  ]);
  return withAndroidManifest(config, (cfg) => {
    const app = cfg.modResults.manifest.application[0];
    app.provider = (app.provider ?? []).filter((p) => p.$['android:authorities'] !== '${applicationId}.rfe.fileprovider');
    app.provider.push({
      $: {
        'android:name': 'androidx.core.content.FileProvider',
        'android:authorities': '${applicationId}.rfe.fileprovider',
        'android:exported': 'false',
        'android:grantUriPermissions': 'true',
      },
      'meta-data': [{ $: { 'android:name': 'android.support.FILE_PROVIDER_PATHS', 'android:resource': '@xml/rfe_file_paths' } }],
    });
    return cfg;
  });
}

module.exports = function withRfeAndroid(config) {
  return withFileProvider(withNetworkSecurityConfig(withSigningAndDebuggable(config)));
};
