import { fileURLToPath } from 'node:url';
import { copyFileSync } from 'node:fs';
import { resolve } from 'node:path';

const page = (name) => fileURLToPath(new URL(name, import.meta.url));

const copyClassicAppScript = {
    name: 'copy-classic-app-script',
    writeBundle(outputOptions) {
        copyFileSync(page('app.js'), resolve(outputOptions.dir || 'dist', 'app.js'));
    },
};

export default {
    plugins: [copyClassicAppScript],
    build: {
        rollupOptions: {
            input: {
                app: page('index.html'),
                privacy: page('privacy.html'),
                terms: page('terms.html'),
                support: page('support.html'),
            },
        },
    },
};
