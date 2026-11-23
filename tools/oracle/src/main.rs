//! `graft-oracle tokens <file>` and `graft-oracle tree <file>` print the tokens or the syntax
//! tree that the reference implementation makes of a file, in the format Graft prints.
//!
//! - One element per line: `Kind@start..end`, nested elements indented by two spaces.
//! - Positions count code points, not bytes, because Graft reads sources as code points.
//! - Kinds are the PascalCase of the reference implementation's `SyntaxKind` (`L_PAREN` is
//!   `LParen`), except for the few in `RENAMES`.
//! - Diagnostics follow as `error[E0101]@start..end`, without messages. `tree` prints only the
//!   codes the parser reports (`PARSER_CODES`), not those of the lexer or of validation.

use std::env;
use std::fs;
use std::process::ExitCode;

use emela_syntax::{SyntaxKind, SyntaxNode};
use rowan::{NodeOrToken, TextRange, WalkEvent};

/// Kinds whose Graft name is not the PascalCase of the reference name.
const RENAMES: &[(&str, &str)] = &[
    ("INT", "IntLit"),
    ("FLOAT", "FloatLit"),
    ("LTEQ", "LtEq"),
    ("GTEQ", "GtEq"),
];

/// The codes the parser of emela-syntax reports. Validation reports a disjoint set.
const PARSER_CODES: &[&str] = &[
    "E0110", "E0111", "E0112", "E0113", "E0114", "E0115", "E0117", "E0118", "E0119", "E0120",
    "E0121", "E0122", "E0126", "E0127", "E0128", "E0129", "E0131", "E0133", "E0142",
];

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    let (mode, path) = match args.as_slice() {
        [mode, path] if mode == "tokens" || mode == "tree" => (mode.as_str(), path),
        _ => {
            eprintln!("usage: graft-oracle <tokens|tree> <file>");
            return ExitCode::from(2);
        }
    };
    let src = match fs::read_to_string(path) {
        Ok(src) => src,
        Err(e) => {
            eprintln!("{path}: {e}");
            return ExitCode::FAILURE;
        }
    };
    let positions = Positions::new(&src);
    let mut out = String::new();
    if mode == "tokens" {
        let lexed = emela_syntax::lex(&src);
        for token in &lexed.tokens {
            out += &format!("{}@{}\n", name(token.kind), positions.range(token.range));
        }
    } else {
        let parse = emela_syntax::parse(&src);
        dump_tree(&parse.syntax(), &positions, &mut out);
        for d in parse.diagnostics() {
            if !PARSER_CODES.contains(&d.code.as_str()) {
                continue;
            }
            out += &format!("error[{}]@{}\n", d.code, positions.range(d.range));
        }
    }
    print!("{out}");
    ExitCode::SUCCESS
}

fn dump_tree(root: &SyntaxNode, positions: &Positions, out: &mut String) {
    let mut depth = 0;
    for event in root.preorder_with_tokens() {
        match event {
            WalkEvent::Enter(element) => {
                let range = positions.range(element.text_range());
                *out += &format!("{}{}@{range}\n", "  ".repeat(depth), name(element.kind()));
                if let NodeOrToken::Node(_) = element {
                    depth += 1;
                }
            }
            WalkEvent::Leave(NodeOrToken::Node(_)) => depth -= 1,
            WalkEvent::Leave(NodeOrToken::Token(_)) => {}
        }
    }
}

fn name(kind: SyntaxKind) -> String {
    let screaming = format!("{kind:?}");
    if let Some((_, graft)) = RENAMES.iter().find(|(reference, _)| *reference == screaming) {
        return (*graft).to_owned();
    }
    screaming
        .split('_')
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                Some(first) => first.to_string() + &chars.as_str().to_lowercase(),
                None => String::new(),
            }
        })
        .collect()
}

/// Maps byte offsets to code point offsets.
struct Positions {
    /// The code point offset of each byte offset that starts a character, and of the end.
    of_byte: Vec<usize>,
}

impl Positions {
    fn new(src: &str) -> Self {
        let mut of_byte = vec![0; src.len() + 1];
        for (n, (byte, _)) in src.char_indices().enumerate() {
            of_byte[byte] = n;
        }
        of_byte[src.len()] = src.chars().count();
        Positions { of_byte }
    }

    fn range(&self, range: TextRange) -> String {
        let start = self.of_byte[usize::from(range.start())];
        let end = self.of_byte[usize::from(range.end())];
        format!("{start}..{end}")
    }
}
