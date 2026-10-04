#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2026 Travis Hinkelman
;; SPDX-License-Identifier: MIT
#!r6rs

;; run from the project root
;; CHEZSCHEMELIBDIRS=. scheme --script tests/test-passgen.sps

(import (chezscheme)
        (passgen))

;; minimal test harness ---------------------------------------------------------

(define passes 0)
(define failures 0)

(define (report name ok?)
  (if ok?
      (set! passes (+ passes 1))
      (begin (set! failures (+ failures 1))
             (printf "FAIL: ~a\n" name))))

(define-syntax test-assert
  (syntax-rules ()
    [(_ name expr)
     (report name (guard (e [#t #f]) expr))]))

(define-syntax test-equal
  (syntax-rules ()
    [(_ name expected expr)
     (report name (guard (e [#t #f]) (equal? expected expr)))]))

(define-syntax test-error
  (syntax-rules ()
    [(_ name expr)
     (report name (guard (e [#t #t]) expr #f))]))

(define-syntax test-group
  (syntax-rules ()
    [(_ name body ...) (let () body ...)]))

(define (repeat n thunk)
  (map (lambda (i) (thunk)) (iota n)))

(define (split str ch)
  (let loop ([chars (string->list str)] [cur '()] [out '()])
    (cond [(null? chars) (reverse (cons (list->string (reverse cur)) out))]
          [(char=? (car chars) ch) (loop (cdr chars) '() (cons (list->string (reverse cur)) out))]
          [else (loop (cdr chars) (cons (car chars) cur) out)])))

(test-group "word-list"
  (test-assert "has thousands of words" (> (vector-length word-list) 5000))
  (test-assert "words are lowercase a-z, 2-8 letters"
    (for-all (lambda (w)
               (and (<= 2 (string-length w) 8)
                    (for-all (lambda (c) (char<=? #\a c #\z)) (string->list w))))
             (vector->list word-list))))

(test-group "random-below"
  (let ([xs (repeat 5000 (lambda () (random-below 7)))])
    (test-assert "in range" (for-all (lambda (x) (<= 0 x 6)) xs))
    (test-assert "hits every value"
      (for-all (lambda (v) (memv v xs)) (iota 7))))
  (test-equal "n = 1" 0 (random-below 1))
  (test-error "n = 0" (random-below 0)))

(test-group "transform-outcomes"
  (define (prob word token)
    (let ([o (assoc token (transform-outcomes word))]) (if o (cdr o) 0)))
  (test-equal "probabilities sum to 1" 1 (apply + (map cdr (transform-outcomes "calculator"))))
  (test-equal "unchanged long word" 1/2 (prob "calculator" "calculator"))
  (test-equal "reversed + leet + upcase" 1/48 (prob "lips" "SP1L"))
  (test-equal "no leet letters" 3/8 (prob "lump" "lump"))
  (test-equal "palindrome reversal merges" 1/2 (prob "pup" "pup")))

(test-group "password-bits"
  (define n (vector-length word-list))
  (define (log2 x) (log x 2))
  ;; harvest is unchanged with probability 3/4 * 2/3 = 1/2, i.e., 1 bit
  (test-assert "untransformed word costs log2(n) + 1"
    (< (abs (- (password-bits "harvest-harvest-harvest" "-")
               (* 3 (+ (log2 n) 1))))
       1e-9))
  (test-assert "rarer transformations cost more bits"
    (> (password-bits "h4rvest.harvest.harvest" ".")
       (password-bits "harvest.harvest.harvest" ".")))
  (test-error "rejects words not in the list" (password-bits "qzxv-lips-lips" "-")))

(test-group "transform-word"
  (define outputs (repeat 2000 (lambda () (transform-word "lips"))))
  (define (seen? s) (member s outputs))
  (test-assert "unchanged" (seen? "lips"))
  (test-assert "reversed" (seen? "spil"))
  (test-assert "leet" (seen? "l1ps"))
  (test-assert "upcased short word" (seen? "LIPS"))
  (test-assert "all combined" (seen? "SP1L"))
  (test-assert "long words are never upcased"
    (for-all (lambda (w) (not (exists char-upper-case? (string->list w))))
             (repeat 500 (lambda () (transform-word "calculator"))))))

(test-group "generate-password"
  (define pws (repeat 300 generate-password))
  (test-assert "default length is 16-32"
    (for-all (lambda (pw) (<= 16 (string-length pw) 32)) pws))
  (test-assert "at least three words"
    (for-all (lambda (pw) (>= (length (split pw #\-)) 3)) pws))
  (test-assert "has an uppercase letter"
    (for-all (lambda (pw) (exists char-upper-case? (string->list pw))) pws))
  (test-assert "has a digit"
    (for-all (lambda (pw) (exists char-numeric? (string->list pw))) pws))
  (test-assert "custom bounds and separator"
    (for-all (lambda (pw) (and (<= 20 (string-length pw) 22)
                               (>= (length (split pw #\.)) 3)))
             (repeat 100 (lambda () (generate-password 20 22 "." 0)))))
  (test-assert "min-bits is honored"
    (for-all (lambda (pw) (>= (password-bits pw "-") 60))
             (repeat 50 (lambda () (generate-password 16 32 "-" 60)))))
  (test-error "invalid bounds" (generate-password 32 16 "-" 0))
  (test-error "separator with a letter" (generate-password 16 32 "x" 0))
  (test-error "empty separator" (generate-password 16 32 "" 0))
  (test-error "unsatisfiable" (generate-password 16 16 "-" 200)))

(printf "~a passed, ~a failed\n" passes failures)
(exit (if (zero? failures) 0 1))
