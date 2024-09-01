const std = @import("std");
const expectEqual = std.testing.expectEqual;

const Error = @import("types.zig").Error;
const String = @import("types.zig").String;

pub const Token = struct {
    start: u64,
    end: u64,
    kind: Kind,
    source: String,

    pub const Kind = enum {
        select_keyword,
        create_table_keyword,
        insert_keyword,
        values_keyword,
        from_keyword,
        where_keyword,

        plus_operator,
        equal_operator,
        lt_operator,
        concat_operator,

        left_paren_syntax,
        right_paren_syntax,
        comma_syntax,

        identifier,
        integer,
        string,
    };

    pub fn string(self: Token) String {
        return self.source[self.start..self.end];
    }

    fn debug(self: Token, msg: String) void {
        var line: usize = 0;
        var column: usize = 0;
        var lineStartIndex: usize = 0;
        var lineEndIndex: usize = 0;
        var i: usize = 0;
        var source = self.source;

        while (i < source.len) {
            if (source[i] == '\n') {
                line += 1;
                column = 0;
                lineStartIndex = i + 1;
            } else {
                column += 1;
            }

            if (i == self.start) {
                lineEndIndex = i;
                while (source[lineEndIndex] != '\n') {
                    lineEndIndex += 1;
                }
                break;
            }
            i += 1;
        }

        std.debug.print(
            "{s}\nNear line {}, column {}.\n{s}\n",
            .{ msg, line + 1, column, source[lineStartIndex..lineEndIndex] },
        );

        while (column - 1 > 0) {
            std.debug.print(" ", .{});
            column -= 1;
        }
        std.debug.print("^ Near here\n\n", .{});
    }
};

pub fn debug(tokens: []Token, preferredIndex: usize, msg: String) void {
    var i = preferredIndex;
    while (i >= tokens.len) {
        i -= 1;
    }

    tokens[i].debug(msg);
}

const Builtin = struct {
    name: String,
    kind: Token.Kind,
};

var BUILTINS = [_]Builtin{
    .{ .name = "CREATE TABLE", .kind = Token.Kind.create_table_keyword },
    .{ .name = "INSERT INTO", .kind = Token.Kind.insert_keyword },
    .{ .name = "VALUES", .kind = Token.Kind.values_keyword },
    .{ .name = "FROM", .kind = Token.Kind.from_keyword },
    .{ .name = "WHERE", .kind = Token.Kind.where_keyword },
    .{ .name = "SELECT", .kind = Token.Kind.select_keyword },
    .{ .name = "||", .kind = Token.Kind.concat_operator },
    .{ .name = "+", .kind = Token.Kind.plus_operator },
    .{ .name = "=", .kind = Token.Kind.equal_operator },
    .{ .name = "<", .kind = Token.Kind.lt_operator },
    .{ .name = "(", .kind = Token.Kind.left_paren_syntax },
    .{ .name = ")", .kind = Token.Kind.right_paren_syntax },
    .{ .name = ",", .kind = Token.Kind.comma_syntax },
};

fn eatWhitespace(source: String, index: usize) usize {
    if (source.len == 0) {
        return index;
    }

    var res = index;
    while (res < source.len and (source[res] == ' ' or
        source[res] == '\n' or
        source[res] == '\t' or
        source[res] == '\r'))
    {
        res += 1;
        if (res == source.len) {
            break;
        }
    }
    return res;
}

fn asciiCaseInsensitiveEqual(left: String, right: String) bool {
    const min_len = @min(left.len, right.len);

    for (0..min_len) |i| {
        var l = left[i];
        if (l >= 97 and l <= 122) {
            l -= 32;
        }

        var r = right[i];
        if (r >= 97 and r <= 122) {
            r -= 32;
        }

        if (l != r) {
            return false;
        }
    }
    return left.len == right.len;
}

fn lexKeyword(source: String, index: usize) struct { nextPosition: usize, token: ?Token } {
    var longestLen: usize = 0;
    var kind = Token.Kind.select_keyword;
    for (BUILTINS) |builtin| {
        if (index + builtin.name.len >= source.len) {
            continue;
        }

        if (asciiCaseInsensitiveEqual(source[index .. index + builtin.name.len], builtin.name)) {
            longestLen = builtin.name.len;
            kind = builtin.kind;
            break;
        }
    }

    if (longestLen == 0) {
        return .{ .nextPosition = 0, .token = null };
    }

    return .{
        .nextPosition = index + longestLen,
        .token = Token{
            .source = source,
            .start = index,
            .end = index + longestLen,
            .kind = kind,
        },
    };
}

fn lexInteger(source: String, index: usize) struct { nextPosition: usize, token: ?Token } {
    const start = index;
    var end = index;
    var i = index;
    while (i < source.len and source[i] >= '0' and source[i] <= '9') : (i += 1) {
        end = end + 1;
    }

    if (start == end) {
        return .{ .nextPosition = 0, .token = null };
    }

    return .{
        .nextPosition = end,
        .token = Token{
            .source = source,
            .start = start,
            .end = end,
            .kind = Token.Kind.integer,
        },
    };
}

fn lexString(source: String, index: usize) struct { nextPosition: usize, token: ?Token } {
    var i = index;
    if (source[i] != '\'') {
        return .{ .nextPosition = 0, .token = null };
    }
    i = i + 1;
    const start = i;
    var end = i;

    while (i < source.len and source[i] != '\'') : (i += 1) {
        end = end + 1;
    }

    if (source[i] == '\'') {
        i = i + 1;
    }

    if (start == end) {
        return .{ .nextPosition = 0, .token = null };
    }

    return .{
        .nextPosition = i,
        .token = Token{
            .source = source,
            .start = start,
            .end = end,
            .kind = Token.Kind.string,
        },
    };
}

fn lexIdentifier(source: String, index: usize) struct { nextPosition: usize, token: ?Token } {
    const start = index;
    var end = index;
    var i = index;
    while (i < source.len and ((source[i] >= 'a' and source[i] <= 'z') or
        (source[i] >= 'A' and source[i] <= 'Z') or
        (source[i] == '*'))) : (i += 1)
    {
        end = end + 1;
    }

    if (start == end) {
        return .{ .nextPosition = 0, .token = null };
    }

    return .{
        .nextPosition = end,
        .token = Token{
            .source = source,
            .start = start,
            .end = end,
            .kind = Token.Kind.identifier,
        },
    };
}

pub fn lex(source: String, tokens: *std.ArrayList(Token)) ?Error {
    var i: usize = 0;
    while (true) {
        i = eatWhitespace(source, i);
        if (i >= source.len) {
            break;
        }

        const keywordRes = lexKeyword(source, i);
        if (keywordRes.token) |token| {
            tokens.append(token) catch return "Failed to allocate space for keyword token";
            i = keywordRes.nextPosition;
            continue;
        }

        const integerRes = lexInteger(source, i);
        if (integerRes.token) |token| {
            tokens.append(token) catch return "Failed to allocate space for integer token";
            i = integerRes.nextPosition;
            continue;
        }

        const stringRes = lexString(source, i);
        if (stringRes.token) |token| {
            tokens.append(token) catch return "Failed to allocate space for string token";
            i = stringRes.nextPosition;
            continue;
        }

        const identifierRes = lexIdentifier(source, i);
        if (identifierRes.token) |token| {
            tokens.append(token) catch return "Failed to allocate space for identifier token";
            i = identifierRes.nextPosition;
            continue;
        }

        if (tokens.items.len > 0) {
            debug(tokens.items, tokens.items.len - 1, "Last good token.\n");
        }
        return "Bad token";
    }

    return null;
}

test "eatWhitespace" {
    const testCases = [_]struct {
        input: []const u8,
        startIndex: usize,
        expectedIndex: usize,
    }{
        .{ .input = "   abc", .startIndex = 0, .expectedIndex = 3 },
        .{ .input = "abc   def", .startIndex = 3, .expectedIndex = 6 },
        .{ .input = "abc\n\t\rdef", .startIndex = 3, .expectedIndex = 6 },
        .{ .input = "   ", .startIndex = 0, .expectedIndex = 3 },
        .{ .input = "abc", .startIndex = 0, .expectedIndex = 0 },
        .{ .input = "", .startIndex = 0, .expectedIndex = 0 },
    };

    for (testCases) |tc| {
        const result = eatWhitespace(tc.input, tc.startIndex);
        try expectEqual(tc.expectedIndex, result);
    }
}

test "asciiCaseInsensitiveEqual" {
    const testCases = [_]struct {
        left: []const u8,
        right: []const u8,
        expected: bool,
    }{
        .{ .left = "hello", .right = "HELLO", .expected = true },
        .{ .left = "World", .right = "world", .expected = true },
        .{ .left = "Zig", .right = "zig", .expected = true },
        .{ .left = "OpenAI", .right = "openai", .expected = true },
        .{ .left = "Test", .right = "test", .expected = true },
        .{ .left = "Different", .right = "Strings", .expected = false },
        .{ .left = "Case", .right = "case", .expected = true },
        .{ .left = "LongerString", .right = "Longer", .expected = false },
        .{ .left = "Shorter", .right = "ShorterString", .expected = false },
        .{ .left = "", .right = "", .expected = true },
        .{ .left = "A", .right = "a", .expected = true },
        .{ .left = "123", .right = "123", .expected = true },
        .{ .left = "MixEd123CaSe", .right = "MiXeD123cAsE", .expected = true },
    };

    for (testCases) |tc| {
        const result = asciiCaseInsensitiveEqual(tc.left, tc.right);
        try expectEqual(tc.expected, result);
    }
}

test "lexKeyword" {
    const testCases = [_]struct {
        source: []const u8,
        index: usize,
        expectedNextPosition: usize,
        expectedToken: ?Token.Kind,
    }{
        .{ .source = "SELECT * FROM table", .index = 0, .expectedNextPosition = 6, .expectedToken = .select_keyword },
        .{ .source = "from table", .index = 0, .expectedNextPosition = 4, .expectedToken = .from_keyword },
        .{ .source = "WHERE id = 1", .index = 0, .expectedNextPosition = 5, .expectedToken = .where_keyword },
        .{ .source = "SELECTFROM", .index = 0, .expectedNextPosition = 6, .expectedToken = .select_keyword },
        .{ .source = "not_a_keyword", .index = 0, .expectedNextPosition = 0, .expectedToken = null },
        .{ .source = "SELECT", .index = 1, .expectedNextPosition = 0, .expectedToken = null },
        .{ .source = "sElEcT * FROM table", .index = 0, .expectedNextPosition = 6, .expectedToken = .select_keyword },
    };

    for (testCases) |tc| {
        const result = lexKeyword(tc.source, tc.index);
        try expectEqual(tc.expectedNextPosition, result.nextPosition);
        if (tc.expectedToken) |expected| {
            try expectEqual(expected, result.token.?.kind);
        } else {
            try expectEqual(@as(?Token, null), result.token);
        }
    }
}

test "lexInteger" {
    const testCases = [_]struct {
        source: []const u8,
        index: usize,
        expectedNextPosition: usize,
        expectedToken: ?Token.Kind,
        expectedStart: usize,
        expectedEnd: usize,
    }{
        .{ .source = "123", .index = 0, .expectedNextPosition = 3, .expectedToken = .integer, .expectedStart = 0, .expectedEnd = 3 },
        .{ .source = "456 abc", .index = 0, .expectedNextPosition = 3, .expectedToken = .integer, .expectedStart = 0, .expectedEnd = 3 },
        .{ .source = "abc 789", .index = 0, .expectedNextPosition = 0, .expectedToken = null, .expectedStart = 0, .expectedEnd = 0 },
        .{ .source = "abc 789", .index = 4, .expectedNextPosition = 7, .expectedToken = .integer, .expectedStart = 4, .expectedEnd = 7 },
        .{ .source = "42abc", .index = 0, .expectedNextPosition = 2, .expectedToken = .integer, .expectedStart = 0, .expectedEnd = 2 },
        .{ .source = "0", .index = 0, .expectedNextPosition = 1, .expectedToken = .integer, .expectedStart = 0, .expectedEnd = 1 },
        .{ .source = "", .index = 0, .expectedNextPosition = 0, .expectedToken = null, .expectedStart = 0, .expectedEnd = 0 },
    };

    for (testCases) |tc| {
        const result = lexInteger(tc.source, tc.index);
        try expectEqual(tc.expectedNextPosition, result.nextPosition);
        if (tc.expectedToken) |expected| {
            try expectEqual(expected, result.token.?.kind);
            try expectEqual(tc.expectedStart, result.token.?.start);
            try expectEqual(tc.expectedEnd, result.token.?.end);
        } else {
            try expectEqual(@as(?Token, null), result.token);
        }
    }
}

test "lexString" {
    const testCases = [_]struct {
        source: []const u8,
        index: usize,
        expectedNextPosition: usize,
        expectedToken: ?Token.Kind,
        expectedStart: usize,
        expectedEnd: usize,
    }{
        .{ .source = "'hello'", .index = 0, .expectedNextPosition = 7, .expectedToken = .string, .expectedStart = 1, .expectedEnd = 6 },
        .{ .source = "'hello world'", .index = 0, .expectedNextPosition = 13, .expectedToken = .string, .expectedStart = 1, .expectedEnd = 12 },
        .{ .source = "abc 'hello'", .index = 4, .expectedNextPosition = 11, .expectedToken = .string, .expectedStart = 5, .expectedEnd = 10 },
        .{ .source = "abc 'hello' def", .index = 4, .expectedNextPosition = 11, .expectedToken = .string, .expectedStart = 5, .expectedEnd = 10 },
        .{ .source = "abc 'hello' def", .index = 11, .expectedNextPosition = 0, .expectedToken = null, .expectedStart = 0, .expectedEnd = 0 },
    };

    for (testCases) |tc| {
        const result = lexString(tc.source, tc.index);
        try expectEqual(tc.expectedNextPosition, result.nextPosition);
        if (tc.expectedToken) |expected| {
            try expectEqual(expected, result.token.?.kind);
            try expectEqual(tc.expectedStart, result.token.?.start);
            try expectEqual(tc.expectedEnd, result.token.?.end);
        } else {
            try expectEqual(@as(?Token, null), result.token);
        }
    }
}

test "lexIdentifier" {
    const testCases = [_]struct {
        source: []const u8,
        index: usize,
        expectedNextPosition: usize,
        expectedToken: ?Token.Kind,
        expectedStart: usize,
        expectedEnd: usize,
    }{
        .{ .source = "hello", .index = 0, .expectedNextPosition = 5, .expectedToken = .identifier, .expectedStart = 0, .expectedEnd = 5 },
        .{ .source = "hello world", .index = 0, .expectedNextPosition = 5, .expectedToken = .identifier, .expectedStart = 0, .expectedEnd = 5 },
        .{ .source = "abc hello", .index = 4, .expectedNextPosition = 9, .expectedToken = .identifier, .expectedStart = 4, .expectedEnd = 9 },
        .{ .source = "abc hello def", .index = 4, .expectedNextPosition = 9, .expectedToken = .identifier, .expectedStart = 4, .expectedEnd = 9 },
        .{ .source = "abc hello def", .index = 9, .expectedNextPosition = 0, .expectedToken = null, .expectedStart = 0, .expectedEnd = 0 },
    };

    for (testCases) |tc| {
        const result = lexIdentifier(tc.source, tc.index);
        try expectEqual(tc.expectedNextPosition, result.nextPosition);
        if (tc.expectedToken) |expected| {
            try expectEqual(expected, result.token.?.kind);
            try expectEqual(tc.expectedStart, result.token.?.start);
            try expectEqual(tc.expectedEnd, result.token.?.end);
        } else {
            try expectEqual(@as(?Token, null), result.token);
        }
    }
}

test "lexer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const testCases = [_]struct {
        source: []const u8,
        expectedTokens: []const Token.Kind,
        expectedError: ?Error,
    }{
        .{
            .source = "SELECT * FROM table",
            .expectedTokens = &[_]Token.Kind{ .select_keyword, .identifier, .from_keyword, .identifier },
            .expectedError = null,
        },
        .{
            .source = "SELECT * FROM table WHERE id = 1",
            .expectedTokens = &[_]Token.Kind{ .select_keyword, .identifier, .from_keyword, .identifier, .where_keyword, .identifier, .equal_operator, .integer },
            .expectedError = null,
        },
        .{
            .source = "SELECT * FROM table WHERE id = 'abc'",
            .expectedTokens = &[_]Token.Kind{ .select_keyword, .identifier, .from_keyword, .identifier, .where_keyword, .identifier, .equal_operator, .string },
            .expectedError = null,
        },
    };

    for (testCases) |tc| {
        var tokens = std.ArrayList(Token).init(allocator);
        defer tokens.deinit();

        const err = lex(tc.source, &tokens);

        if (tc.expectedError) |expected_error| {
            try std.testing.expectEqualStrings(expected_error, err.?);
        } else {
            try expectEqual(@as(?Error, null), err);
            try expectEqual(tc.expectedTokens.len, tokens.items.len);
            for (tc.expectedTokens, tokens.items) |expected, actual| {
                try expectEqual(expected, actual.kind);
            }
        }
    }
}
