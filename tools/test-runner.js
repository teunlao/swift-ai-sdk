#!/usr/bin/env node

/**
 * Flexible Swift Test Runner
 *
 * Allows running tests with various filtering strategies:
 * - Exclude specific tests (blacklist)
 * - Include only specific tests (whitelist)
 * - Run last/first N tests
 * - Run specific test suites
 */

const { execSync, spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

// Default config path
const DEFAULT_CONFIG = path.join(__dirname, 'test-runner.config.json');

/**
 * Get all available tests
 */
function getAllTests() {
    try {
        const output = execSync('swift test list', {
            encoding: 'utf8',
            stdio: ['pipe', 'pipe', 'ignore'] // Suppress stderr (build output)
        });

        return output
            .split('\n')
            .filter(line => line.trim() && !line.includes('Building'))
            .map(line => line.trim());
    } catch (error) {
        console.error('Failed to get test list:', error.message);
        process.exit(1);
    }
}

/**
 * Load config file
 */
function loadConfig(configPath) {
    try {
        const content = fs.readFileSync(configPath, 'utf8');
        return JSON.parse(content);
    } catch (error) {
        console.error(`Failed to load config from ${configPath}:`, error.message);
        process.exit(1);
    }
}

/**
 * Match test name against pattern (supports wildcards)
 */
function matchPattern(testName, pattern) {
    // Convert wildcard pattern to regex
    const regexPattern = pattern
        .replace(/\./g, '\\.')
        .replace(/\*/g, '.*')
        .replace(/\?/g, '.');

    const regex = new RegExp(`^${regexPattern}$`);
    return regex.test(testName);
}

/**
 * Filter tests based on config
 */
function filterTests(allTests, config) {
    const { mode, count } = config;

    // Smart field selection based on mode
    // Supports: exclude/include fields (mode-specific) or patterns/tests (universal)
    let patterns = [];
    if (mode === 'exclude') {
        patterns = config.exclude || config.patterns || config.tests || [];
    } else if (mode === 'include') {
        patterns = config.include || config.patterns || config.tests || [];
    } else {
        patterns = config.patterns || config.tests || [];
    }

    switch (mode) {
        case 'all':
            return allTests;

        case 'exclude': {
            // Run all EXCEPT listed tests
            return allTests.filter(test =>
                !patterns.some(pattern => matchPattern(test, pattern))
            );
        }

        case 'include': {
            // Run ONLY listed tests
            // Return patterns directly if they contain wildcards
            // This allows filtering by suite instead of individual tests
            const hasWildcards = patterns.some(p => p.includes('*'));
            if (hasWildcards) {
                // Return patterns themselves for suite-level filtering
                return patterns.map(p => p.replace('/*', ''));
            }

            return allTests.filter(test =>
                patterns.some(pattern => matchPattern(test, pattern))
            );
        }

        case 'last': {
            // Run last N tests
            const n = count || 20;
            return allTests.slice(-n);
        }

        case 'first': {
            // Run first N tests
            const n = count || 20;
            return allTests.slice(0, n);
        }

        default:
            console.error(`Unknown mode: ${mode}`);
            process.exit(1);
    }
}

/**
 * Build swift test command with filters
 */
function buildCommand(tests, _allTests, config) {
    const { parallel = false, verbose = false, mode } = config;

    let cmd = 'swift test';
    let flags = '';

    // Build flags separately to add at the end
    if (parallel) {
        flags += ' --parallel';
    }
    if (verbose) {
        flags += ' --verbose';
    }

    // For exclude mode with many tests, it's more efficient to run all
    // Swift doesn't support excluding tests via CLI, only including
    if (mode === 'exclude' && tests.length > 100) {
        console.warn('\n⚠️  Warning: Excluding tests via CLI is inefficient.');
        console.warn(`   Running ALL tests instead of filtering ${tests.length} tests.`);
        console.warn('   Use mode="include" for better performance with large sets.\n');
        return cmd + flags;
    }

    // Add filter for each test
    if (tests.length > 0 && tests.length <= 100) {
        // For reasonable sets, filter individual tests
        tests.forEach(test => {
            cmd += ` --filter "${test}"`;
        });
    } else if (tests.length > 100) {
        // For large sets, group by test suites
        const suites = new Set();
        tests.forEach(test => {
            const [suite] = test.split('/');
            suites.add(suite);
        });

        // If we can reduce to reasonable number of suites
        if (suites.size <= 50) {
            suites.forEach(suite => {
                cmd += ` --filter "${suite}"`;
            });
        } else {
            console.warn('\n⚠️  Warning: Too many test suites to filter efficiently.');
            console.warn(`   Running ALL tests instead.\n`);
            // Just run all tests
        }
    }

    return cmd + flags;
}

/**
 * Cleanup zombie test processes before running tests
 */
function cleanupZombieProcesses() {
    try {
        // Kill all swiftpm-testing-helper zombie processes
        execSync('pkill -9 -f "swiftpm-testing-helper"', {
            stdio: 'ignore'
        });
        console.log('🧹 Cleaned up zombie test processes\n');
    } catch (error) {
        // Ignore errors if no processes found
    }
}

/**
 * Run tests and stream output
 */
function runTests(command) {
    // Always cleanup zombie processes first
    cleanupZombieProcesses();

    console.log(`🧪 Running: ${command}\n`);

    // Parse command into array of arguments
    // Split on spaces but respect quotes
    const args = command.match(/(?:[^\s"]+|"[^"]*")+/g).map(arg => {
        // Remove surrounding quotes
        if (arg.startsWith('"') && arg.endsWith('"')) {
            return arg.slice(1, -1);
        }
        return arg;
    });

    // First arg is 'swift', second is 'test'
    const swiftArgs = args.slice(1); // Remove 'swift'

    const child = spawn('swift', swiftArgs, {
        stdio: 'inherit',
        shell: false
    });

    child.on('exit', (code) => {
        process.exit(code);
    });
}

/**
 * Print summary
 */
function printSummary(allTests, filteredTests, config) {
    console.log('📊 Test Runner Summary');
    console.log('━'.repeat(50));
    console.log(`Mode:           ${config.mode}`);
    console.log(`Total tests:    ${allTests.length}`);
    console.log(`Selected tests: ${filteredTests.length}`);
    console.log(`Excluded:       ${allTests.length - filteredTests.length}`);
    console.log(`Parallel:       ${config.parallel ? 'Yes' : 'No'}`);

    if (config.mode === 'exclude' || config.mode === 'include') {
        // Get patterns based on mode
        let patterns = [];
        if (config.mode === 'exclude') {
            patterns = config.exclude || config.patterns || config.tests || [];
        } else if (config.mode === 'include') {
            patterns = config.include || config.patterns || config.tests || [];
        }
        console.log(`Patterns:       ${patterns.length}`);
        patterns.forEach(p => console.log(`  - ${p}`));
    }

    console.log('━'.repeat(50));
}

/**
 * Generate default config
 */
function generateConfig() {
    const defaultConfig = {
        "$schema": "test-runner.schema.json",
        "mode": "exclude",
        "tests": [
            "SwiftAISDKTests.HandleUIMessageStreamFinishTests/*",
            "SwiftAISDKTests.ReadUIMessageStreamTests/*"
        ],
        "parallel": true,
        "verbose": false,
        "count": 20
    };

    const configPath = DEFAULT_CONFIG;
    fs.writeFileSync(configPath, JSON.stringify(defaultConfig, null, 2));
    console.log(`✅ Created default config at: ${configPath}`);
}

/**
 * List all tests
 */
function listTests() {
    const tests = getAllTests();
    console.log(`📋 Found ${tests.length} tests:\n`);
    tests.forEach((test, i) => {
        console.log(`${String(i + 1).padStart(4)}. ${test}`);
    });
}

/**
 * Main
 */
function main() {
    const args = process.argv.slice(2);

    // Handle commands
    if (args.includes('--init')) {
        generateConfig();
        return;
    }

    if (args.includes('--list')) {
        listTests();
        return;
    }

    if (args.includes('--help') || args.includes('-h')) {
        console.log(`
Swift Test Runner - Flexible test execution tool

Usage:
  node test-runner.js [options]

Options:
  --config <path>   Path to config file (default: test-runner.config.json)
  --init            Generate default config file
  --list            List all available tests
  --dry-run         Show what would be run without executing
  --help, -h        Show this help

Config modes:
  all      - Run all tests
  exclude  - Run all tests EXCEPT those matching patterns
  include  - Run ONLY tests matching patterns
  last     - Run last N tests
  first    - Run first N tests

Example config:
  {
    "mode": "exclude",
    "tests": [
      "SwiftAISDKTests.CreateUIMessageStreamTests/*",
      "*.HandleUIMessageStreamFinishTests/*"
    ],
    "parallel": true,
    "verbose": false
  }
        `);
        return;
    }

    // Get config path
    const configIndex = args.indexOf('--config');
    const configPath = configIndex !== -1
        ? args[configIndex + 1]
        : DEFAULT_CONFIG;

    // Check if config exists
    if (!fs.existsSync(configPath)) {
        console.error(`Config not found: ${configPath}`);
        console.log('Run with --init to create default config');
        process.exit(1);
    }

    // Load config and get tests
    const config = loadConfig(configPath);
    const allTests = getAllTests();
    const filteredTests = filterTests(allTests, config);

    // Print summary
    printSummary(allTests, filteredTests, config);

    // Dry run
    if (args.includes('--dry-run')) {
        const command = buildCommand(filteredTests, allTests, config);
        console.log(`\n🧪 Command: ${command}\n`);
        console.log('🔍 Tests to run:');
        filteredTests.slice(0, 20).forEach(test => console.log(`  ${test}`));
        if (filteredTests.length > 20) {
            console.log(`  ... and ${filteredTests.length - 20} more`);
        }
        return;
    }

    // Build and run command
    const command = buildCommand(filteredTests, allTests, config);
    runTests(command);
}

main();
