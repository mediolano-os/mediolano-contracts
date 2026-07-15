pub fn bytearray_ends_with(haystack: @ByteArray, needle: @ByteArray) -> bool {
    let n = needle.len();
    let h = haystack.len();
    if h < n {
        return false;
    }
    let offset = h - n;
    let mut i: u32 = 0;
    let mut matches = true;
    while i < n {
        if haystack.at(offset + i).unwrap() != needle.at(i).unwrap() {
            matches = false;
            break;
        }
        i += 1;
    }
    matches
}

pub fn bytearray_starts_with(haystack: @ByteArray, needle: @ByteArray) -> bool {
    let n = needle.len();
    if haystack.len() < n {
        return false;
    }
    let mut i: u32 = 0;
    let mut matches = true;
    while i < n {
        if haystack.at(i).unwrap() != needle.at(i).unwrap() {
            matches = false;
            break;
        }
        i += 1;
    }
    matches
}
