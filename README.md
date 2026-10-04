# password-generator

A [Chez Scheme](https://cisco.github.io/ChezScheme/) command-line tool that generates human-readable passwords such as `consen7-reffub-seizing-MEAN` and `3katsim-roster-d4rt-TIN`. It needs only Chez Scheme.

## How passwords are built

1. Words are drawn from a list of ~5,700 common English words (`passgen/words.scm`) using `/dev/urandom` with rejection sampling, so every word is equally likely.
2. Each word is independently transformed:
   - reversed (1 in 4): `lips` → `spil`
   - one letter replaced with a look-alike digit (1 in 3): `a→4 e→3 i→1 o→0 s→5 t→7`, e.g., `hair` → `ha1r`
   - upcased if it is 4 letters or shorter (1 in 2): `spil` → `SPIL`
3. Words are joined with a separator (`-` by default) until the password reaches a random target length between `--min` and `--max` (16–32 by default).
4. A candidate is rejected and regenerated unless it has at least three words, an uppercase letter, a digit, and at least 50 bits of entropy (`--min-bits`).

## Entropy

Entropy is measured against an attacker who knows the word list and exactly how passwords are built, so it never overstates strength. Each word in a password is traced back to the base words that could have produced it, and the exact probability of drawing it is computed from the transformation odds above. The password's entropy is the sum of `-log2(probability)` over its words.

Each word contributes about 12.5 bits from the word list plus about 0.5–7 bits from its transformations. Three-word passwords land around 42–50 bits and four or more words around 55 bits and up, so the default of 50 bits rejects most three-word candidates. Raise `--min-bits` (and `--max` if needed) for stronger passwords.

## Requirements

- Chez Scheme (tested with 10.4)

The Chez Scheme executable is named `chez` when installed with Homebrew, `scheme` when built from source, and `chezscheme` on Debian/Ubuntu. `chez-passgen` tries those names in that order, checking every match on your `PATH` and skipping other Schemes installed as `scheme`. To choose one explicitly, set `CHEZ` to a command name or path, e.g., `CHEZ=/opt/chez/bin/scheme chez-passgen`. The commands below use `scheme`, so substitute the name on your system.

## Usage

```
$ chez-passgen
canyon-BECK-3lcitrap-fry-till

$ chez-passgen -n 3 -b 70
lavish-walking-pseudo-IDE4-TEAM
retsam-bundl3-TIRW-salary-etaler
bas1c-dial-yrdnual-EB0L-thatcher
```

When a single password is generated, it is also copied to the clipboard using the first of `pbcopy`, `wl-copy`, `xclip`, or `xsel` that is installed. Pass `-c` to skip this.

```
Options:
  -n, --count N         number of passwords to generate (default 1)
      --min N           minimum length (default 16)
      --max N           maximum length (default 32)
  -s, --sep STR         word separator, no letters or digits (default "-")
  -b, --min-bits X      minimum entropy in bits, assuming the attacker knows
                        the word list and how passwords are built (default 50)
  -c, --no-copy         don't copy the password to the clipboard
  -h, --help            show this message
```

To run it as `chez-passgen` from anywhere, symlink it into a directory on your `PATH`, e.g.:

```
ln -s "$PWD/bin/chez-passgen" ~/.local/bin/chez-passgen
```

## Project layout

| Path | Description |
|------|-------------|
| `passgen.sls` | `(passgen)` library: randomness, word transformations, entropy, password assembly |
| `passgen/words.scm` | generated word list |
| `passgen.sps` | command-line interface |
| `bin/chez-passgen` | wrapper that sets the library path and runs the CLI |
| `data-scripts/build-word-list.ss` | rebuilds the word list |
| `tests/test-passgen.sps` | tests |

Run the tests:

```
CHEZSCHEMELIBDIRS=. scheme --script tests/test-passgen.sps
```

Rebuilding the word list is only needed to change it. The script filters the frequency lists in [zxcvbn-chez](https://github.com/hinkelman/zxcvbn-chez)'s `data` directory against `/usr/share/dict/words`:

```
scheme --script data-scripts/build-word-list.ss ../zxcvbn-chez/data
```

## License

MIT
