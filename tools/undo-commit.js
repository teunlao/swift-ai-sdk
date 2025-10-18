#!/usr/bin/env node

/**
 * Undo last commit (keeps all changes staged)
 * Equivalent to: git reset --soft HEAD~1
 */

const { execSync } = require('node:child_process');

try {
    console.log('🔄 Undoing last commit (keeping changes staged)...\n');

    // Show last commit info before undoing
    const lastCommit = execSync('git log -1 --oneline', { encoding: 'utf8' }).trim();
    console.log(`Last commit: ${lastCommit}\n`);

    // Undo commit (keep changes staged)
    execSync('git reset --soft HEAD~1', { stdio: 'inherit' });

    console.log('\n✅ Commit undone! All changes are still staged.');
    console.log('💡 You can now modify and re-commit, or unstage with: git restore --staged .');

} catch (error) {
    console.error('❌ Failed to undo commit:', error.message);
    process.exit(1);
}
