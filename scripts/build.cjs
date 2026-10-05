'use strict';
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),out=path.join(root,'public-build');
fs.rmSync(out,{recursive:true,force:true});fs.mkdirSync(out,{recursive:true});
for(const file of ['index.html','app.js','workspace.js','presence.js','season.js','calendar-utils.js','intelligence.js','notifications.js','match-intelligence.js','cloud-config.js','content-protection.js','styles.css','manifest.webmanifest','service-worker.js','app-icon.svg','robots.txt'])fs.copyFileSync(path.join(root,file),path.join(out,file));
fs.cpSync(path.join(root,'assets'),path.join(out,'assets'),{recursive:true});
fs.cpSync(path.join(root,'.well-known'),path.join(out,'.well-known'),{recursive:true});
require('esbuild').buildSync({entryPoints:[path.join(root,'client/bot-protection.js')],bundle:true,minify:true,platform:'browser',format:'iife',target:['es2022'],outfile:path.join(out,'bot-protection.js')});
console.log('Built public files only; database imports, migrations, tests and server source excluded.');
