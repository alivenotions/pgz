const std = @import("std");

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
};
