/// 
/// ----ZIG SUDOKU SOLVER----
/// 
///       by Ko6i, 2024
///       ~~~~~~~~~~~~~
///  

const std = @import("std");
const builtin = @import("builtin");

// BLOCK INDEXING:
// ==============
// 0 1 2
// 3 4 5
// 6 7 8

const OUTPUT_ERROR = "Output error!";

const Board = [9][9]usize;

const BgColor = enum(u8) {
    green = 42,
    magenta = 44
};

const GroupType = enum(u2) {
    row,
    column,
    block,

    pub fn others(t: GroupType) [2]GroupType {
        return switch (t) {
            .row => [2]GroupType{GroupType.column, GroupType.block},
            .column => [2]GroupType{GroupType.row, GroupType.block},
            .block => [2]GroupType{GroupType.row, GroupType.column}
        };
    }

    pub fn init_groups(b: *Board, t: GroupType) [9]Group {
        var ret = [_]Group{undefined} ** 9;
        for (0..9) |i| {
            ret[i] = Group.init(b, t, i);
        }
        return ret;
    } 
};

const Coords = struct {
    r: usize,
    c: usize,

    pub fn init(r: usize, c: usize) Coords {
        return Coords {
            .r = r,
            .c = c
        };
    }
};

const Group = struct {
    board: *Board,
    g_type: GroupType,
    no: usize,

    pub fn init(board: *Board, g_type: GroupType, no: usize) Group {
        return Group {
            .board = board,
            .g_type = g_type,
            .no = no
        };
    }

    pub fn get_coords(self: Group, i: usize) Coords {
        return switch (self.g_type) {
            .row => Coords.init(self.no, i),
            .column => Coords.init(i, self.no),
            .block => Coords.init((self.no / 3) * 3 + i / 3, (self.no % 3) * 3 + i % 3)
        };
    }

    pub fn get_by_coords(g_type: GroupType, coords: Coords) usize {
        return switch (g_type) {
            GroupType.row => coords.r,
            GroupType.column => coords.c,
            GroupType.block => (coords.r / 3) * 3 + coords.c / 3
        };
    }

    pub fn get(self: Group, i: usize) usize {
        const coords = get_coords(self, i);
        return self.board.*[coords.r][coords.c];
    }

    pub fn set(self: Group, i: usize, val: u4) void {
        const coords = get_coords(self, i);
        self.board.*[coords.r][coords.c] = val;
    }

    pub fn get_missing_vals(self: Group) [10]bool {
        var ret = [_]bool{false} ** 10;
        vals: for (1..10) |v| {
            for (0..9) |i| {
                if (self.get(i) == v) continue :vals;
            }
            ret[v] = true;
        }
        return ret;
    }

    pub fn get_missing_val_no(self: Group) u4 {
        var ret: u4 = 0;
        for (0..9) |p| {
            if (self.get(p) == 0) ret += 1;
        }
        return ret;
    }

    pub fn get_missing_pos(self: Group) [9]bool {
        var ret = [_]bool{false} ** 9;
        for (0..9) |p| {
            if (self.get(p) == 0) ret[p] = true;
        }
        return ret;
    }

};

const Snapshot = struct {
    board: Board,
    cur_field: Coords,
    possible_vals: [10]bool,

    pub fn init(board: Board, cur_field: Coords, possible_vals: [10]bool) Snapshot {
        return Snapshot {
            .board = board,
            .cur_field = cur_field,
            .possible_vals = possible_vals
        };
    }
};

fn sort_groups_by_missing(ctx: void, a: Group, b: Group) bool {
    _ = ctx;
    return a.get_missing_val_no() < b.get_missing_val_no();
}

fn solve(alloc: std.mem.Allocator, b_ptr: *Board) Board {
    var b = b_ptr.*;
    var groups: [9 * 3]Group = undefined;
    var snapshots = std.ArrayList(Snapshot).init(alloc);
    var min_fits: usize = 10;
    var min_fits_place: Coords = undefined;
    var min_fits_vals: [10]bool = undefined;

    solving: while (true) {
        groups = GroupType.init_groups(&b, GroupType.row) ++ GroupType.init_groups(&b, GroupType.column) ++ GroupType.init_groups(&b, GroupType.block);
        min_fits = 10;
        std.sort.insertion(Group, &groups, {}, sort_groups_by_missing);
        if (groups[groups.len - 1].get_missing_val_no() == 0) return b;
        for (groups) |g| {
            if (g.get_missing_val_no() == 0) continue;
            for (g.get_missing_pos(), 0..) |vp, p| {
                if (vp) {
                    const coords = g.get_coords(p);
                    var missing_vals: [10]bool = g.get_missing_vals();
                    for (GroupType.others(g.g_type)) |gt| {
                        for (Group.init(&b, gt, Group.get_by_coords(gt, coords)).get_missing_vals(), 0..) |other_val, vi| {
                            missing_vals[vi] = missing_vals[vi] and other_val;
                        }
                    }
                    var fits: usize = 0;
                    var one_of: usize = undefined;
                    for (missing_vals, 0..) |mv, imv| {
                        if (mv) {
                            fits += 1;
                            one_of = imv;
                        }
                    }
                    if (fits == 0) {
                        if (snapshots.items.len == 0) {
                            @panic("Cannot solve puzzle!");
                        } else {
                            var snap = snapshots.getLast();
                            var new_val: usize = 0;
                            for (0..10) |val_idx| {
                                if (snap.possible_vals[val_idx]) {
                                    new_val = val_idx;
                                    snap.possible_vals[val_idx] = false;
                                    break;
                                }
                            }
                            var vals_empty = true;
                            for (new_val..10) |idx| {
                                if (snap.possible_vals[idx]) {
                                    vals_empty = false;
                                    break;
                                }
                            }
                            if (vals_empty) _ = snapshots.pop();
                            @memcpy(&b, &snap.board);
                            b[snap.cur_field.r][snap.cur_field.c] = new_val;
                            continue :solving;
                        }
                    } else if (fits == 1) {
                        b[coords.r][coords.c] = one_of;
                        continue :solving;
                    } else if (fits < min_fits) {
                        min_fits = fits;
                        @memcpy(&min_fits_vals, &missing_vals);
                        min_fits_place = coords;
                    }
                }
            }
        }
        var shot_val: usize = 0;
        for (0..10) |idx| {
            if (min_fits_vals[idx]) {
                shot_val = idx;
                min_fits_vals[idx] = false;
                break;
            }
        }
        var save_board: Board = undefined;
        var save_vals: [10]bool = undefined;
        @memcpy(&save_board, &b);
        @memcpy(&save_vals, &min_fits_vals);
        snapshots.append(Snapshot.init(save_board, min_fits_place, save_vals)) catch @panic("Memory error!");
        b[min_fits_place.r][min_fits_place.c] = shot_val;
    }
}

fn display_board(board: Board, op: [9][9]bool) void {
    var bg: BgColor = undefined;
    std.io.getStdOut().writer().print("\n-----------------\n", .{}) catch @panic(OUTPUT_ERROR);
    for (board, 0..) |row, r| {
        for (row, 0..) |field, c| {
            bg = switch ((r/3 + c/3)%2) {
                0 => BgColor.green,
                else => BgColor.magenta
            };
            if (field == 0) {
                std.io.getStdOut().writer().print("\x1b[{}m \x1b[0m", .{@intFromEnum(bg)}) catch @panic(OUTPUT_ERROR);
            } else {
                if (op[r][c]) {
                    std.io.getStdOut().writer().print("\x1b[{};1m{}\x1b[0m", .{@intFromEnum(bg), field}) catch @panic(OUTPUT_ERROR);
                } else {
                    std.io.getStdOut().writer().print("\x1b[{}m{}\x1b[0m", .{@intFromEnum(bg), field}) catch @panic(OUTPUT_ERROR);
                }
            }
            if (c < 8) {
                std.io.getStdOut().writer().print("|", .{}) catch @panic(OUTPUT_ERROR);
            }
        }
        std.io.getStdOut().writer().print("\n-----------------\n", .{}) catch @panic(OUTPUT_ERROR);
    }
}

fn input_board(b: *Board, op: *[9][9]bool, halloc: std.mem.Allocator) void {

    var board = b.*;
    var orig_pos = op.*;

    for (0..9) |r| {
        var row = &board[r];
        var op_row = &orig_pos[r];
        for (row, op_row, 0..) |*field, *op_field, c| {
            while (true) {
                std.io.getStdOut().writer().print("Enter number for row {}, column {} - '0' if empty: ", .{r+1, c+1}) catch @panic(OUTPUT_ERROR);
                const field_input = std.io.getStdIn().reader().readUntilDelimiterAlloc(halloc, '\n', 128) catch @panic("Input error!");
                defer halloc.free(field_input);
                const field_input_trimmed = std.mem.trimRight(u8, field_input, &[_]u8{'\r'});
                const parse_input = std.fmt.parseInt(u4, field_input_trimmed, 10) catch {
                    std.io.getStdOut().writer().print("\nInvalid integer, try again.\n", .{}) catch @panic(OUTPUT_ERROR);
                    continue;
                };
                if (parse_input <= 9) {
                    field.* = parse_input;
                    if (parse_input > 0) {
                        op_field.* = true;
                    }
                    break;
                } else {
                    std.io.getStdOut().writer().print("\nValue too large, try again.\n", .{}) catch @panic(OUTPUT_ERROR);
                    continue;
                }
                halloc.free(field_input_trimmed);
            }
        }
    }
}

pub fn main() !void {

    const halloc = std.heap.page_allocator;
    std.io.getStdOut().writer().print("\n-~=Zig Sudoku Solver by Ko6i=~-\n\n", .{}) catch @panic(OUTPUT_ERROR);

    var orig_pos: [9][9]bool = undefined;
    var board: Board = undefined;
    input_board(&board, &orig_pos, halloc);

    display_board(board, orig_pos);

    board = solve(halloc, &board);

    std.io.getStdOut().writer().print("\nSOLVED:\n", .{}) catch @panic(OUTPUT_ERROR);

    display_board(board, orig_pos);

}