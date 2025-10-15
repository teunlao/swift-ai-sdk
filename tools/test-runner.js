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
const DEFAULT_CONFIG = path.join(__dirname, 'test-runner.default.config.json');

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
        console.log('🧹 Cleaned up zombie test processes');
    } catch (error) {
        // Ignore errors if no processes found (no zombies = good)
    }
}

/**
 * Execute test command and return structured result
 * @returns Promise<{ status: 'passed'|'failed'|'timeout', duration: number, failedTests: Array, lastOutput: string[], totalTests: number }>
 */
function executeTest(command, timeoutMs = 10000) {
    return new Promise((resolve) => {
        const startTime = Date.now();

        // Parse command into array of arguments
        const args = command.match(/(?:[^\s"]+|"[^"]*")+/g).map(arg => {
            if (arg.startsWith('"') && arg.endsWith('"')) {
                return arg.slice(1, -1);
            }
            return arg;
        });

        const swiftArgs = args.slice(1); // Remove 'swift'

        const child = spawn('swift', swiftArgs, {
            stdio: ['pipe', 'pipe', 'pipe'],
            shell: false
        });

        let output = '';
        let failedTests = [];
        let currentFailure = null;
        let testCount = 0;
        let timedOut = false;

        const timer = setTimeout(() => {
            timedOut = true;
            child.kill('SIGTERM');
            setTimeout(() => child.kill('SIGKILL'), 1000);
        }, timeoutMs);

        child.stdout.on('data', (data) => {
            const lines = data.toString().split('\n');

            for (const line of lines) {
                output += line + '\n';

                if (line.includes('Test run with')) {
                    const match = line.match(/Test run with (\d+) tests/);
                    if (match) testCount = parseInt(match[1]);
                }

                if (line.includes('✘ Test ') && line.includes('failed')) {
                    const testMatch = line.match(/✘ Test "([^"]+)"/);
                    if (testMatch) {
                        currentFailure = {
                            name: testMatch[1],
                            details: [line]
                        };
                    }
                }

                if (line.includes('recorded an issue')) {
                    if (currentFailure) {
                        currentFailure.details.push(line);
                    } else {
                        currentFailure = {
                            name: 'Unknown test',
                            details: [line]
                        };
                    }
                }

                if (currentFailure && (line.includes('✔ Test') || line.includes('✘ Suite'))) {
                    failedTests.push(currentFailure);
                    currentFailure = null;
                }
            }
        });

        child.stderr.on('data', () => {
            // Ignore build output
        });

        child.on('exit', () => {
            clearTimeout(timer);
            const duration = Date.now() - startTime;
            const lines = output.split('\n').filter(l => l.trim());
            const lastOutput = lines.slice(-30);

            if (timedOut) {
                resolve({
                    status: 'timeout',
                    duration,
                    failedTests,
                    lastOutput,
                    totalTests: testCount
                });
                return;
            }

            const summaryMatch = output.match(/Test run with (\d+) tests (passed|failed)/);
            const status = summaryMatch && summaryMatch[2] === 'passed' ? 'passed' : 'failed';

            resolve({
                status,
                duration,
                failedTests,
                lastOutput,
                totalTests: testCount
            });
        });

        child.on('error', () => {
            clearTimeout(timer);
            resolve({
                status: 'failed',
                duration: Date.now() - startTime,
                failedTests: [],
                lastOutput: [],
                totalTests: 0
            });
        });
    });
}

/**
 * Print test result details
 */
function printTestResult(result) {
    console.log('\n' + '━'.repeat(60));

    if (result.status === 'timeout') {
        console.log('⏱️  TIMEOUT: Tests did not complete in time!');
        console.log('❌ This indicates race conditions or async issues\n');

        if (result.failedTests.length > 0) {
            console.log(`🔥 FAILURES BEFORE TIMEOUT (${result.failedTests.length}):\n`);
            result.failedTests.forEach((failure, i) => {
                console.log(`${i + 1}. ${failure.name}`);
                failure.details.forEach(detail => {
                    console.log(`   ${detail.trim()}`);
                });
                console.log('');
            });
        }

        console.log('📋 LAST OUTPUT BEFORE TIMEOUT:\n');
        result.lastOutput.forEach(line => console.log(`  ${line}`));
        console.log('');
    } else if (result.status === 'passed') {
        console.log(`✅ ALL ${result.totalTests} TESTS PASSED`);
    } else {
        console.log(`❌ TEST RUN FAILED`);
        console.log(`   Total: ${result.totalTests} tests`);

        if (result.failedTests.length > 0) {
            console.log(`\n🔥 FAILED TESTS (${result.failedTests.length}):\n`);
            result.failedTests.forEach((failure, i) => {
                console.log(`${i + 1}. ${failure.name}`);
                failure.details.forEach(detail => {
                    console.log(`   ${detail.trim()}`);
                });
                console.log('');
            });
        } else if (result.lastOutput.length > 0) {
            console.log('\n📋 LAST OUTPUT:\n');
            result.lastOutput.forEach(line => console.log(`  ${line}`));
        }
    }

    console.log('━'.repeat(60) + '\n');
}

/**
 * Run tests once with detailed output
 */
async function runTests(command, timeoutMs = 10000) {
    cleanupZombieProcesses();

    console.log(`🧪 Running: ${command}`);
    console.log(`⏱️  Timeout: ${timeoutMs}ms\n`);

    const result = await executeTest(command, timeoutMs);
    printTestResult(result);

    process.exit(result.status === 'passed' ? 0 : result.status === 'timeout' ? 124 : 1);
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
 * Smart binary search to find timeout culprits
 * Only searches when tests timeout, not when they fail
 */
async function smartBinarySearch(tests, allTestsCount, baseTimeout, config, depth = 0) {
    const indent = '  '.repeat(depth);
    console.log(`${indent}🔍 Testing ${tests.length} tests (depth ${depth})...`);

    // Adaptive timeout based on test count ratio
    const timeoutRatio = Math.max(tests.length / allTestsCount, 0.2);
    const timeout = Math.max(Math.floor(baseTimeout * timeoutRatio), 2000);
    console.log(`${indent}⏱️  Timeout: ${timeout}ms (${(timeoutRatio * 100).toFixed(1)}% of base)`);

    cleanupZombieProcesses();

    const command = buildCommand(tests, tests, config);
    const result = await executeTest(command, timeout);

    // If passed or failed (not timeout), no culprits here
    if (result.status === 'passed') {
        console.log(`${indent}✅ This group PASSED - no culprits\n`);
        return [];
    }

    if (result.status === 'failed') {
        console.log(`${indent}❌ This group FAILED (not timeout) - not searching\n`);
        return [];
    }

    // Timeout detected
    console.log(`${indent}⏱️  This group TIMEOUT!\n`);

    // If group is small (1-5 tests), return all as culprits
    if (tests.length <= 5) {
        console.log(`${indent}🎯 Found ${tests.length} culprit(s):\n`);
        tests.forEach(test => console.log(`${indent}  - ${test}`));
        console.log('');
        return tests;
    }

    // Split in half and recurse
    const mid = Math.floor(tests.length / 2);
    const left = tests.slice(0, mid);
    const right = tests.slice(mid);

    console.log(`${indent}➗ Splitting into [0..${mid-1}] and [${mid}..${tests.length-1}]\n`);

    // Search both halves
    const leftCulprits = await smartBinarySearch(left, allTestsCount, baseTimeout, config, depth + 1);
    const rightCulprits = await smartBinarySearch(right, allTestsCount, baseTimeout, config, depth + 1);

    return [...leftCulprits, ...rightCulprits];
}

/**
 * Run smart timeout culprit detection
 */
async function runSmart(allTests, config, baseTimeout) {
    console.log('🧠 SMART MODE: Binary search for timeout culprits');
    console.log('━'.repeat(60));
    console.log(`Total tests:    ${allTests.length}`);
    console.log(`Base timeout:   ${baseTimeout}ms`);
    console.log('━'.repeat(60) + '\n');

    // First, run all tests to see if there's a timeout
    console.log('📊 Running all tests to detect timeout...\n');
    cleanupZombieProcesses();

    const command = buildCommand(allTests, allTests, config);
    const initialResult = await executeTest(command, baseTimeout);

    if (initialResult.status === 'passed') {
        console.log('\n✅ All tests PASSED - no timeout to investigate!\n');
        process.exit(0);
    }

    if (initialResult.status === 'failed') {
        console.log('\n❌ Tests FAILED (not timeout) - showing failures:\n');
        printTestResult(initialResult);
        process.exit(1);
    }

    // Timeout detected - start binary search
    console.log('\n⏱️  TIMEOUT detected! Starting binary search...\n');
    console.log('━'.repeat(60) + '\n');

    const culprits = await smartBinarySearch(allTests, allTests.length, baseTimeout, config);

    // Print final results
    console.log('━'.repeat(60));
    console.log('🎯 SMART SEARCH RESULTS');
    console.log('━'.repeat(60));

    if (culprits.length === 0) {
        console.log('⚠️  No specific culprits found - timeout may be environmental');
    } else {
        console.log(`Found ${culprits.length} test(s) causing timeout:\n`);
        culprits.forEach((test, i) => {
            console.log(`${i + 1}. ${test}`);
        });
        console.log('');
        console.log('💡 These tests together cause timeout/deadlock');
        console.log('💡 Try running them individually to confirm');
    }

    console.log('━'.repeat(60) + '\n');
    process.exit(culprits.length > 0 ? 1 : 0);
}

/**
 * Run multiple test iterations with detailed output for each
 */
async function runMultiple(command, timeout, runs) {
    console.log(`🔁 Running ${runs} iterations to check stability\n`);

    const results = {
        passed: 0,
        failed: 0,
        timeout: 0,
        runs: []
    };

    for (let i = 1; i <= runs; i++) {
        console.log(`\n${'━'.repeat(60)}`);
        console.log(`🧪 RUN ${i}/${runs}`);
        console.log('━'.repeat(60));

        cleanupZombieProcesses();

        const result = await executeTest(command, timeout);

        // Update counters
        if (result.status === 'passed') results.passed++;
        else if (result.status === 'timeout') results.timeout++;
        else results.failed++;

        results.runs.push({
            run: i,
            status: result.status,
            duration: result.duration,
            failedTests: result.failedTests,
            lastOutput: result.lastOutput
        });

        // Print result for this run
        printTestResult(result);
    }

    // Print summary
    console.log(`\n${'━'.repeat(60)}`);
    console.log('📊 MULTI-RUN SUMMARY');
    console.log('━'.repeat(60));
    console.log(`Total runs:    ${runs}`);
    console.log(`✅ Passed:     ${results.passed} (${(results.passed/runs*100).toFixed(1)}%)`);
    console.log(`❌ Failed:     ${results.failed} (${(results.failed/runs*100).toFixed(1)}%)`);
    console.log(`⏱️  Timeout:    ${results.timeout} (${(results.timeout/runs*100).toFixed(1)}%)`);

    if (results.timeout > 0) {
        console.log(`\n⚠️  ${results.timeout} timeout(s) detected - indicates race conditions!`);
    }

    console.log('\n📋 Detailed results:');
    results.runs.forEach(r => {
        const icon = r.status === 'passed' ? '✅' : r.status === 'timeout' ? '⏱️' : '❌';
        console.log(`  ${icon} Run ${r.run}: ${r.status.toUpperCase()} (${r.duration}ms)`);
    });
    console.log('━'.repeat(60) + '\n');

    // Exit with error if any failures/timeouts
    if (results.failed > 0 || results.timeout > 0) {
        process.exit(1);
    }
}

/**
 * Main
 */
async function main() {
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
  --config <path>      Path to config file (default: test-runner.default.config.json)
  --runs <N>           Run tests N times and show stability report
  --smart              Smart binary search for timeout culprits (adaptive timeout)
  --exclude <pattern>  Exclude tests matching pattern (can be used multiple times)
  --include <pattern>  Include only tests matching pattern (can be used multiple times)
  --timeout <ms>       Override timeout in milliseconds (default: 10000)
  --init               Generate default config file
  --list               List all available tests
  --dry-run            Show what would be run without executing
  --help, -h           Show this help

Config modes:
  all      - Run all tests
  exclude  - Run all tests EXCEPT those matching patterns
  include  - Run ONLY tests matching patterns
  last     - Run last N tests
  first    - Run first N tests

Examples:
  # Run all tests 3 times
  ./test-runner.js --runs 3

  # Smart binary search for timeout culprits
  ./test-runner.js --smart --timeout 10000

  # Exclude specific tests without config
  ./test-runner.js --exclude "SwiftAISDKTests.EmbedTests/*" --exclude "SwiftAISDKTests.EmbedManyTests/*"

  # Include only specific tests
  ./test-runner.js --include "SwiftAISDKTests.UIMessage*"

  # Combine: exclude with custom timeout
  ./test-runner.js --exclude "*.Embed*" --timeout 30000 --runs 5

  # Use config + override timeout
  ./test-runner.js --config my-config.json --timeout 20000
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

    // Parse CLI overrides
    const excludePatterns = [];
    const includePatterns = [];

    // Collect all --exclude arguments
    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--exclude' && args[i + 1]) {
            excludePatterns.push(args[i + 1]);
        }
        if (args[i] === '--include' && args[i + 1]) {
            includePatterns.push(args[i + 1]);
        }
    }

    // Override config with CLI arguments
    if (excludePatterns.length > 0) {
        config.mode = 'exclude';
        config.exclude = excludePatterns;
    }
    if (includePatterns.length > 0) {
        config.mode = 'include';
        config.include = includePatterns;
    }

    // Override timeout if provided
    const timeoutIndex = args.indexOf('--timeout');
    if (timeoutIndex !== -1) {
        config.timeout = parseInt(args[timeoutIndex + 1]);
    }

    const allTests = getAllTests();
    const filteredTests = filterTests(allTests, config);
    const timeout = config.timeout || 10000;

    // Check for smart mode
    if (args.includes('--smart')) {
        await runSmart(filteredTests.length > 0 ? filteredTests : allTests, config, timeout);
        return;
    }

    // Get number of runs
    const runsIndex = args.indexOf('--runs');
    const runs = runsIndex !== -1 ? parseInt(args[runsIndex + 1]) : 1;

    if (runs > 1) {
        // Multi-run mode
        console.log('📊 Test Runner Summary');
        console.log('━'.repeat(50));
        console.log(`Mode:           ${config.mode}`);
        console.log(`Total tests:    ${allTests.length}`);
        console.log(`Selected tests: ${filteredTests.length}`);
        console.log(`Runs:           ${runs}`);
        console.log(`Timeout:        ${config.timeout || 10000}ms`);
        console.log('━'.repeat(50) + '\n');

        const command = buildCommand(filteredTests, allTests, config);
        await runMultiple(command, timeout, runs);
        return;
    }

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
    await runTests(command, timeout);
}

main();
