#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2026 Travis Hinkelman
;; SPDX-License-Identifier: MIT
#!r6rs

;; Command-line interface. Run via the `bin/passgen` wrapper, which puts this
;; directory on the library path.

(import (chezscheme)
        (passgen))

(define usage "\
Usage: passgen [options]

Generate human-readable passwords like tongue-slip-past-SP1L.

Options:
  -n, --count N         number of passwords to generate (default 1)
      --min N           minimum length (default 16)
      --max N           maximum length (default 32)
  -s, --sep STR         word separator, no letters or digits (default \"-\")
  -b, --min-bits X      minimum entropy in bits, assuming the attacker knows
                        the word list and how passwords are built (default 50)
  -c, --no-copy         don't copy the password to the clipboard
  -h, --help            show this message

When generating a single password, it is also copied to the clipboard
(pbcopy, wl-copy, xclip, or xsel; whichever is found first).
")

(define (fail fmt . args)
  (apply fprintf (current-error-port) (string-append "passgen: " fmt "\n") args)
  (exit 1))

(define (parse-number flag str)
  (unless str (fail "~a expects a value" flag))
  (let ([n (string->number str)])
    (unless (and n (real? n) (>= n 0))
      (fail "~a expects a non-negative number, got ~s" flag str))
    n))

(define (parse-integer flag str)
  (let ([n (parse-number flag str)])
    (unless (integer? n)
      (fail "~a expects an integer, got ~s" flag str))
    (exact n)))

;; returns an alist of options
(define (parse-args args)
  (let loop ([args args]
             [opts '((count . 1) (min . 16) (max . 32) (sep . "-")
                     (min-bits . 50) (copy . #t))])
    (define (value) (if (null? (cdr args)) #f (cadr args)))
    (define (set key val) (cons (cons key val) opts))
    (if (null? args)
        opts
        (let ([flag (car args)])
          (cond [(member flag '("-h" "--help"))
                 (display usage)
                 (exit 0)]
                [(member flag '("-c" "--no-copy"))
                 (loop (cdr args) (set 'copy #f))]
                [(member flag '("-n" "--count"))
                 (loop (cddr* args) (set 'count (parse-integer flag (value))))]
                [(string=? flag "--min")
                 (loop (cddr* args) (set 'min (parse-integer flag (value))))]
                [(string=? flag "--max")
                 (loop (cddr* args) (set 'max (parse-integer flag (value))))]
                [(member flag '("-s" "--sep"))
                 (unless (value) (fail "~a expects a value" flag))
                 (loop (cddr* args) (set 'sep (value)))]
                [(member flag '("-b" "--min-bits"))
                 (loop (cddr* args) (set 'min-bits (parse-number flag (value))))]
                [else (fail "unknown option ~s (see --help)" flag)])))))

(define (cddr* args) (if (null? (cdr args)) '() (cddr args)))

(define (opt key opts) (cdr (assq key opts)))

(define clipboard-commands
  '("pbcopy" "wl-copy" "xclip -selection clipboard" "xsel --clipboard --input"))

(define (find-clipboard-command)
  (find (lambda (cmd)
          (let ([prog (car (split-words cmd))])
            (zero? (system (format "command -v ~a >/dev/null 2>&1" prog)))))
        clipboard-commands))

(define (split-words str)
  (let loop ([chars (string->list str)] [cur '()] [out '()])
    (cond [(null? chars)
           (reverse (if (null? cur) out (cons (list->string (reverse cur)) out)))]
          [(char=? (car chars) #\space)
           (loop (cdr chars) '() (if (null? cur) out (cons (list->string (reverse cur)) out)))]
          [else (loop (cdr chars) (cons (car chars) cur) out)])))

;; Writes str to the clipboard command's stdin (no shell quoting involved).
;; Returns #t on success.
(define (copy-to-clipboard str)
  (let ([cmd (find-clipboard-command)])
    (and cmd
         (let-values ([(to-stdin from-stdout from-stderr pid)
                       (open-process-ports cmd (buffer-mode block) (native-transcoder))])
           (put-string to-stdin str)
           (close-port to-stdin)
           (close-port from-stdout)
           (close-port from-stderr)
           #t))))

(define (main args)
  (let* ([opts (parse-args args)]
         [count (opt 'count opts)]
         [min-length (opt 'min opts)]
         [max-length (opt 'max opts)]
         [sep (opt 'sep opts)])
    (unless (<= 1 min-length max-length)
      (fail "--min must be at least 1 and no greater than --max"))
    (when (or (string=? sep "")
              (exists (lambda (c) (or (char-alphabetic? c) (char-numeric? c)))
                      (string->list sep)))
      (fail "--sep must be non-empty and contain no letters or digits"))
    (let ([pws (map (lambda (i)
                      (guard (e [(error? e)
                                 (fail "could not generate a password with these settings; try a larger --max or smaller --min-bits")])
                        (generate-password min-length max-length sep (opt 'min-bits opts))))
                    (iota count))])
      (for-each (lambda (pw) (printf "~a\n" pw)) pws)
      (when (and (= count 1) (opt 'copy opts))
        (unless (copy-to-clipboard (car pws))
          (fprintf (current-error-port)
                   "passgen: no clipboard command found; password not copied\n"))))))

(main (cdr (command-line)))
