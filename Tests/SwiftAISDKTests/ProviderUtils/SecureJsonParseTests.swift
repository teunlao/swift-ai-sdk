// Licensed under BSD-3-Clause (this file only)
// Code adapted from https://github.com/fastify/secure-json-parse/blob/783fcb1b5434709466759847cec974381939673a/test/index.test.js
//
// Copyright (c) Vercel, Inc. (https://vercel.com)
// Copyright (c) 2019 The Fastify Team
// Copyright (c) 2019, Sideway Inc, and project contributors
// All rights reserved.
//
// The complete list of contributors can be found at:
// - https://github.com/hapijs/bourne/graphs/contributors
// - https://github.com/fastify/secure-json-parse/graphs/contributors
// - https://github.com/vercel/ai/commits/main/packages/provider-utils/src/secure-parse-json.test.ts
//
// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Testing
import Foundation
@testable import SwiftAISDK

@Suite("SecureJsonParse")
struct SecureJsonParseTests {

    @Test("parses object string")
    func parsesObjectString() throws {
        let result = try secureJsonParse(#"{"a": 5, "b": 6}"#)
        let dict = try #require(result as? [String: Any])
        #expect(dict["a"] as? Int == 5)
        #expect(dict["b"] as? Int == 6)
    }

    @Test("parses null string")
    func parsesNullString() throws {
        let result = try secureJsonParse("null")
        #expect(result is NSNull)
    }

    @Test("parses 0 string")
    func parsesZeroString() throws {
        let result = try secureJsonParse("0")
        #expect(result as? Int == 0)
    }

    @Test("parses string string")
    func parsesStringString() throws {
        let result = try secureJsonParse(#""X""#)
        #expect(result as? String == "X")
    }

    @Test("errors on constructor property")
    func errorsOnConstructorProperty() throws {
        let text = #"{ "a": 5, "b": 6, "constructor": { "x": 7 }, "c": { "d": 0, "e": "text", "__proto__": { "y": 8 }, "f": { "g": 2 } } }"#

        #expect(throws: SecureJsonParseError.self) {
            try secureJsonParse(text)
        }
    }

    @Test("errors on proto property")
    func errorsOnProtoProperty() throws {
        let text = #"{ "a": 5, "b": 6, "__proto__": { "x": 7 }, "c": { "d": 0, "e": "text", "__proto__": { "y": 8 }, "f": { "g": 2 } } }"#

        #expect(throws: SecureJsonParseError.self) {
            try secureJsonParse(text)
        }
    }

    @Test("errors on proto in nested arrays")
    func errorsOnProtoInNestedArrays() throws {
        // Test case for deeply nested arrays with __proto__
        // This verifies the fix for recursive array traversal
        let text = #"{ "data": [[{ "__proto__": { "x": 7 } }]] }"#

        #expect(throws: SecureJsonParseError.self) {
            try secureJsonParse(text)
        }
    }

    @Test("errors on constructor in nested arrays")
    func errorsOnConstructorInNestedArrays() throws {
        // Test case for deeply nested arrays with constructor.prototype
        // This ensures we catch prototype pollution at any array depth
        let text = #"{ "items": [[[{ "constructor": { "prototype": { "polluted": true } } }]]] }"#

        #expect(throws: SecureJsonParseError.self) {
            try secureJsonParse(text)
        }
    }

    @Test("parses clean nested arrays without error")
    func parsesCleanNestedArrays() throws {
        // Verify that deeply nested arrays without forbidden properties work fine
        let text = #"{ "data": [[{ "safe": "value" }]] }"#
        let result = try secureJsonParse(text)
        let dict = try #require(result as? [String: Any])
        #expect(dict["data"] != nil)
    }
}
