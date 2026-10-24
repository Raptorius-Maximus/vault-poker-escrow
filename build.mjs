import { build } from 'esbuild';

// Two independently named outputs from one outdir, via esbuild's { in, out }
// entry-point form (esbuild >=0.14). V1's bundle keeps its exact name --
// public/bundle.js, which public/index.html loads -- so nothing about V1
// changes (D11/D13). V2's app builds alongside it as public/bundle-v2.js,
// which public/v2.html loads. A third entry (bundle-v2-recover) is added by
// task 7 for the recovery page.
await build({
  entryPoints: [
    { in: 'src/main.js', out: 'bundle' },
    { in: 'src/mainV2.js', out: 'bundle-v2' },
    { in: 'src/mainV2Recover.js', out: 'bundle-v2-recover' },
  ],
  bundle: true,
  format: 'esm',
  outdir: 'public',
  target: 'es2020',
});

console.log('built public/bundle.js, public/bundle-v2.js, public/bundle-v2-recover.js');
