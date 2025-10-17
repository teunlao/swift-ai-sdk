#!/usr/bin/env node

/**
 * Race Finder - Find race conditions by removing test suites from end
 *
 * Strategy:
 * 1. Run all tests N times (default: 3, configurable via --runs)
 * 2. If timeout: remove 5 suites from end, test N times
 * 3. Keep removing by 5 until timeout disappears
 * 4. Add back one by one to find exact culprit
 */

const { execSync, spawn } = require('node:child_process');

/**
 * Get all test suites (not individual tests)
 * @param {string[]} excludePatterns - Patterns to exclude from test suites
 */
function getAllTestSuites(excludePatterns = []) {
    try {
        const output = execSync('swift test list', {
            encoding: 'utf8',
            stdio: ['pipe', 'pipe', 'ignore']
        });

        const tests = output
            .split('\n')
            .filter(line => line.trim() && !line.includes('Building'))
            .map(line => line.trim());

        // Group by suite name
        const suites = new Set();
        tests.forEach(test => {
            const suite = test.split('/')[0];
            suites.add(suite);
        });

        let allSuites = Array.from(suites).sort();

        // Apply exclusion patterns
        if (excludePatterns.length > 0) {
            const originalCount = allSuites.length;
            allSuites = allSuites.filter(suite => {
                return !excludePatterns.some(pattern => {
                    // Support wildcards: * for any characters
                    const regexPattern = pattern
                        .replace(/[.+?^${}()|[\]\\]/g, '\\$&') // Escape regex special chars
                        .replace(/\*/g, '.*'); // Convert * to .*
                    const regex = new RegExp(`^${regexPattern}$`);
                    return regex.test(suite);
                });
            });
            const excludedCount = originalCount - allSuites.length;
            if (excludedCount > 0) {
                console.log(`🚫 Excluded ${excludedCount} suite(s) matching patterns: ${excludePatterns.join(', ')}\n`);
            }
        }

        return allSuites;
    } catch (error) {
        console.error('Failed to get test list:', error.message);
        process.exit(1);
    }
}

/**
 * Cleanup zombie test processes (aggressive version)
 */
function cleanupZombies() {
    try {
        execSync('pkill -9 -f "swift test"', { stdio: 'ignore' });
        execSync('pkill -9 -f "swiftpm-testing-helper"', { stdio: 'ignore' });
        execSync('pkill -9 swift-testing', { stdio: 'ignore' });
        execSync('pkill -9 xctest', { stdio: 'ignore' });
    } catch (error) {
        // Ignore - no zombies is fine
    }
}

/**
 * Execute test command with timeout
 */
function executeTest(suites, timeoutMs) {
    return new Promise((resolve) => {
        const startTime = Date.now();

        const args = ['test'];
        suites.forEach(suite => {
            args.push('--filter', suite);
        });

        const child = spawn('swift', args, {
            stdio: ['pipe', 'pipe', 'pipe'],
            shell: false
        });

        let timedOut = false;
        const timer = setTimeout(() => {
            timedOut = true;
            child.kill('SIGTERM');
            setTimeout(() => child.kill('SIGKILL'), 1000);
        }, timeoutMs);

        let output = '';
        child.stdout.on('data', (data) => {
            output += data.toString();
        });

        child.stderr.on('data', () => {
            // Ignore build output
        });

        child.on('exit', () => {
            clearTimeout(timer);
            const duration = Date.now() - startTime;

            if (timedOut) {
                resolve({ status: 'timeout', duration });
                return;
            }

            const passed = output.includes('passed');
            resolve({ status: passed ? 'passed' : 'failed', duration });
        });

        child.on('error', () => {
            clearTimeout(timer);
            resolve({ status: 'failed', duration: Date.now() - startTime });
        });
    });
}

/**
 * Run tests N times and check if any timeout
 * @param {string[]} suites - Test suites to run
 * @param {number} timeoutMs - Timeout in milliseconds
 * @param {number} runs - Number of times to run tests (default: 3)
 */
async function runMultipleTimes(suites, timeoutMs, runs = 3) {
    let timeoutCount = 0;
    let passedCount = 0;
    let failedCount = 0;

    for (let i = 1; i <= runs; i++) {
        console.log(`  Run ${i}/${runs}...`);
        cleanupZombies();

        const result = await executeTest(suites, timeoutMs);

        if (result.status === 'timeout') {
            timeoutCount++;
            console.log(`    ⏱️  TIMEOUT (${result.duration}ms)`);
        } else if (result.status === 'passed') {
            passedCount++;
            console.log(`    ✅ PASSED (${result.duration}ms)`);
        } else {
            failedCount++;
            console.log(`    ❌ FAILED (${result.duration}ms)`);
        }
    }

    return {
        hasTimeout: timeoutCount > 0,
        timeoutCount,
        passedCount,
        failedCount
    };
}

/**
 * Main race finder algorithm
 * @param {string[]} allSuites - All test suites
 * @param {number} timeoutMs - Timeout in milliseconds
 * @param {number} runs - Number of times to run tests
 */
async function findRace(allSuites, timeoutMs, runs = 3) {
    console.log('\n🏁 RACE FINDER');
    console.log('━'.repeat(60));
    console.log(`Total suites: ${allSuites.length}`);
    console.log(`Timeout:      ${timeoutMs}ms`);
    console.log(`Runs:         ${runs}`);
    console.log(`Strategy:     Remove from END until timeout disappears`);
    console.log('━'.repeat(60) + '\n');

    // Step 1: Run all tests N times
    console.log(`📊 Running ALL ${allSuites.length} suites (${runs} times)...\n`);
    const initialResult = await runMultipleTimes(allSuites, timeoutMs, runs);

    if (!initialResult.hasTimeout) {
        console.log('\n✅ No timeout detected - all tests pass!\n');
        return [];
    }

    console.log(`\n⏱️  TIMEOUT detected (${initialResult.timeoutCount}/${runs} runs)!`);
    console.log('Starting removal from END...\n');

    // Step 2: Remove from end by 5 until timeout disappears
    let removed = 0;
    let currentSuites = [...allSuites];
    let lastSafeCount = 0;

    while (removed < allSuites.length) {
        removed += 5;
        currentSuites = allSuites.slice(0, -removed);

        if (currentSuites.length === 0) {
            console.log('\n⚠️  All suites removed - race condition in first suite?\n');
            return [allSuites[0]];
        }

        console.log(`━`.repeat(60));
        console.log(`🔍 Testing with ${removed} suites removed from end`);
        console.log(`   Remaining: ${currentSuites.length} suites`);
        console.log(`   Removed range: [${currentSuites.length}..${allSuites.length - 1}]`);
        console.log(`━`.repeat(60) + '\n');

        const result = await runMultipleTimes(currentSuites, timeoutMs, runs);

        if (!result.hasTimeout) {
            console.log(`\n✅ Timeout disappeared! Last safe count: ${currentSuites.length} suites\n`);
            lastSafeCount = currentSuites.length;
            break;
        }

        console.log(`\n⏱️  Still timing out (${result.timeoutCount}/${runs} runs), removing more...\n`);
    }

    // Step 3: Find exact culprit(s)
    // We know: suites[0..lastSafeCount-1] = PASS
    // We know: suites[0..lastSafeCount+4] = TIMEOUT
    // Suspects: suites[lastSafeCount..lastSafeCount+4]

    const suspectStart = lastSafeCount;
    const suspectEnd = Math.min(lastSafeCount + 5, allSuites.length);
    const suspects = allSuites.slice(suspectStart, suspectEnd);

    console.log('━'.repeat(60));
    console.log(`🎯 SUSPECT RANGE: [${suspectStart}..${suspectEnd - 1}]`);
    console.log('━'.repeat(60));
    console.log(`\nSuspect suites (${suspects.length}):`);
    suspects.forEach((suite, i) => {
        console.log(`  ${suspectStart + i}. ${suite}`);
    });
    console.log('');

    // Try adding back one by one
    console.log('🔬 Testing suspects by adding back ONE BY ONE...\n');

    const baseSuites = allSuites.slice(0, lastSafeCount);
    const culprits = [];

    for (let i = 0; i < suspects.length; i++) {
        const testSuites = [...baseSuites, suspects[i]];

        console.log(`━`.repeat(60));
        console.log(`Testing: ${suspects[i]}`);
        console.log(`Total suites: ${testSuites.length} (base ${baseSuites.length} + 1 suspect)`);
        console.log(`━`.repeat(60) + '\n');

        const result = await runMultipleTimes(testSuites, timeoutMs, runs);

        if (result.hasTimeout) {
            console.log(`\n🎯 CULPRIT FOUND: ${suspects[i]} (timeout ${result.timeoutCount}/${runs} runs)\n`);
            culprits.push(suspects[i]);
        } else {
            console.log(`\n✅ Not a culprit: ${suspects[i]}\n`);
        }
    }

    return culprits;
}

/**
 * Kill all Swift PM processes before starting (AGGRESSIVE VERSION)
 */
function killAllSwiftProcesses() {
    console.log('🧹 Killing all Swift processes (aggressive mode)...\n');
    try {
        // Kill by process name patterns
        execSync('pkill -9 -f "swift test"', { stdio: 'ignore' });
        execSync('pkill -9 -f "swiftpm-testing-helper"', { stdio: 'ignore' });
        execSync('pkill -9 swift-testing', { stdio: 'ignore' });
        execSync('pkill -9 xctest', { stdio: 'ignore' });
        execSync('pkill -9 swift', { stdio: 'ignore' });

        // Kill specific Swift tools
        execSync('killall -9 swift-frontend 2>/dev/null', { stdio: 'ignore' });
        execSync('killall -9 swift-driver 2>/dev/null', { stdio: 'ignore' });
        execSync('killall -9 swift-test 2>/dev/null', { stdio: 'ignore' });
        execSync('killall -9 swiftc 2>/dev/null', { stdio: 'ignore' });

        // Kill by PID search (extreme measure)
        try {
            const pids = execSync(
                "ps aux | grep -E 'swift|SwiftPM' | grep -v grep | awk '{print $2}'",
                { encoding: 'utf8', stdio: 'pipe' }
            ).trim().split('\n').filter(Boolean);

            if (pids.length > 0) {
                pids.forEach(pid => {
                    try {
                        execSync(`kill -9 ${pid}`, { stdio: 'ignore' });
                    } catch (e) {
                        // Process may have already died
                    }
                });
            }
        } catch (e) {
            // No processes found - that's fine
        }

        // Small delay to ensure processes are dead
        execSync('sleep 1', { stdio: 'ignore' });

        // Verify cleanup
        try {
            const remaining = execSync(
                "ps aux | grep -i swift | grep -v grep | grep -v SWBBuildService | wc -l",
                { encoding: 'utf8', stdio: 'pipe' }
            ).trim();

            if (parseInt(remaining) === 0) {
                console.log('✅ All Swift processes killed successfully\n');
            } else {
                console.log(`⚠️  ${remaining} Swift process(es) still running (may be system processes)\n`);
            }
        } catch (e) {
            console.log('✅ All Swift processes killed successfully\n');
        }
    } catch (error) {
        // Ignore - no processes is fine
        console.log('✅ No Swift processes found to kill\n');
    }
}

/**
 * Main
 */
async function main() {
    // ALWAYS kill all Swift processes first
    killAllSwiftProcesses();

    const startTime = Date.now();
    const args = process.argv.slice(2);

    if (args.includes('--help') || args.includes('-h')) {
        console.log(`
Race Finder - Detect race conditions by removing tests from end

Usage:
  node race-finder.js [--timeout <ms>] [--runs <n>] [--exclude <pattern>...]

Options:
  --timeout <ms>        Timeout in milliseconds (default: 4000)
  --runs <n>            Number of times to run each test (default: 3)
  --exclude <pattern>   Exclude test suites matching pattern (can be used multiple times)
                        Supports wildcards: * for any characters
  --help, -h            Show this help

How it works:
  1. Run all tests N times
  2. If timeout: remove 5 suites from end, test N times
  3. Keep removing by 5 until timeout disappears
  4. Add back one by one to find exact culprit

Examples:
  node race-finder.js --timeout 5000 --runs 5
  node race-finder.js --exclude SwiftAISDKTests.CreateUIMessageStreamTests
  node race-finder.js --runs 10 --exclude "*UIMessageStream*" --exclude "*SerialJobExecutor*"
        `);
        return;
    }

    // Parse timeout
    const timeoutIndex = args.indexOf('--timeout');
    const timeoutMs = timeoutIndex !== -1 ? parseInt(args[timeoutIndex + 1]) : 4000;

    // Parse runs
    const runsIndex = args.indexOf('--runs');
    const runs = runsIndex !== -1 ? parseInt(args[runsIndex + 1]) : 3;

    // Parse exclude patterns
    const excludePatterns = [];
    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--exclude' && i + 1 < args.length) {
            excludePatterns.push(args[i + 1]);
        }
    }

    console.log('⏳ Getting all test suites (this may take a moment)...\n');
    const allSuites = getAllTestSuites(excludePatterns);
    console.log(`✅ Found ${allSuites.length} test suites\n`);

    const culprits = await findRace(allSuites, timeoutMs, runs);

    const duration = Date.now() - startTime;
    const minutes = Math.floor(duration / 60000);
    const seconds = ((duration % 60000) / 1000).toFixed(1);

    console.log('━'.repeat(60));
    console.log('🎯 FINAL RESULTS');
    console.log('━'.repeat(60));

    if (culprits.length > 0) {
        console.log(`\n⏱️  RACE CONDITION CULPRITS (${culprits.length}):\n`);
        culprits.forEach((suite, i) => {
            console.log(`  ${i + 1}. ${suite}`);
        });
        console.log('');
        console.log('💡 These suites cause timeout when added to safe set');
        console.log('   Look for shared state, deadlocks, or async issues');
    } else {
        console.log('\n✅ No specific culprits identified');
        console.log('   Timeout may be intermittent or environment-specific');
    }

    console.log(`\n⏱️  Total time: ${minutes}m ${seconds}s`);
    console.log('━'.repeat(60) + '\n');

    process.exit(culprits.length > 0 ? 1 : 0);
}

main();
