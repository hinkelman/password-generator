#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2026 Travis Hinkelman
;; SPDX-License-Identifier: MIT
#!r6rs

;; run from the project root (chez-srfi comes from zxcvbn-chez's Akku install)
;; CHEZSCHEMELIBDIRS=.:../zxcvbn-chez/.akku/lib chez --script tests/test-passgen.sps

(import (chezscheme)
        (srfi :64 testing)
        (passgen))

(define (repeat n thunk)
  (map (lambda (i) (thunk)) (iota n)))

(define (split str ch)
  (let loop ([chars (string->list str)] [cur '()] [out '()])
    (cond [(null? chars) (reverse (cons (list->string (reverse cur)) out))]
          [(char=? (car chars) ch) (loop (cdr chars) '() (cons (list->string (reverse cur)) out))]
          [else (loop (cdr chars) (cons (car chars) cur) out)])))

(test-begin "passgen")

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
             (repeat 100 (lambda () (generate-password 20 22 "." (lambda (pw) #t))))))
  (test-assert "accept? predicate is honored"
    (for-all (lambda (pw) (char=? (string-ref pw 0) #\a))
             (repeat 20 (lambda ()
                          (generate-password 16 32 "-"
                                             (lambda (pw) (char=? (string-ref pw 0) #\a)))))))
  (test-error "invalid bounds" (generate-password 32 16 "-" (lambda (pw) #t)))
  (test-error "unsatisfiable" (generate-password 16 32 "-" (lambda (pw) #f))))

(test-end "passgen")

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
