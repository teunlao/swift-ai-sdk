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
const TEST_CACHE_FILE = path.join(__dirname, '.test-cache.json');
const DEFAULT_TIMEOUT_MS = 15000;

function normalizeTestSelector(selector) {
    // `swift test list` prints test functions with trailing `()`, but `swift test --filter`
    // expects selectors without it.
    return selector.replace(/\(\)$/, '');
}

/**
 * Get all available tests (with optional caching)
 */
function getAllTests(useCache = false) {
    // Check if cache exists and user explicitly requested it
    if (useCache && fs.existsSync(TEST_CACHE_FILE)) {
        try {
            const cache = JSON.parse(fs.readFileSync(TEST_CACHE_FILE, 'utf8'));
            if (cache.tests && Array.isArray(cache.tests)) {
                console.log('📦 Using cached test list');
                return cache.tests;
            }
        } catch (error) {
            // Cache is corrupted, rebuild
        }
    }

    try {
        const output = execSync('swift test list', {
            encoding: 'utf8',
            stdio: ['pipe', 'pipe', 'ignore'] // Suppress stderr (build output)
        });

        const tests = output
            .split('\n')
            .filter(line => line.trim() && !line.includes('Building'))
            .map(line => normalizeTestSelector(line.trim()));

        // Save to cache only if user requested caching
        if (useCache) {
            try {
                fs.writeFileSync(TEST_CACHE_FILE, JSON.stringify({ tests, timestamp: new Date().toISOString() }, null, 2));
                console.log('💾 Cached test list');
            } catch (err) {
                // Ignore cache write errors
            }
        }

        return tests;
    } catch (error) {
        console.error('Failed to get test list:', error.message);
        exitWithTime(1);
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
        exitWithTime(1);
    }
}

/**
 * Match test name against pattern (supports wildcards)
 */
function matchPattern(testName, pattern) {
    testName = normalizeTestSelector(testName);
    pattern = normalizeTestSelector(pattern);

    // Convert wildcard pattern to regex
    // Escape regex metacharacters except for wildcards (* and ?).
    const escapedPattern = pattern.replace(/[\\^$+.()|[\]{}]/g, '\\$&');
    const regexPattern = escapedPattern
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
            const matchedTests = allTests.filter(test =>
                patterns.some(pattern => matchPattern(test, pattern))
            );

            // If we have wildcards, also check if any tests match and return suite names
            const hasWildcards = patterns.some(p => p.includes('*') || p.includes('?') || p.endsWith('/'));
            if (hasWildcards && matchedTests.length === 0) {
                // No actual tests match - return empty array
                return [];
            }

            if (hasWildcards && matchedTests.length > 0) {
                // Extract unique suite names from matched tests
                const suites = new Set();
                matchedTests.forEach(test => {
                    const suite = test.split('/')[0];
                    suites.add(suite);
                });
                return Array.from(suites);
            }

            return matchedTests;
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
            exitWithTime(1);
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
function executeTest(command, timeoutMs = DEFAULT_TIMEOUT_MS) {
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
                    const match = line.match(/Test run with (\d+) tests?/);
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

            const summaryMatch = output.match(/Test run with (\d+) tests?(?: in (\d+) suites?)? (passed|failed)/);
            const status = summaryMatch && summaryMatch[3] === 'passed' ? 'passed' : 'failed';

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
async function runTests(command, timeoutMs = DEFAULT_TIMEOUT_MS) {
    cleanupZombieProcesses();

    console.log(`🧪 Running: ${command}`);
    console.log(`⏱️  Timeout: ${timeoutMs}ms\n`);

    const result = await executeTest(command, timeoutMs);
    printTestResult(result);

    exitWithTime(result.status === 'passed' ? 0 : result.status === 'timeout' ? 124 : 1);
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
 * Verify individual culprits by running them alone
 * Returns classified results: broken, race, slow
 */
async function verifyCulprits(culprits, baseTimeout, config) {
    const results = {
        broken: [],      // Failed individually
        race: [],        // Passed individually, timeout in group
        slow: []         // Timeout individually
    };

    console.log('🔬 VERIFYING CULPRITS INDIVIDUALLY...\n');

    for (const test of culprits) {
        console.log(`  Testing: ${test}`);
        cleanupZombieProcesses();

        const command = buildCommand([test], [test], config);
        const result = await executeTest(command, baseTimeout);

        if (result.status === 'failed') {
            console.log(`    ❌ FAILED individually (broken test)\n`);
            results.broken.push({
                test,
                duration: result.duration,
                failures: result.failedTests
            });
        } else if (result.status === 'timeout') {
            console.log(`    ⏱️  TIMEOUT individually (slow test)\n`);
            results.slow.push({
                test,
                duration: result.duration
            });
        } else {
            console.log(`    ✅ PASSED individually (race condition culprit!)\n`);
            results.race.push({
                test,
                duration: result.duration
            });
        }
    }

    return results;
}

/**
 * Get all test suites (group tests by suite name)
 */
function getTestSuites(allTests) {
    const suiteMap = new Map();

    allTests.forEach(test => {
        const suite = test.split('/')[0];
        if (!suiteMap.has(suite)) {
            suiteMap.set(suite, []);
        }
        suiteMap.get(suite).push(test);
    });

    return Array.from(suiteMap.keys()).sort();
}

/**
 * Build command from suite names (not individual tests)
 */
function buildCommandFromSuites(suites, config) {
    const { parallel = false, verbose = false } = config;
    let cmd = 'swift test';
    let flags = '';

    if (parallel) {
        flags += ' --parallel';
    }
    if (verbose) {
        flags += ' --verbose';
    }

    suites.forEach(suite => {
        cmd += ` --filter "${suite}"`;
    });

    return cmd + flags;
}

/**
 * Global array to collect unstable test groups
 */
let unstableGroups = [];

/**
 * Smart binary search to find timeout culprits
 * Only searches when tests timeout, not when they fail
 */
async function smartBinarySearch(tests, allTestsCount, baseTimeout, config, depth = 0, runs = 1, currentTimeout = null) {
    const indent = '  '.repeat(depth);
    console.log(`${indent}🔍 Testing ${tests.length} tests (depth ${depth}, ${runs} run${runs > 1 ? 's' : ''})...`);

    // Calculate adaptive timeout: reduce by 25% each depth level, but not below 25% of base
    if (currentTimeout === null) {
        currentTimeout = baseTimeout;
    }

    const minTimeout = Math.floor(baseTimeout * 0.25);
    const timeout = Math.max(minTimeout, currentTimeout);

    const percentage = Math.round((timeout / baseTimeout) * 100);
    console.log(`${indent}⏱️  Timeout: ${timeout}ms (${percentage}% of base)`);

    const command = buildCommand(tests, tests, config);

    // Run multiple times to detect race conditions
    let timeoutCount = 0;
    let failedCount = 0;
    let passedCount = 0;
    let lastResult = null;

    for (let i = 1; i <= runs; i++) {
        if (runs > 1) {
            console.log(`${indent}  Run ${i}/${runs}...`);
        }
        cleanupZombieProcesses();

        const result = await executeTest(command, timeout);
        lastResult = result;

        if (result.status === 'timeout') {
            timeoutCount++;
            if (runs > 1) {
                console.log(`${indent}  ⏱️  TIMEOUT on run ${i}`);
            }
        } else if (result.status === 'failed') {
            failedCount++;
            if (runs > 1) {
                console.log(`${indent}  ❌ FAILED on run ${i}`);
            }
        } else {
            passedCount++;
            if (runs > 1) {
                console.log(`${indent}  ✅ PASSED on run ${i}`);
            }
        }
    }

    // Determine overall result
    const hasTimeout = timeoutCount > 0;
    const hasFailed = failedCount > 0;
    const result = hasTimeout ? { status: 'timeout' } : (hasFailed ? { status: 'failed' } : lastResult);

    // Check if group is UNSTABLE (mixed results: both timeout and pass)
    const isUnstable = hasTimeout && passedCount > 0;
    if (isUnstable) {
        unstableGroups.push({
            tests,
            depth,
            size: tests.length,
            timeoutCount,
            passedCount,
            failedCount,
            runs
        });
    }

    // If passed, no culprits here
    if (result.status === 'passed') {
        console.log(`${indent}✅ This group PASSED - no culprits\n`);
        return [];
    }

    // Timeout or Failed - continue searching
    if (result.status === 'timeout') {
        console.log(`${indent}⏱️  This group TIMEOUT!\n`);
    } else {
        console.log(`${indent}❌ This group FAILED - continuing search...\n`);
    }

    // If group is small (1-5 tests), return all as potential culprits
    if (tests.length <= 5) {
        console.log(`${indent}🎯 Found ${tests.length} potential culprit(s):\n`);
        tests.forEach(test => console.log(`${indent}  - ${test}`));
        console.log('');
        return tests;
    }

    // Split in half and recurse
    const mid = Math.floor(tests.length / 2);
    const left = tests.slice(0, mid);
    const right = tests.slice(mid);

    console.log(`${indent}➗ Splitting into [0..${mid-1}] and [${mid}..${tests.length-1}]\n`);

    // Reduce timeout by 25% for next level (but not below 25% of base)
    const nextTimeout = Math.floor(timeout * 0.75);

    // Search both halves with reduced timeout
    const leftCulprits = await smartBinarySearch(left, allTestsCount, baseTimeout, config, depth + 1, runs, nextTimeout);
    const rightCulprits = await smartBinarySearch(right, allTestsCount, baseTimeout, config, depth + 1, runs, nextTimeout);

    return [...leftCulprits, ...rightCulprits];
}

/**
 * Smart binary search working with test suites (not individual tests)
 */
async function smartBinarySearchSuites(suites, allSuites, baseTimeout, config, depth = 0, runs = 1, currentTimeout = null) {
    const indent = '  '.repeat(depth);
    console.log(`${indent}🔍 Testing ${suites.length} suite${suites.length !== 1 ? 's' : ''} (depth ${depth}, ${runs} run${runs > 1 ? 's' : ''})...`);

    // Calculate adaptive timeout: reduce by 25% each depth level, but not below 25% of base
    if (currentTimeout === null) {
        currentTimeout = baseTimeout;
    }

    const minTimeout = Math.floor(baseTimeout * 0.25);
    const timeout = Math.max(minTimeout, currentTimeout);

    const percentage = Math.round((timeout / baseTimeout) * 100);
    console.log(`${indent}⏱️  Timeout: ${timeout}ms (${percentage}% of base)`);

    const command = buildCommandFromSuites(suites, config);

    // Run multiple times to detect race conditions
    let timeoutCount = 0;
    let failedCount = 0;
    let passedCount = 0;
    let lastResult = null;

    for (let i = 1; i <= runs; i++) {
        if (runs > 1) {
            console.log(`${indent}  Run ${i}/${runs}...`);
        }
        cleanupZombieProcesses();

        const result = await executeTest(command, timeout);
        lastResult = result;

        if (result.status === 'timeout') {
            timeoutCount++;
            if (runs > 1) {
                console.log(`${indent}  ⏱️  TIMEOUT on run ${i}`);
            }
        } else if (result.status === 'failed') {
            failedCount++;
            if (runs > 1) {
                console.log(`${indent}  ❌ FAILED on run ${i}`);
            }
        } else {
            passedCount++;
            if (runs > 1) {
                console.log(`${indent}  ✅ PASSED on run ${i}`);
            }
        }
    }

    // Determine overall result
    const hasTimeout = timeoutCount > 0;
    const hasFailed = failedCount > 0;
    const result = hasTimeout ? { status: 'timeout' } : (hasFailed ? { status: 'failed' } : lastResult);

    // Check if group is UNSTABLE (mixed results: both timeout and pass)
    const isUnstable = hasTimeout && passedCount > 0;
    if (isUnstable) {
        unstableGroups.push({
            suites,
            depth,
            size: suites.length,
            timeoutCount,
            passedCount,
            failedCount,
            runs
        });
    }

    // If passed, no culprits here
    if (result.status === 'passed') {
        console.log(`${indent}✅ This group PASSED - no culprits\n`);
        return [];
    }

    // Timeout or Failed - continue searching
    if (result.status === 'timeout') {
        console.log(`${indent}⏱️  This group TIMEOUT!\n`);
    } else {
        console.log(`${indent}❌ This group FAILED - continuing search...\n`);
    }

    // If group is small (1-3 suites), return all as potential culprits
    if (suites.length <= 3) {
        console.log(`${indent}🎯 Found ${suites.length} potential culprit(s):\n`);
        suites.forEach(suite => console.log(`${indent}  - ${suite}`));
        console.log('');
        return suites;
    }

    // Split in half and recurse
    const mid = Math.floor(suites.length / 2);
    const left = suites.slice(0, mid);
    const right = suites.slice(mid);

    console.log(`${indent}➗ Splitting into [0..${mid-1}] and [${mid}..${suites.length-1}]\n`);

    // Reduce timeout by 25% for next level (but not below 25% of base)
    const nextTimeout = Math.floor(timeout * 0.75);

    // Search both halves with reduced timeout
    const leftCulprits = await smartBinarySearchSuites(left, allSuites, baseTimeout, config, depth + 1, runs, nextTimeout);
    const rightCulprits = await smartBinarySearchSuites(right, allSuites, baseTimeout, config, depth + 1, runs, nextTimeout);

    return [...leftCulprits, ...rightCulprits];
}

/**
 * Run smart timeout culprit detection (working with suites)
 */
async function runSmart(allTests, config, baseTimeout, runs = 1) {
    // Reset unstable groups
    unstableGroups = [];

    // Get test suites instead of individual tests
    const allSuites = getTestSuites(allTests);

    console.log('🧠 SMART MODE: Binary search for timeout culprits (by test suite)');
    console.log('━'.repeat(60));
    console.log(`Total tests:    ${allTests.length}`);
    console.log(`Total suites:   ${allSuites.length}`);
    console.log(`Base timeout:   ${baseTimeout}ms`);
    if (runs > 1) {
        console.log(`Runs per group: ${runs}`);
    }
    console.log('━'.repeat(60) + '\n');

    // First, run all suites to see if there's a timeout (run multiple times if requested)
    console.log(`📊 Running all ${allSuites.length} suites ${runs} time${runs > 1 ? 's' : ''} to detect timeout...\n`);

    const command = buildCommandFromSuites(allSuites, config);
    let hasTimeout = false;
    let hasFailed = false;
    let timeoutCount = 0;
    let passedCount = 0;
    let failedCount = 0;
    let lastResult = null;
    let firstFailedResult = null;

    for (let i = 1; i <= runs; i++) {
        if (runs > 1) {
            console.log(`  Run ${i}/${runs}...`);
        }
        cleanupZombieProcesses();

        const result = await executeTest(command, baseTimeout);
        lastResult = result;

        if (result.status === 'timeout') {
            hasTimeout = true;
            timeoutCount++;
            if (runs > 1) {
                console.log(`  ⏱️  TIMEOUT on run ${i}\n`);
            }
        } else if (result.status === 'failed') {
            hasFailed = true;
            failedCount++;
            if (!firstFailedResult) {
                firstFailedResult = result;
            }
            if (runs > 1) {
                console.log(`  ❌ FAILED on run ${i}\n`);
            }
        } else {
            passedCount++;
            if (runs > 1) {
                console.log(`  ✅ PASSED on run ${i}\n`);
            }
        }
    }

    // Check if initial group is UNSTABLE (mixed results: both timeout and pass)
    const isInitialGroupUnstable = hasTimeout && passedCount > 0;
    if (isInitialGroupUnstable) {
        unstableGroups.push({
            suites: allSuites,
            depth: 0,
            size: allSuites.length,
            timeoutCount,
            passedCount,
            failedCount,
            runs
        });
    }

    // Determine overall result
    const initialResult = hasTimeout ? { status: 'timeout' } : (hasFailed ? { status: 'failed' } : lastResult);

    if (initialResult.status === 'passed') {
        console.log('\n✅ All tests PASSED - no timeout to investigate!\n');
        exitWithTime(0);
    }

    if (initialResult.status === 'failed') {
        console.log('\n❌ Tests FAILED (not timeout) - showing failures:\n');
        printTestResult(firstFailedResult || lastResult);
        exitWithTime(1);
    }

    // Timeout detected - start binary search by splitting in half
    console.log('\n⏱️  TIMEOUT detected! Starting binary search...\n');
    console.log('━'.repeat(60) + '\n');

    // Split initial set of suites in half (skip re-running all suites)
    const mid = Math.floor(allSuites.length / 2);
    const left = allSuites.slice(0, mid);
    const right = allSuites.slice(mid);

    console.log(`🔍 Splitting ${allSuites.length} suites into [0..${mid-1}] and [${mid}..${allSuites.length-1}]\n`);

    // Start with 75% of base timeout for first split
    const firstTimeout = Math.floor(baseTimeout * 0.75);

    // Search both halves
    const leftCulprits = await smartBinarySearchSuites(left, allSuites, baseTimeout, config, 1, runs, firstTimeout);
    const rightCulprits = await smartBinarySearchSuites(right, allSuites, baseTimeout, config, 1, runs, firstTimeout);
    const potentialCulprits = [...leftCulprits, ...rightCulprits];

    if (potentialCulprits.length === 0 && unstableGroups.length === 0) {
        console.log('━'.repeat(60));
        console.log('🎯 SMART SEARCH RESULTS');
        console.log('━'.repeat(60));
        console.log('⚠️  No specific culprits or unstable groups found');
        console.log('━'.repeat(60) + '\n');
        exitWithTime(0);
    }

    // Show unstable groups if no specific culprits found
    if (potentialCulprits.length === 0 && unstableGroups.length > 0) {
        console.log('━'.repeat(60));
        console.log('🎯 SMART SEARCH RESULTS - UNSTABLE GROUPS DETECTED');
        console.log('━'.repeat(60));
        console.log('\n⚠️  UNSTABLE TEST GROUPS (race conditions detected):\n');
        console.log('   These groups show intermittent timeouts (both pass and timeout)');
        console.log('   This is the classic signature of race conditions!\n');

        // Sort by instability (highest timeout rate first), then by size (smallest first)
        const sorted = unstableGroups.sort((a, b) => {
            const aRate = a.timeoutCount / a.runs;
            const bRate = b.timeoutCount / b.runs;

            // If timeout rates are similar (within 10%), sort by size
            if (Math.abs(aRate - bRate) < 0.1) {
                return a.size - b.size;
            }

            // Otherwise, sort by timeout rate (higher first)
            return bRate - aRate;
        });

        sorted.forEach((group, i) => {
            console.log(`${i + 1}. Group of ${group.size} suite${group.size !== 1 ? 's' : ''} (depth ${group.depth}) - UNSTABLE`);
            console.log(`   Timeout: ${group.timeoutCount}/${group.runs} runs, Passed: ${group.passedCount}/${group.runs} runs`);
            console.log(`   Problematic suites:`);
            group.suites.forEach(suite => {
                console.log(`     📁 ${suite}`);
            });
            console.log('');
        });

        console.log('💡 RECOMMENDATIONS:');
        console.log('   • Focus on smallest unstable group first');
        console.log('   • Look for shared state, deadlocks, or async coordination issues');
        console.log('   • Try running the smallest group alone with multiple iterations');
        console.log(`   • Example: node tools/test-runner.js --include "${sorted[0].suites[0]}" --runs 10`);
        console.log('━'.repeat(60) + '\n');
        exitWithTime(1);
    }

    // Verify each culprit individually
    console.log('━'.repeat(60) + '\n');
    const verified = await verifyCulprits(potentialCulprits, baseTimeout, config);

    // Print smart categorized results
    console.log('━'.repeat(60));
    console.log('🎯 SMART SEARCH RESULTS');
    console.log('━'.repeat(60));

    let hasIssues = false;

    // Race condition culprits (most important!)
    if (verified.race.length > 0) {
        hasIssues = true;
        console.log('\n⏱️  RACE CONDITION CULPRITS (pass alone, timeout together):');
        console.log('   These tests cause deadlock/timeout when run with full suite\n');
        verified.race.forEach((item, i) => {
            console.log(`${i + 1}. ${item.test}`);
            console.log(`   ✅ Passes individually in ${item.duration}ms`);
        });
        console.log('');
    }

    // Broken tests
    if (verified.broken.length > 0) {
        hasIssues = true;
        console.log('\n🐛 BROKEN TESTS (fail individually):');
        console.log('   These tests are simply broken, not race conditions\n');
        verified.broken.forEach((item, i) => {
            console.log(`${i + 1}. ${item.test}`);
            console.log(`   ❌ Failed in ${item.duration}ms`);
            if (item.failures.length > 0) {
                console.log(`   Issue: ${item.failures[0].name}`);
            }
        });
        console.log('');
    }

    // Slow tests
    if (verified.slow.length > 0) {
        hasIssues = true;
        console.log('\n🐌 SLOW TESTS (timeout individually):');
        console.log('   These tests are just too slow, not race conditions\n');
        verified.slow.forEach((item, i) => {
            console.log(`${i + 1}. ${item.test}`);
            console.log(`   ⏱️  Timeout after ${item.duration}ms`);
        });
        console.log('');
    }

    // Summary
    if (!hasIssues) {
        console.log('⚠️  No issues found after verification');
    } else {
        console.log('💡 RECOMMENDATIONS:');
        if (verified.race.length > 0) {
            console.log('   • Fix race condition culprits first (most critical)');
            console.log('   • Look for shared state, deadlocks, or async coordination issues');
        }
        if (verified.broken.length > 0) {
            console.log('   • Fix broken tests (simple assertion failures)');
        }
        if (verified.slow.length > 0) {
            console.log('   • Optimize slow tests or increase timeout');
        }
    }

    console.log('━'.repeat(60) + '\n');
    exitWithTime(hasIssues ? 1 : 0);
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
        exitWithTime(1);
    }
}

/**
 * Format duration in human-readable format
 */
function formatDuration(ms) {
    if (ms < 1000) return `${ms}ms`;
    const seconds = (ms / 1000).toFixed(1);
    if (ms < 60000) return `${seconds}s`;
    const minutes = Math.floor(ms / 60000);
    const remainingSeconds = ((ms % 60000) / 1000).toFixed(1);
    return `${minutes}m ${remainingSeconds}s`;
}

/**
 * Global start time for total duration tracking
 */
let globalStartTime = null;

/**
 * Print total execution time and exit
 */
function exitWithTime(code) {
    if (globalStartTime) {
        const totalDuration = Date.now() - globalStartTime;
        console.log(`⏱️  Total execution time: ${formatDuration(totalDuration)}\n`);
    }
    process.exit(code);
}

/**
 * Main
 */
async function main() {
    globalStartTime = Date.now();
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
  --timeout <ms>       Override timeout in milliseconds (default: 6000)
  --cache              Use cached test list (saves time, use only if test list hasn't changed)
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
  ./test-runner.js --smart --timeout 6000

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
        exitWithTime(1);
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

    // Check for cache flag
    const useCache = args.includes('--cache');

    console.log('⏳ Getting all available tests (this may take a moment)...\n');
    const allTests = getAllTests(useCache);
    console.log(`✅ Found ${allTests.length} tests\n`);

    const filteredTests = filterTests(allTests, config);
    const timeout = config.timeout || DEFAULT_TIMEOUT_MS;

    // Get number of runs
    const runsIndex = args.indexOf('--runs');
    const runs = runsIndex !== -1 ? parseInt(args[runsIndex + 1]) : 1;

    // Check for smart mode
    if (args.includes('--smart')) {
        await runSmart(filteredTests.length > 0 ? filteredTests : allTests, config, timeout, runs);
        return;
    }

    if (runs > 1) {
        // Multi-run mode
        console.log('📊 Test Runner Summary');
        console.log('━'.repeat(50));
        console.log(`Mode:           ${config.mode}`);
        console.log(`Total tests:    ${allTests.length}`);
        console.log(`Selected tests: ${filteredTests.length}`);
        console.log(`Runs:           ${runs}`);
        console.log(`Timeout:        ${config.timeout || DEFAULT_TIMEOUT_MS}ms`);
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
