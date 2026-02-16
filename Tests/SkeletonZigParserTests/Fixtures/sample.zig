const std = @import("std");

pub const Animal = struct {
    name: []const u8,
    age: u32,

    pub fn init(name: []const u8, age: u32) Animal {
        return Animal{ .name = name, .age = age };
    }

    pub fn greet(self: *const Animal, greeting: []const u8) []const u8 {
        _ = greeting;
        return self.name;
    }
};

pub const Shape = enum {
    circle,
    rectangle,
    triangle,

    pub fn describe(self: Shape) []const u8 {
        return switch (self) {
            .circle => "circle",
            .rectangle => "rectangle",
            .triangle => "triangle",
        };
    }
};

pub const Point = struct {
    x: f64,
    y: f64,

    pub fn distance(self: Point, other: Point) f64 {
        _ = other;
        return self.x;
    }
};

pub const Value = union {
    int_val: i64,
    float_val: f64,
    bool_val: bool,
};
