// serval-15q
//! Shared test fixture types used across serval's own test suites.

pub const User = struct {
    id: u64,
    name: []const u8,
    email: []const u8 = "",
    age: ?u8 = null,
};

pub const sample_user_json =
    \\{"id":1,"name":"ada","email":"ada@example.com","age":36}
;
