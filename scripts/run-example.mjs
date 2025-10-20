#!/usr/bin/env node
/**
 * Run Swift AI SDK examples
 * Usage: node scripts/run-example.mjs <example-name> [...args]
 */

import chalk from 'chalk';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const rootDir = resolve(__dirname, '..');
const examplesDir = resolve(rootDir, 'examples');

// Available examples
const EXAMPLES = {
  // Getting Started
  'basic-generation': 'BasicGeneration',
  'streaming': 'StreamingExample',
  'tools': 'ToolsExample',
  'cli': 'BasicCLI',

  // AI SDK Core
  'text-generation': 'BasicTextGeneration',
  'generate-object': 'GenerateObjectExample',
};

function printHelp() {
  console.log(chalk.bold('\n🚀 Swift AI SDK Examples Runner\n'));
  console.log('Usage: pnpm example <name> [...args]\n');
  console.log(chalk.bold('Available examples:\n'));

  console.log(chalk.cyan('Getting Started:'));
  console.log('  basic-generation  - Simple text generation');
  console.log('  streaming         - Streaming text output');
  console.log('  tools             - Using tools/function calling');
  console.log('  cli               - Command-line interface');

  console.log(chalk.cyan('\nAI SDK Core:'));
  console.log('  text-generation   - Core text generation features');
  console.log('  generate-object   - Structured data generation');

  console.log(chalk.yellow('\nExamples:\n'));
  console.log('  pnpm example basic-generation');
  console.log('  pnpm example streaming');
  console.log('  pnpm example cli "Write a haiku"');
  console.log();
}

async function runExample(exampleKey, args = []) {
  const exampleName = EXAMPLES[exampleKey];

  if (!exampleName) {
    console.error(chalk.red(`❌ Unknown example: ${exampleKey}\n`));
    printHelp();
    process.exit(1);
  }

  // Check .env file
  const envPath = resolve(examplesDir, '.env');
  if (!existsSync(envPath)) {
    console.log(chalk.yellow('⚠️  .env file not found'));
    console.log(chalk.gray('Copy .env.example to .env and add your API keys:'));
    console.log(chalk.gray('  cd examples && cp .env.example .env\n'));
  }

  console.log(chalk.bold.green(`\n🔨 Building ${exampleName}...\n`));

  // Build the example
  const buildProcess = spawn('swift', ['build', '--product', exampleName], {
    cwd: examplesDir,
    stdio: 'inherit',
  });

  await new Promise((resolve, reject) => {
    buildProcess.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(`Build failed with code ${code}`));
      } else {
        resolve();
      }
    });
  });

  console.log(chalk.bold.green(`\n▶️  Running ${exampleName}...\n`));
  console.log(chalk.gray('━'.repeat(80)));
  console.log();

  // Run the example
  const runProcess = spawn('swift', ['run', exampleName, ...args], {
    cwd: examplesDir,
    stdio: 'inherit',
  });

  return new Promise((resolve, reject) => {
    runProcess.on('close', (code) => {
      console.log();
      console.log(chalk.gray('━'.repeat(80)));
      if (code !== 0) {
        console.log(chalk.red(`\n❌ Example failed with code ${code}`));
        reject(new Error(`Example failed with code ${code}`));
      } else {
        console.log(chalk.green(`\n✅ Example completed successfully`));
        resolve();
      }
    });
  });
}

// Main
const [exampleKey, ...args] = process.argv.slice(2);

if (!exampleKey || exampleKey === '--help' || exampleKey === '-h') {
  printHelp();
  process.exit(0);
}

runExample(exampleKey, args).catch((error) => {
  console.error(chalk.red(`\n❌ Error: ${error.message}`));
  process.exit(1);
});
