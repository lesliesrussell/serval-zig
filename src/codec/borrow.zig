// serval-15q
//! Borrowed decoding support (MemoryMode.borrowed).
//! Lifetime rule: a Borrowed(T) is valid only as long as the input buffer
//! it was decoded from. This must stay painfully explicit in docs and
//! signatures.

pub fn Borrowed(comptime T: type) type {
    return struct {
        /// Slices inside `value` may point into the input buffer.
        value: T,
    };
}
