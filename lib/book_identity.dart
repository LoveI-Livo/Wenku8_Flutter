/// Local originals and virtual series share a reserved identity range.
const localBookIdStart = 0x60000000;
bool isLocalBook(int id) => id >= localBookIdStart;

/// Stable online/cloud records live below the local-original range.
///
/// Keeping cloud IDs out of [localBookIdStart] matters: the shelf, backup,
/// book-list assignment and reader settings all reserve the upper range for
/// files physically stored on this device. Cloud IDs must also stay within
/// the 31-bit range accepted by existing preference/backup records.
const cloudBookIdStart = 0x40000000;
const cloudBookIdEnd = 0x5fffffff;
bool isCloudBookId(int id) => id >= cloudBookIdStart && id <= cloudBookIdEnd;
