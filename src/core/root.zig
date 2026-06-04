// serval-15q
//! serval-core: stable semantic center.
//! Schema model, field metadata, pathing, value representation, errors.
//! No dependency on any wire format.

pub const schema = @import("schema.zig");
pub const type_info = @import("type_info.zig");
pub const field_meta = @import("field_meta.zig");
pub const attributes = @import("attributes.zig");
pub const value = @import("value.zig");
pub const context = @import("context.zig");
pub const errors = @import("errors.zig");
pub const result = @import("result.zig");

pub const Schema = schema.Schema;
pub const schemaOf = schema.schemaOf;
pub const Field = schema.Field;
pub const TypeOptions = schema.TypeOptions;
pub const Value = value.Value;
pub const FieldValue = value.FieldValue;
pub const Path = errors.Path;
pub const PathSegment = errors.PathSegment;
pub const IssueCode = errors.IssueCode;
pub const ValidationIssue = errors.ValidationIssue;
pub const ValidationReport = errors.ValidationReport;
pub const DecodeError = errors.DecodeError;
pub const DecodeResult = result.DecodeResult;
pub const ValidateContext = context.ValidateContext;
pub const FieldMeta = field_meta.FieldMeta;
