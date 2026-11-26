// Copyright 2026 Contextual, Inc. https://agentrq.com
// This notice may not be modified or removed.
// SPDX-License-Identifier: AGPL-3.0-only

//! Byte ranges (RFC 9110 14) for an attachment the shell holds whole.
//!
//! WKWebView plays `<audio>` and `<video>` through AVFoundation, which asks
//! for `bytes=0-1` first and plays nothing unless the answer is a 206. The
//! server sends an attachment whole and ignores `Range`, so the shell fetches
//! it whole, as it always has, and cuts the range itself. One range only: a
//! server may answer any other `Range` with the whole body, and so do we.

use crate::protocol::{BytesReply, HeaderList};

/// The request headers that ask for part of a body. The shell answers them
/// itself, so they are never forwarded for an attachment.
pub const RANGE_REQUEST_HEADERS: [&str; 2] = ["range", "if-range"];

/// What a `Range` header asks of a body `len` bytes long.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Wanted {
    /// The whole body: no header, one we do not serve, or a malformed one.
    Whole,
    /// Bytes `start..=end`, both inside the body.
    Part { start: u64, end: u64 },
    /// A range that starts past the end: a 416.
    Unsatisfiable,
}

/// Reads a `Range` header against a body `len` bytes long.
pub fn wanted(range: Option<&str>, len: u64) -> Wanted {
    let Some(spec) = range.and_then(|range| {
        let (unit, spec) = range.trim().split_once('=')?;
        unit.trim().eq_ignore_ascii_case("bytes").then_some(spec)
    }) else {
        return Wanted::Whole;
    };
    if spec.contains(',') {
        return Wanted::Whole;
    }
    let Some((first, last)) = spec.trim().split_once('-') else {
        return Wanted::Whole;
    };
    let number = |text: &str| -> Option<u64> {
        let text = text.trim();
        (!text.is_empty() && text.bytes().all(|b| b.is_ascii_digit()))
            .then(|| text.parse().ok())
            .flatten()
    };
    match (first.trim().is_empty(), number(first), number(last)) {
        // `bytes=-n`: the last n bytes.
        (true, _, Some(0)) => Wanted::Unsatisfiable,
        (true, _, Some(suffix)) if len > 0 => Wanted::Part {
            start: len.saturating_sub(suffix),
            end: len - 1,
        },
        (true, _, Some(_)) => Wanted::Unsatisfiable,
        // `bytes=a-` and `bytes=a-b`.
        (false, Some(start), _) if start >= len => Wanted::Unsatisfiable,
        (false, Some(start), None) if last.trim().is_empty() => Wanted::Part {
            start,
            end: len - 1,
        },
        (false, Some(start), Some(end)) if end >= start => Wanted::Part {
            start,
            end: end.min(len - 1),
        },
        _ => Wanted::Whole,
    }
}

/// `reply`, an attachment held whole, answered for `range`: a 200 says it
/// takes ranges, a range in the body becomes a 206 of that part, and one past
/// its end a 416. Any other status goes back as it came.
pub fn ranged(mut reply: BytesReply, range: Option<&str>) -> BytesReply {
    if reply.status != 200 {
        return reply;
    }
    let len = reply.body.len() as u64;
    let mut headers: HeaderList = std::mem::take(&mut reply.headers)
        .into_iter()
        .filter(|(name, _)| name != "accept-ranges" && name != "content-range")
        .collect();
    headers.push(("accept-ranges".to_string(), "bytes".to_string()));
    let (status, body) = match wanted(range, len) {
        Wanted::Whole => (200, reply.body),
        Wanted::Part { start, end } => {
            headers.push((
                "content-range".to_string(),
                format!("bytes {start}-{end}/{len}"),
            ));
            (206, reply.body[start as usize..=end as usize].to_vec())
        }
        Wanted::Unsatisfiable => {
            headers.push(("content-range".to_string(), format!("bytes */{len}")));
            (416, Vec::new())
        }
    };
    BytesReply {
        status,
        headers,
        body,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ok(body: &[u8]) -> BytesReply {
        BytesReply {
            status: 200,
            headers: vec![
                ("content-type".to_string(), "audio/mp4".to_string()),
                ("accept-ranges".to_string(), "none".to_string()),
                ("content-range".to_string(), "bytes 0-0/1".to_string()),
            ],
            body: body.to_vec(),
        }
    }

    fn header<'a>(reply: &'a BytesReply, name: &str) -> Vec<&'a str> {
        reply
            .headers
            .iter()
            .filter(|(n, _)| n == name)
            .map(|(_, v)| v.as_str())
            .collect()
    }

    #[test]
    fn reads_one_byte_range() {
        let part = |start, end| Wanted::Part { start, end };
        let cases: [(Option<&str>, u64, Wanted); 22] = [
            (None, 10, Wanted::Whole),
            (Some("bytes=0-1"), 10, part(0, 1)),
            (Some(" Bytes = 2-4 "), 10, part(2, 4)),
            (Some("bytes=3-"), 10, part(3, 9)),
            (Some("bytes=5-99"), 10, part(5, 9)),
            (Some("bytes=-3"), 10, part(7, 9)),
            (Some("bytes=-30"), 10, part(0, 9)),
            (Some("bytes=10-"), 10, Wanted::Unsatisfiable),
            (Some("bytes=10-12"), 10, Wanted::Unsatisfiable),
            (Some("bytes=-0"), 10, Wanted::Unsatisfiable),
            (Some("bytes=-1"), 0, Wanted::Unsatisfiable),
            (Some("bytes=0-1"), 0, Wanted::Unsatisfiable),
            (Some("bytes=4-2"), 10, Wanted::Whole),
            (Some("bytes=0-1,4-5"), 10, Wanted::Whole),
            (Some("items=0-1"), 10, Wanted::Whole),
            (Some("bytes"), 10, Wanted::Whole),
            (Some("bytes=5"), 10, Wanted::Whole),
            (Some("bytes=-"), 10, Wanted::Whole),
            (Some("bytes=a-1"), 10, Wanted::Whole),
            (Some("bytes=1-b"), 10, Wanted::Whole),
            (Some("bytes=+1-2"), 10, Wanted::Whole),
            (Some("bytes=99999999999999999999-"), 10, Wanted::Whole),
        ];
        for (range, len, expected) in cases {
            assert_eq!(wanted(range, len), expected, "{range:?} of {len}");
        }
    }

    #[test]
    fn answers_a_range_with_its_part() {
        let reply = ranged(ok(b"0123456789"), Some("bytes=0-1"));
        assert_eq!(reply.status, 206);
        assert_eq!(reply.body, b"01");
        assert_eq!(header(&reply, "content-range"), ["bytes 0-1/10"]);
        assert_eq!(header(&reply, "accept-ranges"), ["bytes"]);
        assert_eq!(header(&reply, "content-type"), ["audio/mp4"]);
    }

    #[test]
    fn answers_no_range_whole_and_says_it_takes_ranges() {
        let reply = ranged(ok(b"0123"), None);
        assert_eq!(reply.status, 200);
        assert_eq!(reply.body, b"0123");
        assert_eq!(header(&reply, "accept-ranges"), ["bytes"]);
        assert!(header(&reply, "content-range").is_empty());
    }

    #[test]
    fn answers_a_range_past_the_end_with_a_416() {
        let reply = ranged(ok(b"0123"), Some("bytes=4-"));
        assert_eq!(reply.status, 416);
        assert!(reply.body.is_empty());
        assert_eq!(header(&reply, "content-range"), ["bytes */4"]);
    }

    #[test]
    fn leaves_any_other_status_alone() {
        let error = BytesReply {
            status: 404,
            headers: vec![("content-type".to_string(), "text/plain".to_string())],
            body: b"Not Found".to_vec(),
        };
        assert_eq!(ranged(error.clone(), Some("bytes=0-1")), error);
    }
}
