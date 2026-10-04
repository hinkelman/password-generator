(library (passgen)
  (export generate-password
          make-password
          transform-word
          random-below
          word-list)

  (import (chezscheme))

  (include "passgen/words.scm")

  ;; randomness ------------------------------------------------------------------

  ;; Chez's `random` is not suitable for secrets, so draw bytes from the OS
  (define urandom #f)

  (define (random-bytes n)
    (unless urandom
      (set! urandom (open-file-input-port "/dev/urandom")))
    (get-bytevector-n urandom n))

  ;; uniform integer in [0, n) using rejection sampling to avoid modulo bias
  (define (random-below n)
    (unless (and (fixnum? n) (< 0 n (expt 2 32)))
      (assertion-violation 'random-below "n must be in [1, 2^32)" n))
    (let* ([range (expt 2 32)]
           [limit (- range (mod range n))])
      (let loop ()
        (let ([x (bytevector-u32-ref (random-bytes 4) 0 (endianness little))])
          (if (< x limit) (mod x n) (loop))))))

  ;; #t with probability p
  (define (random-chance p)
    (< (random-below (expt 2 31)) (* p (expt 2 31))))

  (define (random-element vec)
    (vector-ref vec (random-below (vector-length vec))))

  ;; word transformations ---------------------------------------------------------

  (define leet-table
    '((#\a . #\4) (#\e . #\3) (#\i . #\1) (#\o . #\0) (#\s . #\5) (#\t . #\7)))

  ;; replace one randomly chosen substitutable letter with its digit
  (define (leet word)
    (let ([positions (filter (lambda (i) (assv (string-ref word i) leet-table))
                             (iota (string-length word)))])
      (if (null? positions)
          word
          (let ([i (list-ref positions (random-below (length positions)))]
                [new (string-copy word)])
            (string-set! new i (cdr (assv (string-ref word i) leet-table)))
            new))))

  (define (reverse-word word)
    (list->string (reverse (string->list word))))

  ;; each transformation is applied independently, e.g.,
  ;;   lips -> spil (reverse) -> sp1l (leet) -> SP1L (upcase short word)
  (define (transform-word word)
    (let* ([w (if (random-chance 1/4) (reverse-word word) word)]
           [w (if (random-chance 1/3) (leet w) w)]
           [w (if (and (<= (string-length w) 4) (random-chance 1/2))
                  (string-upcase w)
                  w)])
      w))

  ;; password assembly ------------------------------------------------------------

  (define (join strs sep)
    (if (null? strs)
        ""
        (fold-left (lambda (acc s) (string-append acc sep s)) (car strs) (cdr strs))))

  (define (has-char? pred str)
    (exists pred (string->list str)))

  (define min-words 3)

  ;; Builds one candidate: words are added until the password reaches a target
  ;; length drawn uniformly from [min-length, max-length].
  ;; Returns #f if the candidate overshoots max-length or has too few words.
  (define (make-password min-length max-length sep)
    (let ([target (+ min-length (random-below (+ 1 (- max-length min-length))))])
      (let loop ([words (list (transform-word (random-element word-list)))])
        (let ([pw (join words sep)])
          (cond [(> (string-length pw) max-length) #f]
                [(>= (string-length pw) target)
                 (and (>= (length words) min-words) pw)]
                [else (loop (cons (transform-word (random-element word-list))
                                  words))])))))

  ;; Generates candidates until one satisfies the length bounds, has at least
  ;; `min-words` words, an uppercase letter, and a digit, and passes `accept?`
  ;; (e.g., a minimum strength estimate).
  (define generate-password
    (case-lambda
      [() (generate-password 16 32 "-" (lambda (pw) #t))]
      [(min-length max-length sep accept?)
       (unless (and (fixnum? min-length) (fixnum? max-length)
                    (<= 1 min-length max-length))
         (assertion-violation 'generate-password
                              "invalid length bounds" min-length max-length))
       (let loop ([attempts 0])
         (when (> attempts 100000)
           (error 'generate-password
                  "could not satisfy constraints; try relaxing them"))
         (let ([pw (make-password min-length max-length sep)])
           (if (and pw
                    (has-char? char-upper-case? pw)
                    (has-char? char-numeric? pw)
                    (accept? pw))
               pw
               (loop (+ attempts 1)))))]))

  )
