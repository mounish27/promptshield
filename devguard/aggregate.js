#!/usr/bin/env node
// PromptShield GitHub Actions aggregator — writes data/usage.json for GitHub Pages
const https = require("https"), fs = require("fs");
const GATEWAY = process.env.GATEWAY_URL || "";
const KEY     = process.env.DEVGUARD_ADMIN_KEY || "";
const OUT     = "usage-output.json";

function get(url) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const isHttps = u.protocol === "https:";
    const lib = isHttps ? require("https") : require("http");
    const req = lib.get({
      hostname:u.hostname, port:u.port||(isHttps?443:80), path:u.pathname,
      headers:{"Authorization":`Bearer ${KEY}`}
    }, res => {
      let d=""; res.on("data",c=>d+=c);
      res.on("end",()=>{try{resolve(JSON.parse(d))}catch{resolve({})}});
    });
    req.on("error",reject);
    req.setTimeout(8000,()=>{req.destroy();reject(new Error("timeout"))});
  });
}

(async () => {
  let data = {};
  if (GATEWAY && KEY) {
    try { data = await get(`${GATEWAY}/api/v1/admin/usage-summary`); }
    catch (e) { console.warn("Gateway unreachable:", e.message); }
  }
  const out = {
    generatedAt: new Date().toISOString(),
    budgetTotal: 200,
    summary: data.summary || { spentMtd:0, tokensToday:0, requestsToday:0, blocksToday:0, warnsToday:0 },
    developers: data.developers || [],
    dailyCosts: data.dailyCosts || [],
    recentEvents: (data.recentEvents || []).slice(0, 50),
    alerts: [],
  };
  const pct = (out.summary.spentMtd / 200) * 100;
  if (pct >= 90) out.alerts.push({ level:"critical", message:`Budget ${pct.toFixed(0)}% used` });
  else if (pct >= 75) out.alerts.push({ level:"warning", message:`Budget ${pct.toFixed(0)}% used` });
  fs.writeFileSync(OUT, JSON.stringify(out, null, 2));
  console.log(`✓ Written ${OUT} — $${out.summary.spentMtd.toFixed(2)} spent MTD`);
  if (pct >= 95) process.exit(1);
})().catch(e => {
  fs.writeFileSync(OUT, JSON.stringify({generatedAt:new Date().toISOString(),error:e.message,developers:[],recentEvents:[],dailyCosts:[],summary:{spentMtd:0,tokensToday:0,requestsToday:0,blocksToday:0,warnsToday:0}},null,2));
});
