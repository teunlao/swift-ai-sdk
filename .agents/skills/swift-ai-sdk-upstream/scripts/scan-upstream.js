#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const P0 = new Set([
  "ai",
  "provider",
  "provider-utils",
  "openai",
  "openai-compatible",
  "anthropic",
  "google",
  "google-vertex",
  "gateway",
]);

const FRAMEWORK_PACKAGES = new Set(["angular", "react", "rsc", "svelte", "vue"]);
const TOOLING_PACKAGES = new Set([
  "codemod",
  "devtools",
  "harness",
  "harness-claude-code",
  "harness-codex",
  "harness-deepagents",
  "harness-opencode",
  "harness-pi",
  "langchain",
  "llamaindex",
  "mcp",
  "otel",
  "policy-opa",
  "sandbox-just-bash",
  "sandbox-vercel",
  "test-server",
  "tui",
  "valibot",
  "workflow",
  "workflow-harness",
]);

const PROVIDER_PACKAGES = new Set([
  "alibaba",
  "amazon-bedrock",
  "anthropic",
  "anthropic-aws",
  "assemblyai",
  "azure",
  "baseten",
  "black-forest-labs",
  "bytedance",
  "cerebras",
  "cohere",
  "deepgram",
  "deepinfra",
  "deepseek",
  "elevenlabs",
  "fal",
  "fireworks",
  "gateway",
  "gladia",
  "google",
  "google-vertex",
  "groq",
  "huggingface",
  "hume",
  "klingai",
  "lmnt",
  "luma",
  "mistral",
  "moonshotai",
  "open-responses",
  "openai",
  "openai-compatible",
  "perplexity",
  "prodia",
  "quiverai",
  "replicate",
  "revai",
  "togetherai",
  "vercel",
  "voyage",
  "xai",
]);

const TARGET_OVERRIDES = {
  ai: "SwiftAISDK",
  provider: "AISDKProvider",
  "provider-utils": "AISDKProviderUtils",
  alibaba: "AlibabaProvider",
  "amazon-bedrock": "AmazonBedrockProvider",
  anthropic: "AnthropicProvider",
  "anthropic-aws": "AnthropicAWSProvider",
  assemblyai: "AssemblyAIProvider",
  azure: "AzureProvider",
  baseten: "BasetenProvider",
  "black-forest-labs": "BlackForestLabsProvider",
  bytedance: "ByteDanceProvider",
  cerebras: "CerebrasProvider",
  cohere: "CohereProvider",
  deepgram: "DeepgramProvider",
  deepinfra: "DeepInfraProvider",
  deepseek: "DeepSeekProvider",
  elevenlabs: "ElevenLabsProvider",
  fal: "FalProvider",
  fireworks: "FireworksProvider",
  gateway: "GatewayProvider",
  gladia: "GladiaProvider",
  google: "GoogleProvider",
  "google-vertex": "GoogleVertexProvider",
  groq: "GroqProvider",
  huggingface: "HuggingFaceProvider",
  hume: "HumeProvider",
  klingai: "KlingAIProvider",
  lmnt: "LMNTProvider",
  luma: "LumaProvider",
  mistral: "MistralProvider",
  moonshotai: "MoonshotAIProvider",
  "open-responses": "OpenResponsesProvider",
  openai: "OpenAIProvider",
  "openai-compatible": "OpenAICompatibleProvider",
  perplexity: "PerplexityProvider",
  prodia: "ProdiaProvider",
  quiverai: "QuiverAIProvider",
  replicate: "ReplicateProvider",
  revai: "RevAIProvider",
  togetherai: "TogetherAIProvider",
  vercel: "VercelProvider",
  voyage: "VoyageProvider",
  xai: "XAIProvider",
};

function parseArgs(argv) {
  const args = {
    out: ".upstream/current",
    repoRoot: process.cwd(),
    upstreamRoot: "external/vercel-ai-sdk",
  };

  for (let index = 2; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--out") {
      args.out = argv[++index];
    } else if (arg === "--repo-root") {
      args.repoRoot = argv[++index];
    } else if (arg === "--upstream-root") {
      args.upstreamRoot = argv[++index];
    } else if (arg === "--help" || arg === "-h") {
      printHelp();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return args;
}

function printHelp() {
  console.log(`Usage: node scan-upstream.js [--out .upstream/current]

Generates local upstream parity catalogs:
  component-catalog.json
  component-catalog.md

The output directory should be under .upstream/ and stay gitignored.`);
}

function readText(filePath) {
  return fs.existsSync(filePath) ? fs.readFileSync(filePath, "utf8") : "";
}

function listDirectories(dirPath) {
  if (!fs.existsSync(dirPath)) {
    return [];
  }

  return fs
    .readdirSync(dirPath, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b));
}

function parsePinnedBaseline(repoRoot) {
  const upstreamFile = path.join(repoRoot, "upstream", "UPSTREAM.md");
  const text = readText(upstreamFile);
  return {
    commit: matchFirst(text, /Upstream commit:\s*`([0-9a-f]+)`/),
    subject: matchFirst(text, /Commit subject:\s*`([^`]+)`/),
    date: matchFirst(text, /Commit date:\s*`?([0-9-]+)`?/),
    refreshed: matchFirst(text, /Last refreshed \(local\):\s*`?([0-9-]+)`?/),
    path: fs.existsSync(upstreamFile) ? "upstream/UPSTREAM.md" : null,
  };
}

function matchFirst(text, regex) {
  const match = text.match(regex);
  return match ? match[1] : null;
}

function parseSwiftTargets(repoRoot) {
  const packageFile = path.join(repoRoot, "Package.swift");
  const text = readText(packageFile);
  const targets = new Set();
  const tests = new Set();
  const regex = /\.(target|executableTarget|testTarget)\s*\(\s*name:\s*"([^"]+)"/gs;
  let match;

  while ((match = regex.exec(text)) !== null) {
    if (match[1] === "testTarget") {
      tests.add(match[2]);
    } else {
      targets.add(match[2]);
    }
  }

  for (const sourceDir of listDirectories(path.join(repoRoot, "Sources"))) {
    targets.add(sourceDir);
  }

  for (const testDir of listDirectories(path.join(repoRoot, "Tests"))) {
    tests.add(testDir);
  }

  return {
    targets,
    tests,
  };
}

function expectedTargetForPackage(packageName) {
  if (TARGET_OVERRIDES[packageName]) {
    return TARGET_OVERRIDES[packageName];
  }

  return `${toPascalCase(packageName)}Provider`;
}

function toPascalCase(value) {
  return value
    .split(/[-_]/g)
    .filter(Boolean)
    .map((part) => {
      if (part.toLowerCase() === "ai") return "AI";
      return part.charAt(0).toUpperCase() + part.slice(1);
    })
    .join("");
}

function classifyArea(packageName, swiftTargets) {
  if (["ai", "provider", "provider-utils"].includes(packageName)) {
    return "core";
  }
  if (FRAMEWORK_PACKAGES.has(packageName)) {
    return "framework";
  }
  if (TOOLING_PACKAGES.has(packageName)) {
    return "tooling";
  }
  if (PROVIDER_PACKAGES.has(packageName)) {
    return "provider";
  }
  if (swiftTargets.length > 0 && swiftTargets.some((target) => target.endsWith("Provider"))) {
    return "provider";
  }
  return "unknown";
}

function priorityFor(packageName, area, swiftTargets) {
  if (P0.has(packageName)) {
    return "P0";
  }
  if (area === "provider") {
    return "P1";
  }
  if (area === "framework" || area === "unknown") {
    return "P2";
  }
  return "P3";
}

function providerTrackingSlug(packageName) {
  const aliases = {
    deepinfra: "deepinfra",
    deepseek: "deepseek",
    elevenlabs: "elevenlabs",
    huggingface: "huggingface",
    togetherai: "togetherai",
    bytedance: "bytedance",
    moonshotai: "moonshotai",
    assemblyai: "assemblyai",
    klingai: "klingai",
    revai: "revai",
    xai: "xai",
  };
  return aliases[packageName] || packageName;
}

function trackingFor(repoRoot, packageName, area) {
  if (area === "provider") {
    const providerPath = path.join(
      "upstream",
      "providers",
      `${providerTrackingSlug(packageName)}.md`,
    );
    const absolutePath = path.join(repoRoot, providerPath);
    return fs.existsSync(absolutePath) ? providerPath : null;
  }

  if (area === "core") {
    const progressPath = path.join("upstream", "PROGRESS.md");
    return fs.existsSync(path.join(repoRoot, progressPath)) ? progressPath : null;
  }

  return null;
}

function auditedCommitFor(repoRoot, trackingPath) {
  if (!trackingPath) {
    return null;
  }

  const text = readText(path.join(repoRoot, trackingPath));
  return (
    matchFirst(text, /Audited against upstream commit:\s*`([0-9a-f]+)`/) ||
    matchFirst(text, /refreshed upstream [`"]?([0-9a-f]{12,40})[`"]?/)
  );
}

function hasKnownGaps(repoRoot, trackingPath) {
  if (!trackingPath) {
    return true;
  }

  const text = readText(path.join(repoRoot, trackingPath));
  const gapSection = text.split(/## Known gaps \/ TODO/i)[1] || "";
  const beforeNextSection = gapSection.split(/\n## /)[0] || gapSection;
  if (/None known\./i.test(beforeNextSection) || /None known/i.test(beforeNextSection)) {
    return false;
  }
  return /\[ \]|TODO|gap|not implemented|missing/i.test(beforeNextSection);
}

function statusFor({ area, swiftTargets, trackingPath, auditedCommit, pinnedCommit, hasGaps }) {
  if (area === "framework" || area === "tooling") {
    return "n/a";
  }

  if (swiftTargets.length === 0) {
    return "unknown";
  }

  if (!trackingPath) {
    return "mapped";
  }

  if (!auditedCommit) {
    return "mapped";
  }

  if (auditedCommit && pinnedCommit && auditedCommit !== pinnedCommit) {
    return "stale";
  }

  if (auditedCommit && !hasGaps) {
    return "verified";
  }

  return "partial";
}

function freshnessFor({ area, auditedCommit, pinnedCommit }) {
  if (area === "framework" || area === "tooling") {
    return "n/a";
  }
  if (!auditedCommit) {
    return "unknown";
  }
  if (pinnedCommit && auditedCommit === pinnedCommit) {
    return "current";
  }
  return "stale";
}

function buildComponents({ repoRoot, upstreamRoot }) {
  const upstreamPackagesRoot = path.join(repoRoot, upstreamRoot, "packages");
  const packages = listDirectories(upstreamPackagesRoot);
  const pinned = parsePinnedBaseline(repoRoot);
  const swift = parseSwiftTargets(repoRoot);

  const components = packages.map((packageName) => {
    const expectedTarget = expectedTargetForPackage(packageName);
    const swiftTargets = swift.targets.has(expectedTarget) ? [expectedTarget] : [];
    const testTarget = `${expectedTarget}Tests`;
    const testTargets = swift.tests.has(testTarget) ? [testTarget] : [];
    const area = classifyArea(packageName, swiftTargets);
    const priority = priorityFor(packageName, area, swiftTargets);
    const trackingPath = trackingFor(repoRoot, packageName, area);
    const auditedCommit = auditedCommitFor(repoRoot, trackingPath);
    const hasGaps = hasKnownGaps(repoRoot, trackingPath);
    const status = statusFor({
      area,
      swiftTargets,
      trackingPath,
      auditedCommit,
      pinnedCommit: pinned.commit,
      hasGaps,
    });
    const freshness = freshnessFor({
      area,
      auditedCommit,
      pinnedCommit: pinned.commit,
    });

    return {
      name: packageName,
      area,
      priority,
      upstreamPath: `external/vercel-ai-sdk/packages/${packageName}`,
      swiftTargets,
      testTargets,
      trackingPath,
      auditedCommit,
      status,
      freshness,
      notes: notesFor({ area, swiftTargets, trackingPath }),
    };
  });

  components.sort((a, b) => {
    const priority = a.priority.localeCompare(b.priority);
    if (priority !== 0) return priority;
    return a.name.localeCompare(b.name);
  });

  return {
    generatedAt: new Date().toISOString(),
    pinned,
    components,
  };
}

function notesFor({ area, swiftTargets, trackingPath }) {
  if (area === "framework" || area === "tooling") {
    return "JS/upstream-only unless explicitly targeted";
  }
  if (swiftTargets.length === 0) {
    return area === "provider"
      ? "Upstream provider package; no Swift owner detected"
      : "No Swift owner detected";
  }
  if (!trackingPath) {
    return "Swift owner detected; no durable tracking page found";
  }
  return "Swift owner and tracking page detected";
}

function renderMarkdown(report) {
  const lines = [];
  lines.push("# Upstream Component Catalog");
  lines.push("");
  lines.push(`Generated: \`${report.generatedAt}\``);
  lines.push(`Pinned upstream: \`${report.pinned.commit || "unknown"}\``);
  if (report.pinned.subject) {
    lines.push(`Pinned subject: \`${escapeMarkdown(report.pinned.subject)}\``);
  }
  lines.push("");
  lines.push("| Component | Area | Priority | Status | Freshness | Swift owner | Tests | Tracking | Audited commit | Notes |");
  lines.push("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");

  for (const component of report.components) {
    lines.push(
      [
        component.name,
        component.area,
        component.priority,
        component.status,
        component.freshness,
        component.swiftTargets.join(", ") || "-",
        component.testTargets.join(", ") || "-",
        component.trackingPath || "-",
        component.auditedCommit || "-",
        component.notes,
      ]
        .map((value) => escapeTableCell(value))
        .join(" | ")
        .replace(/^/, "| ")
        .replace(/$/, " |"),
    );
  }

  lines.push("");
  lines.push("Status meanings live in `.agents/skills/swift-ai-sdk-upstream/references/component-taxonomy.md`.");
  return `${lines.join("\n")}\n`;
}

function escapeMarkdown(value) {
  return String(value).replace(/`/g, "\\`");
}

function escapeTableCell(value) {
  return String(value).replace(/\|/g, "\\|").replace(/\n/g, " ");
}

function writeReport(report, outputDir) {
  fs.mkdirSync(outputDir, { recursive: true });
  fs.writeFileSync(
    path.join(outputDir, "component-catalog.json"),
    `${JSON.stringify(report, null, 2)}\n`,
  );
  fs.writeFileSync(path.join(outputDir, "component-catalog.md"), renderMarkdown(report));
}

function main() {
  const args = parseArgs(process.argv);
  const repoRoot = path.resolve(args.repoRoot);
  const upstreamRoot = args.upstreamRoot;
  const outputDir = path.resolve(repoRoot, args.out);
  const report = buildComponents({ repoRoot, upstreamRoot });
  writeReport(report, outputDir);

  console.log(`Wrote ${path.relative(repoRoot, outputDir)}/component-catalog.json`);
  console.log(`Wrote ${path.relative(repoRoot, outputDir)}/component-catalog.md`);
  console.log(`Components: ${report.components.length}`);
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
