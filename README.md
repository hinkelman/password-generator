# password-generator

A [Chez Scheme](https://cisco.github.io/ChezScheme/) command-line tool that generates human-readable passwords such as `tongue-slip-past-SP1L` and `fron7ier-7RY-couch-touring`, using [zxcvbn-chez](https://github.com/hinkelman/zxcvbn-chez) to reject weak candidates.

## How passwords are built

1. Words are drawn from a list of ~5,700 common English words (`passgen/words.scm`) using `/dev/urandom` with rejection sampling, so every word is equally likely.
2. Each word is independently transformed:
   - reversed (1 in 4): `lips` → `spil`
   - one letter replaced with a look-alike digit (1 in 3): `a→4 e→3 i→1 o→0 s→5 t→7`, e.g., `hair` → `ha1r`
   - upcased if it is 4 letters or shorter (1 in 2): `spil` → `SPIL`
3. Words are joined with a separator (`-` by default) until the password reaches a random target length between `--min` and `--max` (16–32 by default).
4. A candidate is rejected and regenerated unless it has at least three words, an uppercase letter, a digit, and a zxcvbn estimate of at least 10^14 guesses (`--min-guesses`).

## Requirements

- Chez Scheme (tested with 10.4)
- A checkout of [zxcvbn-chez](https://github.com/hinkelman/zxcvbn-chez) with dependencies installed (`akku install`). By default it is expected next to this project (`../zxcvbn-chez`); set `ZXCVBN_CHEZ` to point elsewhere.

## Usage

```
$ bin/passgen
SWAP-5alary-poverty-injury

$ bin/passgen -n 3
c3remony-PAN-grade-happily-MET1
an5wer-KNEE-costly-average-A1D
kc0lc-eyd-QU1Z-dohtem
```

When a single password is generated, it is also copied to the clipboard using the first of `pbcopy`, `wl-copy`, `xclip`, or `xsel` that is installed. Pass `-c` to skip this.

```
Options:
  -n, --count N         number of passwords to generate (default 1)
      --min N           minimum length (default 16)
      --max N           maximum length (default 32)
  -s, --sep STR         word separator (default "-")
  -g, --min-guesses X   reject passwords that zxcvbn estimates take fewer
                        than 10^X guesses to crack (default 14)
  -c, --no-copy         don't copy the password to the clipboard
  -h, --help            show this message
```

`bin/passgen` can be symlinked onto your `PATH`.

### A note on strength

zxcvbn estimates how hard a password is to guess for an attacker who does *not* know how it was generated. An attacker who knows this scheme and word list faces roughly 12.5 bits per word plus about 2 bits per word from the transformations, so a three-word password has roughly 45 bits of entropy and a five-word password roughly 70. Raise `--min` for more words and more entropy.

## Project layout

| Path | Description |
|------|-------------|
| `passgen.sls` | `(passgen)` library: randomness, word transformations, password assembly |
| `passgen/words.scm` | generated word list |
| `passgen.sps` | command-line interface |
| `bin/passgen` | wrapper that sets the library path and runs the CLI |
| `data-scripts/build-word-list.ss` | rebuilds the word list from zxcvbn-chez's frequency lists and `/usr/share/dict/words` |
| `tests/test-passgen.sps` | SRFI 64 tests |

Rebuild the word list:

```
chez --script data-scripts/build-word-list.ss ../zxcvbn-chez/data
```

Run the tests:

```
CHEZSCHEMELIBDIRS=.:../zxcvbn-chez/.akku/lib chez --script tests/test-passgen.sps
```

## License

MIT
