#!/usr/bin/env node
/**
 * Test all Swift AI SDK examples
 * Usage: node scripts/test-examples.mjs
 */

import chalk from 'chalk';
import { spawn } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const rootDir = resolve(__dirname, '..');
const examplesDir = resolve(rootDir, 'examples');

async function runTests() {
  console.log(chalk.bold.green('\n🧪 Running Examples Tests...\n'));

  const testProcess = spawn('swift', ['test'], {
    cwd: examplesDir,
    stdio: 'inherit',
  });

  return new Promise((resolve, reject) => {
    testProcess.on('close', (code) => {
      if (code !== 0) {
        console.log(chalk.red(`\n❌ Tests failed with code ${code}`));
        reject(new Error(`Tests failed with code ${code}`));
      } else {
        console.log(chalk.green(`\n✅ All tests passed`));
        resolve();
      }
    });
  });
}

async function buildAll() {
  console.log(chalk.bold.green('\n🔨 Building all examples...\n'));

  const buildProcess = spawn('swift', ['build'], {
    cwd: examplesDir,
    stdio: 'inherit',
  });

  return new Promise((resolve, reject) => {
    buildProcess.on('close', (code) => {
      if (code !== 0) {
        console.log(chalk.red(`\n❌ Build failed with code ${code}`));
        reject(new Error(`Build failed with code ${code}`));
      } else {
        console.log(chalk.green(`\n✅ Build successful`));
        resolve();
      }
    });
  });
}

// Main
const command = process.argv[2] || 'test';

if (command === 'build') {
  buildAll().catch((error) => {
    console.error(chalk.red(`\n❌ Error: ${error.message}`));
    process.exit(1);
  });
} else if (command === 'test') {
  runTests().catch((error) => {
    console.error(chalk.red(`\n❌ Error: ${error.message}`));
    process.exit(1);
  });
} else {
  console.log(chalk.yellow('Usage: pnpm test:examples [build|test]'));
  process.exit(1);
}
