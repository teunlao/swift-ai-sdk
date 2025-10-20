#!/usr/bin/env node

/**
 * Accurate test counter for TypeScript test files.
 * Handles: it(), test(), it.each(), describe.each(), nested describes
 */

const fs = require('fs');
const path = require('path');

function countTests(filePath) {
    const content = fs.readFileSync(filePath, 'utf8');

    let count = 0;

    // Pattern 1: Regular it() and test() calls
    const regularTests = content.match(/\b(it|test)\s*\(/g) || [];
    count += regularTests.length;

    // Pattern 2: it.each() - counts array length
    const itEachMatches = content.matchAll(/it\.each\s*\(\s*\[([\s\S]*?)\]\s*\)/g);
    for (const match of itEachMatches) {
        const arrayContent = match[1];
        // Count items by counting commas + 1 (rough estimate)
        // Better: count actual array elements
        const items = arrayContent.split(/,(?![^[\]]*\]|[^{}]*}|[^()]*\))/);
        const filteredItems = items.filter(item => item.trim().length > 0);
        count += filteredItems.length;
        // Subtract one regular it() that was already counted
        count -= 1;
    }

    // Pattern 3: describe.each() - counts array length * tests inside
    const describeEachMatches = content.matchAll(/describe\.each\s*\(\s*\[([\s\S]*?)\]\s*\)/g);
    for (const match of describeEachMatches) {
        const arrayContent = match[1];
        const items = arrayContent.split(/,(?![^[\]]*\]|[^{}]*}|[^()]*\))/);
        const filteredItems = items.filter(item => item.trim().length > 0);

        // Find the describe.each block and count tests inside
        const startIndex = match.index + match[0].length;
        let braceCount = 0;
        let describeBlock = '';
        let inBlock = false;

        for (let i = startIndex; i < content.length; i++) {
            if (content[i] === '{') {
                braceCount++;
                inBlock = true;
            }
            if (inBlock) describeBlock += content[i];
            if (content[i] === '}') {
                braceCount--;
                if (braceCount === 0) break;
            }
        }

        // Count tests inside this describe.each block
        const testsInBlock = (describeBlock.match(/\b(it|test)\s*\(/g) || []).length;
        count += (filteredItems.length - 1) * testsInBlock; // -1 because first iteration already counted
    }

    return count;
}

// Main
if (process.argv.length < 3) {
    console.log('Usage: node count-tests.js <test-file.ts>');
    console.log('Example: node count-tests.js external/vercel-ai-sdk/packages/anthropic/src/anthropic-messages-language-model.test.ts');
    process.exit(1);
}

const filePath = process.argv[2];

if (!fs.existsSync(filePath)) {
    console.error(`Error: File not found: ${filePath}`);
    process.exit(1);
}

const testCount = countTests(filePath);
console.log(`${path.basename(filePath)}: ${testCount} tests`);
