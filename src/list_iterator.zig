const c = @import("c");

const Kind = enum {auto, safe};

pub fn ListIterator(
	comptime T: type,
	comptime member_name: []const u8,
	comptime kind: Kind
) type {
	return struct {
		head: *c.wl_list,
		member: *T,
		tmp: if (kind == .safe) *T else void = undefined,

		const Self = @This();

		pub fn next(self: *Self) ?*T {
			if (&@field(self.member, member_name) == self.head) return null;

			if (kind == .safe) {
				const self_member_wll: *c.wl_list = &@field(self.member, member_name);
				const self_member_wll_next: *c.wl_list = @ptrCast(self_member_wll.next);
				self.member = self.tmp;
				self.tmp = @fieldParentPtr(member_name, self_member_wll_next);
				return self.member;
			}

			const self_member_wll: *c.wl_list = &@field(self.member, member_name);
			const self_member_wll_next: *c.wl_list = @ptrCast(self_member_wll.next);
			self.member = @fieldParentPtr(member_name, self_member_wll_next);
			return self.member;
		}

		pub fn reset(self: *Self) void {
			self.* = switch (kind) {
				.auto => iterate(T, member_name, self.head),
				.safe => iterate_safe(T, member_name, self.head)
			};
		}
	};
}

pub fn iterate(comptime T: type, comptime member_name: []const u8, head: *c.wl_list)
	ListIterator(T, member_name, .auto)
{
	return .{
		.head = head,
		.member = @fieldParentPtr(member_name, head)
	};
}

pub fn iterate_safe(comptime T: type, comptime member_name: []const u8, head: *c.wl_list)
	ListIterator(T, member_name, .safe)
{
	const first_member: *T = @fieldParentPtr(member_name, head);
	const first_member_wll: *c.wl_list = @ptrCast(&@field(first_member, member_name));
	const first_member_wll_next: *c.wl_list = @ptrCast(first_member_wll.next);

	return .{
		.head = head,
		.member = first_member,
		.tmp = @fieldParentPtr(member_name, first_member_wll_next)
	};
}
