import assert from "node:assert/strict";
import test from "node:test";

import { createPatternRegex } from "./list-worktree-files.js";

test("createPatternRegex matches using star wildcard", () => {
	const regex = createPatternRegex("Test*.swift");

	assert.ok(regex.test("TestFile.swift"));
	assert.ok(regex.test("Test.swift"));
	assert.ok(!regex.test("Example.swift"));
});

test("createPatternRegex matches single characters with question wildcard", () => {
	const regex = createPatternRegex("file?.txt");

	assert.ok(regex.test("file1.txt"));
	assert.ok(regex.test("fileA.txt"));
	assert.ok(!regex.test("file10.txt"));
});

test("createPatternRegex escapes regex meta characters", () => {
	const regex = createPatternRegex("report[1].(final)");

	assert.ok(regex.test("report[1].(final)"));
	assert.ok(!regex.test("report1.final"));
	assert.ok(!regex.test("report[1].final"));
});
