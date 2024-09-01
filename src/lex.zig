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
    while (source[res] == ' ' or
        source[res] == '\n' or
        source[res] == '\t' or
        source[res] == '\r')
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
            try std.testing.expectEqual(@as(?Token, null), result.token);
        }
    }
}
