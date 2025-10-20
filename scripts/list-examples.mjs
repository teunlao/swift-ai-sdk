#!/usr/bin/env node
/**
 * List all available examples with descriptions
 * Usage: node scripts/list-examples.mjs
 */

import chalk from 'chalk';

const examples = [
  {
    category: 'Getting Started',
    items: [
      {
        key: 'basic-generation',
        name: 'BasicGeneration',
        description: 'Simple text generation with OpenAI',
        docs: 'getting-started/ios-macos-quickstart.mdx',
      },
      {
        key: 'streaming',
        name: 'StreamingExample',
        description: 'Stream text generation for real-time output',
        docs: 'getting-started/ios-macos-quickstart.mdx',
      },
      {
        key: 'tools',
        name: 'ToolsExample',
        description: 'Use tools/function calling to extend capabilities',
        docs: 'getting-started/ios-macos-quickstart.mdx',
      },
      {
        key: 'cli',
        name: 'BasicCLI',
        description: 'Command-line interface example',
        docs: 'getting-started/cli-quickstart.mdx',
      },
    ],
  },
  {
    category: 'AI SDK Core',
    items: [
      {
        key: 'text-generation',
        name: 'BasicTextGeneration',
        description: 'Core text generation with system prompts and settings',
        docs: 'ai-sdk-core/generating-text.mdx',
      },
      {
        key: 'generate-object',
        name: 'GenerateObjectExample',
        description: 'Generate structured, validated JSON objects',
        docs: 'ai-sdk-core/generating-structured-data.mdx',
      },
    ],
  },
];

console.log(chalk.bold('\n📚 Swift AI SDK Examples\n'));

for (const category of examples) {
  console.log(chalk.bold.cyan(`${category.category}:`));
  console.log();

  for (const example of category.items) {
    console.log(`  ${chalk.green(example.key.padEnd(20))} ${example.description}`);
    console.log(`  ${chalk.gray('→ ' + example.name)}`);
    console.log(`  ${chalk.gray('📄 apps/docs/src/content/docs/' + example.docs)}`);
    console.log();
  }
}

console.log(chalk.bold('Usage:\n'));
console.log(`  ${chalk.yellow('pnpm example <name>')}`);
console.log(`  ${chalk.gray('Example: pnpm example basic-generation')}\n`);
