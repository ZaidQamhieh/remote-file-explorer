// Reproducible native config for the RFE Android build (CNG; android/ is never hand-edited).
//  - RFE_DEBUG_KEYSTORE=<path>: sign debug/rehearsal builds with an existing keystore, so an
//    RN build can be installed over the Flutter debug build (same package + signature).
//  - RFE_TEST_BUILD=1: make the release variant debuggable for `adb run-as` verification.
//    Never set for real releases.
const { withAppBuildGradle } = require('expo/config-plugins');

module.exports = function withRfeAndroid(config) {
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
};
